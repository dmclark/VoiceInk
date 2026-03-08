# Voiceitt Integration Plan for VoiceInk

## Overview

Add Voiceitt as a streaming transcription provider in VoiceInk, enabling real-time speech-to-text for people with non-standard speech. Voiceitt uses per-user trained models accessed via a Socket.IO WebSocket connection.

---

## Current Status: ✅ MOSTLY COMPLETE

The core integration is done. All major components exist and are wired together:

### ✅ Completed

| Component | File | Status |
|---|---|---|
| `.voiceitt` enum case in `ModelProvider` | `TranscriptionModel.swift` | ✅ Done |
| Predefined model (`voiceitt-personal`) | `PredefinedModels.swift` | ✅ Done |
| API key mapping in `APIKeyManager` | `APIKeyManager.swift` | ✅ Done |
| Socket.IO SPM dependency | Xcode project | ✅ Done |
| `VoiceittStreamingProvider` | `VoiceittStreamingProvider.swift` | ✅ Done |
| `VoiceittAuthService` (login + token storage) | `VoiceittAuthService.swift` | ✅ Done |
| Login UI (email/password/appId/apiKey) | `VoiceittModelCardView.swift` | ✅ Done |
| Wired into `StreamingTranscriptionService.createProvider` | `StreamingTranscriptionService.swift` | ✅ Done |
| Wired into `TranscriptionServiceRegistry.supportsStreaming` | `TranscriptionServiceRegistry.swift` | ✅ Done |
| Batch fallback guard (no confusing Groq key error) | `TranscriptionSession.swift` | ✅ Done |
| Voiceitt shown in model list | `ModelManagementView.swift` | ✅ Done |
| Token refresh before connect | `VoiceittStreamingProvider.swift` | ✅ Done |
| Server-side token refresh (`token_updated` event) | `VoiceittStreamingProvider.swift` | ✅ Done |
| Connect/stop race fix (await connection in `transcribe()`) | `TranscriptionSession.swift` | ✅ Done |
| Partial transcript display in mini recorder | `MiniRecorderView.swift` | ✅ Done |

### 🔧 Remaining Work

| Issue | Priority | Status | Details |
|---|---|---|---|
| Validate `set_options` timing | High | ⬜ TODO | Currently sent after `model_ready`. Plan says send on socket open. Verify against VS Code extension behavior. |
| `reset_alb_cookies` handling | Medium | ⬜ Partial | Currently emits an error event. Should either reconnect transparently or surface a clear retry message. |
| Groq fallback policy for Voiceitt | Medium | ⬜ TODO | Silent fallback to Groq Whisper is bad for non-standard speech users — Groq won't understand them. Consider disabling fallback for `.voiceitt` or making it explicit. |
| `save_audio` privacy decision | Low | ⬜ TODO | Currently hardcoded `true` in `set_options`. Should be `false` unless user opts in or Voiceitt requires it. |
| End-to-end testing | High | ⬜ TODO | Login → connect → stream audio → see partial/final transcription. |

---

## Architecture Fit

VoiceInk's `StreamingTranscriptionProvider` protocol maps almost 1:1 to Voiceitt's API:

| VoiceInk Protocol | Voiceitt Equivalent |
|---|---|
| `connect(model:language:)` | Socket.IO connect → wait for `connection_ready` + `model_ready` |
| `sendAudioChunk(Data)` | `stream_audio_samples` (binary Data + "int16") |
| `commit()` | `stop_stream_processing` |
| `disconnect()` | Socket disconnect |
| `.partial(text:)` event | `partial_recognition` → `{ text, unstable_text }` |
| `.committed(text:)` event | `recognition` → `{ text }` |

Audio format already matches: VoiceInk's `CoreAudioRecorder` outputs **16kHz mono PCM Int16 little-endian** — exactly what Voiceitt expects.

---

## Voiceitt Wire Protocol (Socket.IO)

