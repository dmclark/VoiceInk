# VoiceInk — Architecture & Developer Guide

> **What is VoiceInk?** A native macOS app (Swift / SwiftUI, requires macOS 14.4+) that transcribes speech to text and pastes it at the cursor. It supports local Whisper models, NVIDIA Parakeet, Apple's native Speech framework, and cloud providers (Groq, ElevenLabs, Deepgram, Mistral, Gemini, Soniox) — including real-time streaming for some of them. It optionally enhances transcriptions with LLM-powered AI before pasting.
>
> This is an **experimental fork** of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk) maintained by @dmclark to explore [Voiceitt](https://voiceitt.com) integration for non-standard speech.

---

## High-Level Data Flow

```
Hotkey press → RecorderUIManager shows mini/notch recorder
            → VoiceInkEngine.toggleRecord()
            → Recorder.startRecording() (CoreAudioRecorder captures PCM)
            → [if streaming model] TranscriptionSession.prepare() opens WebSocket,
              audio chunks are forwarded live via onAudioChunk callback
            → User releases hotkey / presses again → toggleRecord() stops recording
            → TranscriptionSession.transcribe() gets final text
              (streaming: commit + drain; file-based: upload WAV)
            → TranscriptionPipeline.run():
                filter → format → word-replace → prompt-detect → AI enhance → save → paste
            → CursorPaster.pasteAtCursor() inserts text into the active app
```

---

## Core Components

### 1. App Entry Point — `VoiceInk.swift`

The `@main` SwiftUI `App`. Initializes **all** top-level services and managers in `init()`:

- **`ModelContainer`** (SwiftData) — two stores: `default.store` for `Transcription` records, `dictionary.store` for `VocabularyWord` / `WordReplacement` (synced to iCloud in non-local builds).
- Creates `WhisperModelManager`, `ParakeetModelManager`, `TranscriptionModelManager`, `VoiceInkEngine`, `RecorderUIManager`, `HotkeyManager`, `AIService`, `AIEnhancementService`, `MenuBarManager`, etc.
- Injects everything as `@StateObject` / `.environmentObject` into the SwiftUI view hierarchy.
- Has a persistent `MenuBarExtra` (system tray icon) and a main `WindowGroup`.

### 2. Audio Capture — `CoreAudioRecorder.swift` + `Recorder.swift`

**`CoreAudioRecorder`** is the low-level audio engine. Uses Apple's AUHAL (Audio Unit HAL) API directly — no AVAudioEngine.

- Captures from a specific `AudioDeviceID` (does **not** change the system default device).
- Outputs **16 kHz, mono, PCM Int16, little-endian** WAV files.
- Internally converts from the device's native format (arbitrary sample rate, multi-channel, Float32) via linear interpolation + channel mixing in the real-time audio callback.
- Exposes an **`onAudioChunk`** callback that fires on the audio thread with the same 16kHz mono Int16 PCM data — this is what streaming providers consume.
- Supports **mid-recording device switching** (`switchDevice(to:)`).

**`Recorder`** is the `@MainActor` wrapper. Manages lifecycle, audio metering (EMA-smoothed for UI), media pause/resume (mutes system audio during recording via `MediaController`), and device-switch notifications.

### 3. Models & Providers — `TranscriptionModel.swift` + `PredefinedModels.swift`

**`ModelProvider` enum:** `local`, `parakeet`, `groq`, `elevenLabs`, `deepgram`, `mistral`, `gemini`, `soniox`, `custom`, `nativeApple` (and `voiceitt` on the feature branch).

**Model types** (all conform to `TranscriptionModel` protocol):
- `LocalModel` — Whisper `.bin` files downloaded from HuggingFace
- `ImportedLocalModel` — user-imported local Whisper models
- `ParakeetModel` — NVIDIA Parakeet (uses FluidAudio framework)
- `NativeAppleModel` — Apple Speech framework (macOS 26+)
- `CloudModel` — all cloud providers (Groq, ElevenLabs, Deepgram, etc.)
- `CustomCloudModel` — user-defined OpenAI-compatible endpoints

**`PredefinedModels`** contains the static list of all built-in models. The `models` computed property merges predefined + user custom models.

**`TranscriptionModelManager`** tracks which models are available (downloaded / API key present) and which one is currently selected.

### 4. Transcription Service Layer

**`TranscriptionService` protocol:** Single method: `transcribe(audioURL:model:) → String`. Implementations:
- `LocalTranscriptionService` — runs whisper.cpp via `LibWhisper`
- `ParakeetTranscriptionService` — runs NVIDIA Parakeet via FluidAudio
- `NativeAppleTranscriptionService` — Apple Speech framework
- `CloudTranscriptionService` — dispatches to provider-specific HTTP clients (Groq/OpenAI-compatible, ElevenLabs, Deepgram, Mistral, Gemini, Soniox)

**`TranscriptionServiceRegistry`** is the central router. It:
- Maps `ModelProvider` → `TranscriptionService`
- Decides if a model supports streaming (`supportsStreaming()`)
- Creates the right `TranscriptionSession` (streaming or file-based)
- Handles **batch fallback models** for streaming-only models (e.g. Mistral realtime → Mistral batch, Soniox RT → Soniox async)

### 5. Streaming Transcription

**`StreamingTranscriptionProvider` protocol:** `connect()`, `sendAudioChunk()`, `commit()`, `disconnect()`, plus `transcriptionEvents: AsyncStream<StreamingTranscriptionEvent>`.

Events: `.sessionStarted`, `.partial(text:)`, `.committed(text:)`, `.error(Error)`.

**Implementations** (all use raw WebSockets via `URLSessionWebSocketTask`, except Voiceitt):
- `ElevenLabsStreamingProvider`
- `DeepgramStreamingProvider`
- `MistralStreamingProvider`
- `SonioxStreamingProvider`
- `VoiceittStreamingProvider` *(feature branch — uses Socket.IO)*

**`StreamingTranscriptionService`** orchestrates the lifecycle:
1. Creates the provider via `createProvider(for:)`
2. Connects, starts a send loop (drains an `AsyncStream<Data>` of audio chunks), starts an event consumer (accumulates committed segments, forwards partials)
3. On stop: drains remaining chunks, sends commit, waits for server acknowledgment (10s timeout)
4. Returns joined committed segments as the final text

**`TranscriptionSession` protocol:** Abstracts streaming vs file-based. Two implementations:
- `FileTranscriptionSession` — just calls `TranscriptionService.transcribe()` after recording
- `StreamingTranscriptionSession` — uses `StreamingTranscriptionService`, with automatic fallback to `TranscriptionService` if streaming fails. Returns an `onAudioChunk` callback from `prepare()` that the `Recorder` uses to forward live PCM data.

### 6. Engine — `VoiceInkEngine.swift`

The central orchestrator (`@MainActor`). Owns `Recorder`, `TranscriptionServiceRegistry`, manages `RecordingState` (`.idle` → `.recording` → `.transcribing` → `.enhancing` → `.idle`).

**`toggleRecord()` flow:**
1. If currently recording → stop recorder, run `TranscriptionPipeline`
2. If idle → request mic permission, create WAV file, start `Recorder`, buffer audio chunks, create `TranscriptionSession` via registry, call `prepare()`, wire up `onAudioChunk` callback, replay buffered chunks

Key detail: Audio chunks are buffered in an `OSAllocatedUnfairLock`-protected array while the session is being prepared, then replayed to the real callback once streaming is connected. This avoids losing audio during WebSocket handshake.

### 7. Post-Transcription Pipeline — `TranscriptionPipeline.swift`

After transcription text is obtained, the pipeline runs:
1. `TranscriptionOutputFilter.filter()` — removes hallucinations / noise
2. `WhisperTextFormatter.format()` — capitalizes, punctuates (if enabled)
3. `WordReplacementService.applyReplacements()` — user dictionary substitutions
4. `PromptDetectionService.analyzeText()` — detects if the user spoke a "prompt command" to change AI behavior
5. `AIEnhancementService.enhance()` — LLM post-processing (if enabled): reformats, fixes grammar, follows custom prompt instructions
6. Saves `Transcription` to SwiftData
7. `CursorPaster.pasteAtCursor()` — inserts into the frontmost app (via pasteboard + ⌘V simulation)
8. Auto-send key (Enter/Shift+Enter) if PowerMode config has one

### 8. AI Enhancement — `AIService.swift` + `AIEnhancementService.swift`

**`AIService`** manages LLM API calls via the `LLMkit` library. Supports Cerebras, Groq, Gemini, Anthropic, OpenAI, OpenRouter, Mistral, Ollama as enhancement providers (these are **separate** from transcription providers).

**`AIEnhancementService`** wraps `AIService` with:
- Custom prompts (user-editable, stored in UserDefaults as JSON)
- Screen capture context (screenshot of active window for context-aware enhancement)
- Clipboard context
- Custom vocabulary injection
- Prompt detection (allows "Hey AI, do X" spoken commands)
- Per-recording enhancement enable/disable

### 9. PowerMode — `PowerMode/`

App/URL-specific configurations. Each `PowerModeConfig` can override:
- Transcription model + language
- AI enhancement on/off + specific prompt
- AI provider + model
- Screen capture on/off
- Auto-send key (Enter, Shift+Enter, etc.)
- Custom hotkey

`ActiveWindowService` detects the frontmost app/URL and applies the matching PowerMode. `PowerModeSessionManager` handles per-recording config application.

### 10. Hotkey System — `HotkeyManager.swift`

Supports:
- Two configurable global hotkeys (via `KeyboardShortcuts` library)
- Hold-to-record ("hands-free") and toggle modes
- Middle-click toggle (via NSEvent monitors)
- Fn key support
- PowerMode-specific hotkeys

### 11. UI Layer — `Views/`

- **`ContentView`** — main settings/dashboard window (sidebar navigation)
- **`MiniRecorderView`** / **`NotchRecorderView`** — floating recorder panels (two styles: mini floating panel, or notch-style at top of screen)
- **`MiniWindowManager`** / **`NotchWindowManager`** — manage NSPanel windows for the recorders
- **`ModelManagementView`** — model selection, download, API key configuration
- **`EnhancementSettingsView`** — AI enhancement configuration
- **`TranscriptionHistoryView`** — past transcriptions with audio playback

### 12. Data Layer

- **SwiftData** models: `Transcription`, `VocabularyWord`, `WordReplacement`
- **Keychain** (via `KeychainService`): all API keys, Voiceitt tokens
- **UserDefaults**: settings, preferences, prompt configs
- **File system**: WAV recordings in `~/Library/Application Support/com.prakashjoshipax.VoiceInk/Recordings/`, Whisper models in `.../WhisperModels/`

### 13. SPM Dependencies

| Package | Purpose |
|---|---|
| `Sparkle` | Auto-updates |
| `KeyboardShortcuts` | Global hotkey registration |
| `LaunchAtLogin` | Launch at login |
| `FluidAudio` | NVIDIA Parakeet model inference |
| `MediaRemoteAdapter` | Pause/resume media during recording |
| `Zip` | Model file decompression |
| `SelectedTextKit` | Get selected text from active app |
| `swift-atomics` | Thread-safe atomic operations |
| `LLMkit` | LLM API abstraction for AI enhancement |
| `SocketIO` *(feature branch only)* | Socket.IO client for Voiceitt |

---

## Key Patterns & Conventions

1. **`@MainActor` everywhere.** Most service classes and all `ObservableObject`s are `@MainActor`. Audio callbacks run on the audio thread and dispatch back to main.

2. **Singletons** are common: `APIKeyManager.shared`, `KeychainService.shared`, `PowerModeManager.shared`, `AudioDeviceManager.shared`, `WordReplacementService.shared`, `VoiceittAuthService.shared`, etc.

3. **Streaming audio bridging:** The `Recorder.onAudioChunk` callback is set/replaced at runtime. During session preparation, chunks are buffered in a lock-protected array, then replayed. The `StreamingTranscriptionService` uses an `AsyncStream<Data>` internally.

4. **Fallback strategy:** Streaming providers fall back to file-based batch transcription on failure. The `StreamingTranscriptionSession` handles this transparently. Some streaming-only models map to a different batch-compatible model for fallback.

5. **Logging:** Uses `os.Logger` with the subsystem `com.prakashjoshipax.voiceink` throughout.

6. **Bundle ID:** `com.prakashjoshipax.VoiceInk` (case-sensitive for paths, lowercase for logger subsystem).

---

## Adding a New Transcription Provider (Checklist)

1. Add a case to `ModelProvider` enum in `TranscriptionModel.swift`
2. Add predefined model(s) in `PredefinedModels.swift`
3. Add API key mapping in `APIKeyManager.providerToKeychainKey`
4. **If batch (file-upload):** Add a case in `CloudTranscriptionService.transcribe()`
5. **If streaming:** 
   - Create a `XxxStreamingProvider` conforming to `StreamingTranscriptionProvider`
   - Add the case in `StreamingTranscriptionService.createProvider()`
   - Add the case in `TranscriptionServiceRegistry.supportsStreaming()`
   - If the streaming model has no batch equivalent, add a `batchFallbackModel()` mapping
6. Add UI in `ModelManagementView` (and a custom card view if auth is non-standard)
7. Add the provider check in `TranscriptionModelManager.usableModels`

---

## File Map (Key Files)

| File | Role |
|---|---|
| `VoiceInk.swift` | App entry point, service initialization |
| `Whisper/VoiceInkEngine.swift` | Central orchestrator, toggleRecord() flow |
| `Whisper/TranscriptionPipeline.swift` | Post-transcription processing pipeline |
| `Whisper/TranscriptionModelManager.swift` | Model selection & availability tracking |
| `CoreAudioRecorder.swift` | Low-level AUHAL audio capture |
| `Recorder.swift` | Audio recording lifecycle manager |
| `Models/TranscriptionModel.swift` | Model types & provider enum |
| `Models/PredefinedModels.swift` | Built-in model definitions |
| `Services/TranscriptionService.swift` | Transcription protocol |
| `Services/TranscriptionServiceRegistry.swift` | Service routing & session creation |
| `Services/TranscriptionSession.swift` | Session protocol + streaming/file implementations |
| `Services/StreamingTranscription/StreamingTranscriptionProvider.swift` | Streaming provider protocol |
| `Services/StreamingTranscription/StreamingTranscriptionService.swift` | Streaming lifecycle manager |
| `Services/APIKeyManager.swift` | Keychain-based API key storage |
| `Services/KeychainService.swift` | Raw Keychain wrapper |
| `Services/AIEnhancement/AIService.swift` | LLM API calls |
| `Services/AIEnhancement/AIEnhancementService.swift` | Enhancement orchestration |
| `HotkeyManager.swift` | Global keyboard shortcut handling |
| `Whisper/RecorderUIManager.swift` | Recorder panel show/hide logic |
| `CursorPaster.swift` | Paste text at cursor position |
| `PowerMode/PowerModeConfig.swift` | Per-app configuration model |
| `PowerMode/ActiveWindowService.swift` | Frontmost app detection |
| `Views/Recorder/MiniRecorderView.swift` | Floating recorder UI |
| `Views/AI Models/ModelManagementView.swift` | Model settings UI |
