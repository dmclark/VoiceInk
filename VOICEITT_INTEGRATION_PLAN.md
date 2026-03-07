# Voiceitt Integration Plan for VoiceInk

## Overview

Add Voiceitt as a streaming transcription provider in VoiceInk, enabling real-time speech-to-text for people with non-standard speech. Voiceitt uses per-user trained models accessed via a Socket.IO WebSocket connection.

---

## Architecture Fit

VoiceInk's `StreamingTranscriptionProvider` protocol maps almost 1:1 to Voiceitt's API:

| VoiceInk Protocol | Voiceitt Equivalent |
|---|---|
| `connect(model:language:)` | Socket.IO connect → wait for `connection_ready` + `model_ready` |
| `sendAudioChunk(Data)` | `stream_audio_samples` (Int16 array) or `stream_compressed_audio` |
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
| `set_options` | `{ recognition_mode: "dictation", save_audio: true }` | On socket open |
| `stream_audio_samples` | `([Int16], "int16")` | Each audio chunk |
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
| `reset_alb_cookies` | — | Reconnect |
| `error` | varies | `.error(...)` |

### Ready State

`isReady = socket.connected && connection_ready && model_status == .ready`

Both `connection_ready` AND `model_ready` must fire before audio can be sent. Model loading can take seconds (per-user trained model).

---

## Auth Flow

Voiceitt uses email/password login, NOT a simple API key:

1. `POST` to `https://api2.voiceitt.com` via `VoiceittApi.signInWithEmail(appId, apiKey, email, password)`
2. Returns `{ token, refresh_token, token_expires_at, refresh_token_expires_at }`
3. Tokens passed in Socket.IO `auth` handshake
4. SDK auto-refreshes via `token_updated` event → emits `refresh_token` on socket

### Credential Storage

Store in Keychain via `APIKeyManager`:
- `voiceittEmail` — user email
- `voiceittToken` — JWT token
- `voiceittRefreshToken` — refresh token
- `voiceittAppId` — app ID (or hardcode)
- `voiceittApiKey` — API key (or hardcode)

Alternatively, store email + password and re-auth on each session (simpler, avoids token refresh complexity in Swift).

---

## Implementation Steps

### Phase 1: Dependencies & Model Registration

**1.1 Add Socket.IO Swift package**
- Add `https://github.com/socketio/socket.io-client-swift` as SPM dependency in Xcode project
- Target version: latest stable (v16.x)

**1.2 Add `.voiceitt` to `ModelProvider` enum**
- File: `VoiceInk/Models/TranscriptionModel.swift`
- Add `case voiceitt = "Voiceitt"` to `ModelProvider`

**1.3 Create `VoiceittModel` struct** (or reuse `CloudModel`)
- File: `VoiceInk/Models/TranscriptionModel.swift`
- Simple struct conforming to `TranscriptionModel`
- Single model: name `"voiceitt-personal"`, displayName `"Voiceitt Personal Model"`
- `isMultilingualModel = false` (Voiceitt models are language-specific, trained per user)

**1.4 Register predefined Voiceitt model**
- File: `VoiceInk/Models/PredefinedModels.swift`
- Add Voiceitt model entry to the catalog

**1.5 Add Voiceitt to `APIKeyManager`**
- File: `VoiceInk/Services/APIKeyManager.swift`
- Add `"voiceitt": "voiceittAPIKey"` to `providerToKeychainKey`
- May also need keychain entries for email, token, refresh token

### Phase 2: Streaming Provider

**2.1 Create `VoiceittStreamingProvider.swift`**
- File: `VoiceInk/Services/StreamingTranscription/VoiceittStreamingProvider.swift`
- Implements `StreamingTranscriptionProvider`
- Uses `SocketIO` (socket.io-client-swift) to connect to `casr-dictation-recognition.voiceitt.com`

```
Key implementation details:

connect(model:language:):
  1. Retrieve token + refreshToken from Keychain
  2. Create SocketManager with URL, auth: { token, refresh_token }
  3. Connect socket
  4. On "open" → emit set_options { recognition_mode: "dictation", save_audio: true }
  5. Listen for connection_ready → set flag
  6. Listen for model_ready → set flag, yield .sessionStarted
  7. Listen for model_loading → (optional: surface as status)
  8. Listen for model_missing / model_loading_error → yield .error
  9. Listen for partial_recognition → yield .partial(text:)
  10. Listen for recognition → yield .committed(text:)
  11. Listen for reset_alb_cookies → disconnect + reconnect
  12. Listen for error → yield .error
  13. Wait (with 120s timeout) until both flags are true

sendAudioChunk(Data):
  - Convert Data (PCM Int16 LE bytes) to [Int16] array
  - Emit "stream_audio_samples" with (samples, "int16")
  - OR: send raw Data as compressed audio if format allows

commit():
  - Emit "stop_stream_processing"

disconnect():
  - socket.disconnect()
  - Clean up continuation
```

**2.2 Wire into `StreamingTranscriptionService`**
- File: `VoiceInk/Services/StreamingTranscription/StreamingTranscriptionService.swift`
- Add to `createProvider(for:)`:
  ```swift
  case .voiceitt:
      return VoiceittStreamingProvider()
  ```