**Server URL:** `https://casr-dictation-recognition.voiceitt.com`
**Transport:** Socket.IO (`/socket.io` path, `websocket` + `polling` transports)
**Auth:** Passed in Socket.IO `auth` field: `{ token, refresh_token }`
**Swift note:** `socket.io-client-swift` v16.x has no `.auth` config option. Use `socket.connect(withPayload: ["token": t, "refresh_token": rt])` instead — this sends credentials in the Socket.IO CONNECT packet body (`socket.handshake.auth`). Do NOT use `.connectParams` which puts them in the URL query string and the server ignores them.

### Client → Server Events

| Event | Payload | When |
|---|---|---|
| `set_options` | `{ recognition_mode: "dictation", save_audio: true }` | On socket open (⚠️ verify timing) |
| `stream_audio_samples` | `(Data, "int16")` | Each audio chunk (binary Data, not [Int16] array) |
| `stream_compressed_audio` | `(ArrayBuffer, mimeType)` | Alt: compressed audio |
| `refresh_token` | `{ token: "..." }` | When token refreshed |
| `stop_stream_processing` | — | On commit/stop |

### Server → Client Events

| Event | Payload | Maps to |
|---|---|---|
| `connection_ready` | — | Internal state |
| `model_loading` | — | Internal state (connecting) |
| `model_ready` | — | Internal state → `.sessionStarted` |
| `model_missing` | — | `.error(...)` |
| `model_loading_error` | — | `.error(...)` |
| `partial_recognition` | `{ text, unstable_text }` | `.partial(text:)` |
| `recognition` | `{ text }` | `.committed(text:)` |
| `reset_alb_cookies` | — | Reconnect (⚠️ not fully handled yet) |
| `error` | varies | `.error(...)` |
| `token_updated` | `{ token, refresh_token? }` | Persist new tokens |

### Ready State

`isReady = socket.connected && connection_ready && model_status == .ready`

Both `connection_ready` AND `model_ready` must fire before audio can be sent. Model loading can take seconds (per-user trained model).

---

## Auth Flow

Voiceitt uses email/password login, NOT a simple API key:

1. `POST` to `https://api2.voiceitt.com` via `VoiceittAuthService.signIn()`
2. Returns `{ token, refresh_token, token_expires_at, refresh_token_expires_at }`
3. Tokens passed in Socket.IO `auth` handshake
4. Server auto-refreshes via `token_updated` event → persisted by `VoiceittStreamingProvider`

### Credential Storage

Stored in Keychain:
- `voiceittAPIKey` — JWT access token (via `APIKeyManager`)
- `voiceittRefreshToken` — refresh token (via `KeychainService`)
- `voiceittEmail` — user email
- `voiceittAppId` — developer app ID
- `voiceittApiKey` — developer API key
- Token expiry timestamps (via `KeychainService`)

Auth is owned by `VoiceittAuthService` (singleton). `APIKeyManager` stores the access token for compatibility with VoiceInk's existing key-checking patterns.

---

## Key Bug Fix: Connect/Stop Race Condition

### Problem

`StreamingTranscriptionSession.prepare()` starts the Socket.IO connection in a background `Task.detached` and returns immediately. For fast providers (Deepgram, ElevenLabs), the connection is ready before the user stops recording. But Voiceitt's model loading can take **several seconds**.

If the user stops recording before the connection is ready:
1. `transcribe()` calls `stopAndGetFinalText()`
2. `StreamingTranscriptionService` is still in `.connecting` state
3. `stopAndGetFinalText()` requires `state == .streaming` → throws `notConnected`
4. Falls back to Groq Whisper (useless for non-standard speech)

### Fix (Applied)

Store the connection `Task` and `await` it in `transcribe()` before calling `stopAndGetFinalText()`:

```swift
// In StreamingTranscriptionSession:
private var connectTask: Task<Void, Error>?

func prepare(...) {
    connectTask = Task.detached { ... }
}

func transcribe(...) {
    // Wait for connection to finish (critical for Voiceitt)
    if let connectTask {
        try await connectTask.value
    }
    // Now safe to call stopAndGetFinalText()
}
```

This ensures the streaming service reaches `.streaming` state before we try to finalize, regardless of how long model loading takes.

---

## Voiceitt-Specific Differences from Other Providers

