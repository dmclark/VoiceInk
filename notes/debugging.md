# Voiceitt Integration Debugging Notes

## Issue: "Transcription Failed: API key for this service is missing"

**Reported:** User could log in via VoiceittModelCardView, but transcription failed with a misleading "API key missing" error.

### Root Cause 1: Socket.IO auth sent incorrectly

The `VoiceittStreamingProvider` was passing `token` and `refresh_token` as `.connectParams` (URL query string parameters), but the Voiceitt CASR server expects them in the **Socket.IO `auth` field** (`socket.handshake.auth`).

The Swift Socket.IO client (v16.1.1) doesn't have an `.auth` config option. Instead, auth must be passed via `socket.connect(withPayload:)`, which sends credentials in the Socket.IO CONNECT packet body.

**Before (broken):**
```swift
let manager = SocketManager(socketURL: url, config: [
    .log(false),
    .forceWebsockets(true),
    .connectParams(["token": token, "refresh_token": refreshToken])
])
socket.connect()
```

**After (fixed):**
```swift
let manager = SocketManager(socketURL: url, config: [
    .log(false),
    .version(.three)
])
socket.connect(withPayload: ["token": token, "refresh_token": refreshToken])
```

**Reference:** Confirmed against the official Voiceitt JS SDK at `https://gitlab.com/voiceitt-sdk/voiceitt-sdk-js` — see `src/websocket.ts` which uses `auth: { token, refresh_token }`.

### Root Cause 2: Misleading error from Groq fallback

When Voiceitt streaming failed (due to Root Cause 1), the `StreamingTranscriptionSession` silently fell back to batch transcription using Groq Whisper (`whisper-large-v3-turbo`). Since no Groq API key was configured, `CloudTranscriptionService.requireAPIKey` threw `missingAPIKey`, producing the confusing user-facing error.

**Fix:** Added a guard in `TranscriptionSession.swift` that checks whether the fallback provider's API key exists before attempting fallback. If missing, surfaces the original streaming error instead.

### Files Changed

| File | Change |
|---|---|
| `VoiceittStreamingProvider.swift` | Use `socket.connect(withPayload:)` instead of `.connectParams`; removed `.forceWebsockets(true)`, added `.version(.three)`; improved error logging |
| `TranscriptionSession.swift` | Guard against fallback to provider with missing API key |

### Debugging Tips

- Filter Console.app by `VoiceittStreamingProvider` or `VoiceittAuthService` to see connection/auth logs.
- Socket.IO errors during setup are now logged with the message content.
- Token refresh failures are now logged (previously swallowed by `try?`).

### Transcription Log
Transcription history is stored in a SwiftData SQLite database at:

~/Library/Application Support/com.prakashjoshipax.VoiceInk/default.store

This is a standard SQLite file. You can query it externally with sqlite3:

sqlite3 ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/default.store \
  "SELECT * FROM ZTRANSCRIPTION;"

The Transcription model has columns: id (UUID), text, enhancedText, timestamp, duration, audioFileURL, transcriptionModelName, aiEnhancementModelName, promptName, transcriptionDuration, enhancementDuration, powerModeName, and transcriptionStatus. Note that SwiftData/Core Data prefixes column names with Z (e.g., ZTEXT, ZTIMESTAMP), so explore the schema first with .schema to see exact names.

```
sqlite3 ~/Library/Application\ Support/com.prakashjoshipax.VoiceInk/default.store \
  "SELECT ztimestamp, zduration FROM ZTRANSCRIPTION;"