**2.3 Wire into `TranscriptionServiceRegistry`**
- File: `VoiceInk/Services/TranscriptionServiceRegistry.swift`
- Add to `supportsStreaming(model:)`:
  ```swift
  case .voiceitt:
      return true  // all Voiceitt models are streaming-only
  ```
- No batch fallback needed (Voiceitt has no REST API)

### Phase 3: Auth UI

**3.1 Login view for Voiceitt credentials**
- Need a settings view where user enters email + password
- On submit: call Voiceitt auth REST API from Swift (replicate `signInWithEmail`)
  - `POST https://api2.voiceitt.com/...` with `{ app_id, api_key, email, password }`
  - Store returned tokens in Keychain
- This is different from other providers which just need an API key text field

**3.2 Voiceitt auth REST client (Swift)**
- Small helper to call `signInWithEmail` equivalent
- Need to reverse-engineer the exact REST endpoint from `voiceitt-sdk-js/src/lib/api.ts`
- Returns: `{ token, refresh_token, token_expires_at, refresh_token_expires_at }`

### Phase 4: Token Refresh

**4.1 Handle token expiry**
- Check `token_expires_at` before connecting
- If expired, use refresh token to get new token (or re-login)
- During active session: if server sends `refresh_token` request, handle it

**4.2 Handle `reset_alb_cookies`**
- Server can request a reconnection mid-session
- Provider should disconnect and reconnect transparently
- May cause brief interruption in transcription

---

## Voiceitt-Specific Differences from Other Providers

| Aspect | Other Providers | Voiceitt |
|---|---|---|
| Auth | Simple API key | Email/password → token/refresh |
| Connection ready | Immediate after WS handshake | Must wait for `connection_ready` + `model_ready` |
| Model loading | Instant | Per-user model loads on server (can take seconds) |
| Commit/finalize | Explicit `commit()` message | `stop_stream_processing` (less formal) |
| Batch fallback | REST API available | No REST API — streaming only |
| Reconnection | Not needed | Server can request via `reset_alb_cookies` |
| Transport | Raw WebSocket | Socket.IO (over WebSocket) |

---

## Risks & Open Questions

1. **Socket.IO Swift client compatibility** — ✅ RESOLVED. Server uses Socket.IO v3/v4. Use `.version(.three)` config and `socket.connect(withPayload:)` for auth. `.connectParams` does NOT work (puts tokens in URL query, server ignores). See `notes/debugging.md`.

2. **Audio chunk format** — VoiceInk provides `Data` (raw PCM Int16 bytes). Need to convert to `[Int16]` array for `stream_audio_samples`, or send as binary via `stream_compressed_audio`. Test which the server prefers from a non-JS client.

3. **No batch/REST fallback** — ✅ RESOLVED. Added guard in `TranscriptionSession.swift` — if streaming fails and the fallback provider's API key is missing, surfaces the streaming error instead of a confusing "API key missing" for the fallback provider (Groq). See `notes/debugging.md`.

4. **Auth UX** — Other providers use a simple API key paste. Voiceitt needs email/password login UI + token management. This is the largest UX addition.

5. **Token refresh in Swift** — Need to replicate the SDK's `VoiceittAuthProvider` token refresh logic. Examine `src/lib/auth.ts` for the refresh endpoint.

6. **App ID / API Key** — These are developer credentials (not user credentials). Currently user-provided via the VoiceittModelCardView login form. Stored in Keychain as `voiceittAppId` / `voiceittApiKey`.

7. **Model lifecycle UX** — Model loading can take several seconds. VoiceInk's UI may need a "model loading..." state between "connecting" and "ready". Other providers don't have this delay.

---

## File Change Summary

| File | Action | Lines (est.) |
|---|---|---|
| `TranscriptionModel.swift` | Edit: add `.voiceitt` enum case | +1 |
| `PredefinedModels.swift` | Edit: add Voiceitt model | +10 |
| `APIKeyManager.swift` | Edit: add voiceitt key mapping | +1 |
| `StreamingTranscriptionService.swift` | Edit: add case in `createProvider` | +2 |
| `TranscriptionServiceRegistry.swift` | Edit: add to `supportsStreaming` | +2 |
| **`VoiceittStreamingProvider.swift`** | **Create: full Socket.IO provider** | **~200** |
| **`VoiceittAuthService.swift`** | **Create: login + token management** | **~100** |
| Settings UI (TBD) | Edit: add Voiceitt login section | ~50 |
| Xcode project | Edit: add SPM dependency | — |

**Total estimated: ~370 lines of new/changed code**

---

## Suggested Order of Work

1. Fork & branch ✅ (`feature/voiceitt-provider`)
2. Add socket.io-client-swift SPM dependency
3. Add `.voiceitt` to `ModelProvider` + predefined model
4. Build `VoiceittStreamingProvider.swift` (core integration)
5. Build `VoiceittAuthService.swift` (login + token storage)
6. Wire into registry + service
7. Add settings UI for Voiceitt login
8. Test end-to-end: login → connect → stream audio → see transcription
9. Handle edge cases: token refresh, `reset_alb_cookies`, model loading states