| Aspect | Other Providers | Voiceitt |
|---|---|---|
| Auth | Simple API key | Email/password → token/refresh |
| Connection ready | Immediate after WS handshake | Must wait for `connection_ready` + `model_ready` |
| Model loading | Instant | Per-user model loads on server (can take seconds) |
| Commit/finalize | Explicit `commit()` message | `stop_stream_processing` |
| Batch fallback | REST API available | No REST API — streaming only |
| Reconnection | Not needed | Server can request via `reset_alb_cookies` |
| Transport | Raw WebSocket | Socket.IO (over WebSocket) |

---

## Risks & Open Questions

1. **Socket.IO Swift client compatibility** — ✅ RESOLVED. Server uses Socket.IO v3/v4. Use `.version(.three)` config and `socket.connect(withPayload:)` for auth.

2. **Audio chunk format** — ✅ RESOLVED. Sending binary `Data` (not `[Int16]` array) via `socket.emit("stream_audio_samples", data, "int16")`. Socket.IO Swift treats `Data` as binary, matching the JS SDK's `ArrayBuffer` behavior.

3. **No batch/REST fallback** — ✅ RESOLVED. Guard in `TranscriptionSession.swift` surfaces the streaming error instead of a confusing "API key missing" for Groq.

4. **Connect/stop race** — ✅ RESOLVED. `StreamingTranscriptionSession` now awaits the connection task in `transcribe()` before calling `stopAndGetFinalText()`.

5. **`set_options` timing** — ⚠️ OPEN. Currently sent after `model_ready`. The plan originally said send on socket open. Need to verify which the server expects by comparing with the working VS Code extension.

6. **`reset_alb_cookies`** — ⚠️ OPEN. Currently emits error. v1: fail with clear retry message. v2: transparent reconnect if it proves common.

7. **Groq fallback for Voiceitt** — ⚠️ OPEN. Silent fallback to Groq is harmful for non-standard speech users. Should disable or make explicit.

8. **App ID / API Key** — Currently user-provided via login form. Acceptable for private/internal use. Would need to be bundled or hidden for a public release.

9. **Model lifecycle UX** — Model loading can take several seconds. Consider showing a "loading personal model..." state in the recorder UI.

---

## File Summary

| File | Status |
|---|---|
| `VoiceInk/Models/TranscriptionModel.swift` | ✅ `.voiceitt` enum case exists |
| `VoiceInk/Models/PredefinedModels.swift` | ✅ Voiceitt model registered |
| `VoiceInk/Services/APIKeyManager.swift` | ✅ Voiceitt key mapping exists |
| `VoiceInk/Services/StreamingTranscription/StreamingTranscriptionService.swift` | ✅ `.voiceitt` case in `createProvider` |
| `VoiceInk/Services/TranscriptionServiceRegistry.swift` | ✅ `.voiceitt` in `supportsStreaming` + batch fallback to Groq |
| `VoiceInk/Services/TranscriptionSession.swift` | ✅ Connect/stop race fix applied |
| `VoiceInk/Services/StreamingTranscription/VoiceittStreamingProvider.swift` | ✅ Full Socket.IO provider (~217 lines) |
| `VoiceInk/Services/VoiceittAuthService.swift` | ✅ Login + token management |
| `VoiceInk/Views/AI Models/VoiceittModelCardView.swift` | ✅ Login UI |
| `VoiceInk/Views/AI Models/ModelManagementView.swift` | ✅ Voiceitt in provider list |
| `VoiceInk/Views/Recorder/MiniRecorderView.swift` | ✅ Partial transcript display added |

---

## Next Steps

1. **Verify `set_options` timing** — Compare current code with the working VS Code extension (`/Users/dzc86/voiceitt/src/voiceittSocket.ts`). Move to socket open if needed.
2. **End-to-end test** — Login → select Voiceitt model → record → verify partial + final transcription.
3. **Decide fallback policy** — Disable silent Groq fallback for Voiceitt, or surface it explicitly.
4. **Handle `reset_alb_cookies`** — Start with fail-fast + clear error message.
5. **Privacy** — Change `save_audio` to `false` by default.
