# VoiceITTinINK — Product Requirements Document

**Version:** 0.1 (Draft)
**Date:** 2026-03-24
**Author:** @dmclark

---

## 1. Vision

**VoiceITTinINK** is a native macOS app that brings [Voiceitt](https://voiceitt.com) speech recognition to the desktop, enabling people with non-standard speech to dictate text into any application. It pairs Voiceitt's personalized speech models with AI-powered text enhancement — fixing grammar, formatting, and applying custom prompts — then pastes the result at the cursor.

**Origin:** Fork of [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk), stripped down to a single transcription provider (Voiceitt) and rebranded.

---

## 2. Goals & Non-Goals

### Goals

- **Single transcription provider:** Voiceitt only. No Whisper, Parakeet, Groq, Deepgram, ElevenLabs, Mistral, Gemini, Soniox, Native Apple, or custom endpoints.
- **Keep AI enhancement:** LLM-powered post-transcription processing via LLMkit (Cerebras, Groq, Gemini, Anthropic, OpenAI, OpenRouter, Mistral, Ollama).
- **Keep enhancement prompts:** Custom user prompts, prompt detection ("Hey AI, do X"), screen capture context, clipboard context, vocabulary injection.
- **Keep core pipeline:** Hotkey → record → stream to Voiceitt → enhance → paste at cursor.
- **Keep power features:** PowerMode (per-app configs), global hotkeys, word replacements, transcription history, menu bar presence.
- **Rebrand:** New name (VoiceITTinINK), new bundle ID, new app identity.
- **Chrome-extension-style insertion:** Text is auto-inserted as recognition completes — no explicit "stop and transcribe" step. The user presses the hotkey to start, speaks, and recognized text flows into the active field continuously. Pressing the hotkey again (or releasing in hold mode) ends the session.
- **Utterance correction & feedback:** In the History panel, users can correct a transcription and email it to Voiceitt support to improve their personal model.
- **Hardcoded Voiceitt credentials:** App ID and API Key are bundled in the app (not user-provided), simplifying onboarding to email/password only.

### Non-Goals (v1)

- Supporting any transcription provider other than Voiceitt.
- Local model download/import/management.
- Maintaining merge compatibility with upstream VoiceInk.

### Possible Future Goals

- **Cross-platform expansion:** Selected companion and desktop variants for iOS/iPadOS, Windows, browser, and later Android, with platform-specific feature sets rather than full macOS parity. See [§11 Cross-Platform Feasibility](#11-cross-platform-feasibility) for analysis.

---

## 3. Target Users

People with non-standard speech (dysarthria, speech differences, accents that standard ASR fails on) who:

- Use macOS 14.4+
- Have a Voiceitt account with a trained personal speech model
- Want to dictate into any macOS application (email, chat, documents, code editors)
- May benefit from AI-powered grammar/formatting correction

---

## 4. Core User Flow

```
1. User launches VoiceITTinINK → logs into Voiceitt (email/password only; App ID/API Key are bundled)
2. User presses global hotkey (or holds for hands-free mode)
3. Floating recorder panel appears → audio streams to Voiceitt via Socket.IO
4. Voiceitt loads personal model (may take seconds) → recognized text auto-inserts at cursor as it arrives (Chrome-extension-style continuous insertion)
5. Pipeline runs on each recognized segment:
   a. Filter hallucinations/noise
   b. Format text (capitalize, punctuate)
   c. Apply word replacements
   d. Detect prompt commands
   e. AI enhancement (if enabled) — LLM reformats/fixes/follows instructions
   f. Paste at cursor in the active app
6. User presses hotkey again (or releases in hold mode) → session ends, final transcript saved to history
7. Optional: auto-send (Enter/Shift+Enter) if configured via PowerMode
```

---

## 5. Key Features

### 5.1 Voiceitt Transcription (Streaming Only)

- **Auth:** Email/password login → JWT token + refresh token (stored in Keychain). App ID and API Key are **hardcoded** in the app bundle — users never see or enter them.
- **Transport:** Socket.IO (not raw WebSocket)
- **Audio format:** 16 kHz, mono, PCM Int16, little-endian (already matches CoreAudioRecorder output)
- **Model loading:** Per-user trained model on Voiceitt servers; can take several seconds
- **Continuous insertion:** Recognized text is auto-inserted at the cursor as committed segments arrive (like Voiceitt's Chrome extension), rather than waiting for the user to stop recording. Partial transcripts are displayed in the recorder panel but not inserted.
- **No batch/REST fallback:** Voiceitt is streaming-only. No silent fallback to another provider.

### 5.2 AI Enhancement (Preserved from VoiceInk)

- Multiple LLM providers via LLMkit (Cerebras, Groq, Gemini, Anthropic, OpenAI, OpenRouter, Mistral, Ollama)
- Custom user-editable prompts (stored in UserDefaults as JSON)
- Screen capture context (screenshot of active window)
- Clipboard context
- Custom vocabulary injection
- Prompt detection ("Hey AI, rewrite this as a bullet list")
- Per-recording enable/disable

### 5.3 PowerMode (Preserved)

- Per-app and per-URL configurations
- Override: AI enhancement on/off, specific prompt, AI provider/model, screen capture, auto-send key, custom hotkey
- Active window detection via `ActiveWindowService`

### 5.4 Utterance Correction & Feedback (New)

- In the **History panel**, each transcription entry has a **"Correct & Send"** action.
- User can edit the transcription text to provide the correct version of what they said.
- Submitting emails the correction (original transcription + corrected text + optional audio) to Voiceitt support.
- Purpose: helps Voiceitt improve the user's personal speech model over time.
- Implementation: compose an email via `mailto:` or `MFMailComposeViewController`-equivalent with pre-filled subject, body, and attachment.

### 5.5 Core Infrastructure (Preserved)

- **Audio capture:** CoreAudioRecorder (AUHAL, not AVAudioEngine)
- **Hotkeys:** Global hotkeys via KeyboardShortcuts, hold-to-record, middle-click, Fn key
- **Paste:** CursorPaster (pasteboard + ⌘V simulation)
- **Word replacements:** User dictionary substitutions
- **Transcription history:** SwiftData persistence with audio playback
- **Menu bar:** Persistent MenuBarExtra with status
- **Auto-updates:** Sparkle (with new appcast URL)

---

## 6. What Gets Removed

### Transcription Providers
- Local Whisper models (`LocalTranscriptionService`, `WhisperModelManager`, LibWhisper)
- NVIDIA Parakeet (`ParakeetTranscriptionService`, `ParakeetModelManager`, FluidAudio)
- Apple Native Speech (`NativeAppleTranscriptionService`)
- Groq, ElevenLabs, Deepgram, Mistral, Gemini, Soniox cloud providers
- Custom OpenAI-compatible endpoints
- All streaming providers except `VoiceittStreamingProvider`

### Model Management
- Model download/import UI and flows
- HuggingFace model catalog
- Multi-provider model selection cards (all except Voiceitt)
- `TranscriptionModelManager` multi-model logic (simplify to Voiceitt-only)

### Dependencies to Remove
| Package | Reason |
|---|---|
| `FluidAudio` | Parakeet inference — not needed |
| `Zip` | Model file decompression — not needed |
| whisper.cpp / `LibWhisper` | Local Whisper inference — not needed |

### Dependencies to Keep
| Package | Reason |
|---|---|
| `SocketIO` | Voiceitt transport |
| `LLMkit` | AI enhancement |
| `KeyboardShortcuts` | Global hotkeys |
| `LaunchAtLogin` | Launch at login |
| `MediaRemoteAdapter` | Pause/resume media during recording |
| `SelectedTextKit` | Get selected text from active app |
| `swift-atomics` | Thread-safe atomics in audio path |
| `Sparkle` | Auto-updates |

---

## 7. Fork vs. Scratch Analysis

### Recommendation: **Fork + Strip (Approach 1)**

The oracle analysis strongly favors continuing as a fork. Here is the full comparison:

### Approach 1: Fork + Strip

**Pros:**

1. **Fastest path to a working app.** The hardest parts are already solved: macOS audio capture, global hotkeys, recorder panels, audio chunk buffering during WebSocket handshake, partial transcripts, paste-at-cursor, AI enhancement, and the entire Voiceitt integration.

2. **Lowest integration risk.** The core pipeline (`hotkey → recorder UI → engine → session → transcription → enhancement → paste`) is already coherent. Keeping it intact avoids subtle regressions around audio-thread/main-actor coordination, chunk buffering, paste timing, and permission flows.

3. **Voiceitt integration already done.** Socket.IO config, email/password auth, token refresh, `connection_ready`/`model_ready` state machine, connect/stop race fix, partial transcript display — all wired up and tested on the feature branch.

4. **Lets you defer refactoring.** Ship a simpler product without redesigning the architecture on day 1.

**Cons:**

1. **Inherited conceptual baggage.** The codebase will still be shaped like a multi-provider app — registry/service abstractions, model managers, settings assumptions, provider enums used in switch statements everywhere.

2. **Pruning is not trivial.** 50+ Swift files with `@MainActor` singletons, environment object wiring, SwiftData models, shared persistence keys, and provider enums touched in many places.

3. **Upstream merge value declines.** Once you remove half the app, upstream changes to providers/models become noise. Long-term: selective cherry-picking only, not painless syncing.

4. **Dependency cleanup may lag.** The app may be "Voiceitt-only" conceptually but still carry unused managers, build settings, and packages temporarily.

### Approach 2: Start from Scratch

**Pros:**

1. **Cleanest end state.** Designed around one truth: Voiceitt only. No fake generic abstractions, no dead provider concepts.

2. **Smaller dependency footprint from day one.** No FluidAudio, Zip, whisper.cpp.

3. **Better long-term product identity.** Fewer legacy assumptions, easier signing/configuration, less "VoiceInk-but-reduced" feel.

4. **No upstream merge burden.**

**Cons:**

1. **High hidden coupling cost.** VoiceInk is not a set of isolated reusable packages. "Cherry-pick what we need" turns into: copy a file → discover 3 dependencies → copy those → discover shared assumptions → recreate half the original app shell anyway.

2. **Risk of re-solving already-solved macOS problems.** Audio capture stability, hotkeys, recorder panels, active app detection, paste behavior, audio chunk buffering — all look simple but are annoying to get production-stable.

3. **Voiceitt extraction is not trivial.** Depends on streaming abstractions, session lifecycle, error propagation, auth persistence, recorder pipeline assumptions.

4. **Longer path to first usable build.** Delays the first moment you can: press hotkey → speak → Voiceitt transcribes → AI enhances → text pastes.

### Factor-by-Factor Comparison

| Factor | Fork + Strip | Scratch |
|---|---|---|
| Time to first working product | **Best** | Slower |
| Initial technical risk | **Lower** | Higher |
| Long-term cleanliness | Weaker (unless refactored later) | **Best** |
| Dependency minimization | Gradual | **Best** |
| Reuse of Voiceitt branch work | **Direct** | Partial, with extraction risk |
| Reuse of AI enhancement system | **Direct** | Requires porting dependencies |
| Reuse of PowerMode/hotkeys/paste | **Direct** | Significant integration work |
| Upstream maintenance | Some benefit early, harder later | No merge burden |
| Testing burden | **Lower** for MVP | Higher |
| Likelihood of hidden work | Moderate | **High** |

### Decision

**Go with Approach 1 (Fork + Strip).** The Voiceitt integration is already done, the pipeline works, and the hidden cost of "scratch" is deceptively high. Ship fast, then refactor incrementally.

---

## 8. Implementation Phases

### Phase 1: Stabilize Voiceitt-Only Behavior
- Branch from the Voiceitt integration branch (not upstream main)
- Make Voiceitt the only selectable transcription provider (hide all others in UI)
- Disable silent Groq fallback for `.voiceitt` — surface errors clearly
- Fix remaining Voiceitt issues:
  - Set `save_audio = false` by default
  - Handle `reset_alb_cookies` with fail-fast + clear retry message
  - Add "Loading personal model…" UI state during multi-second model load

### Phase 2: Strip Provider UI & Model Management
- Delete model cards/views for all non-Voiceitt providers
- Simplify `ModelManagementView` into a Voiceitt account/settings screen
- Simplify onboarding to: Voiceitt auth → mic permission → hotkey setup
- Remove model download/import UI and flows

### Phase 3: Remove Dead Services & Dependencies
- Delete: `LocalTranscriptionService`, `ParakeetTranscriptionService`, `NativeAppleTranscriptionService`, most of `CloudTranscriptionService`
- Delete: `WhisperModelManager`, `ParakeetModelManager`, model download flows
- Remove SPM packages: `FluidAudio`, `Zip`, whisper.cpp/LibWhisper
- Remove unused build settings and resources
- Collapse multi-provider abstractions where they're no longer needed

### Phase 4: Rebrand to VoiceITTinINK
- New bundle ID (e.g., `com.dmclark.VoiceITTinINK`)
- Update app support path (`~/Library/Application Support/...`)
- Update `os.Logger` subsystem
- Update Sparkle appcast URL
- Update entitlements and code signing
- Update CloudKit/container IDs if retained
- New app icon and branding
- Update README, documentation, and in-app text

### Phase 5: Harden & Ship
- End-to-end test: login → connect → stream → partial → final → enhance → paste
- Smoke test checklist:
  - Voiceitt login
  - Hotkey start/stop (toggle + hold-to-record)
  - Partial transcript display
  - Final transcription
  - AI enhancement with custom prompt
  - Paste into another app
  - PowerMode override
  - Word replacements
  - Transcription history
- Accessibility audit for non-standard speech users
- Privacy review (`save_audio`, token storage, screen capture opt-in)

---

## 9. Open Questions

| # | Question | Impact |
|---|---|---|
| 1 | ~~Should Voiceitt App ID / API Key be bundled in the app or remain user-provided?~~ **Decided: hardcode them.** | — |
| 2 | Should `reset_alb_cookies` trigger automatic reconnection or user-facing retry? | Reliability vs. complexity |
| 3 | Should transcription history be kept, simplified, or removed? | Scope, privacy |
| 4 | What LLM enhancement providers to include by default? All LLMkit providers or a curated subset? | UX complexity |
| 5 | Should PowerMode be kept in full or simplified for v1? | Scope |
| 6 | Distribution: Mac App Store, direct download (Sparkle), or both? | Signing, sandboxing, updates |
| 7 | Should the notch-style recorder UI be kept or simplified to mini-only? | Maintenance burden |
| 8 | iCloud sync for vocabulary/word replacements — keep or remove? | Complexity, privacy |
| 9 | How should AI enhancement interact with continuous insertion? Enhance each segment individually, or buffer and enhance on stop? | UX, latency |
| 10 | What email address / format should utterance corrections be sent to? Does Voiceitt have a formal correction intake? | Feature design |
| 11 | Should hardcoded App ID/API Key be obfuscated in the binary? | Security |

---

## 10. Success Metrics

- **Functional:** User can press hotkey → speak with non-standard speech → receive accurate transcription via Voiceitt → AI-enhanced text appears at cursor in any app.
- **Performance:** End-to-end latency (stop recording → text pasted) under 5 seconds (excluding Voiceitt model load on first connect).
- **Reliability:** No silent fallback to incompatible providers. Clear error messages for connection/auth failures.
- **Simplicity:** Onboarding requires only Voiceitt email/password + mic permission + hotkey selection. No model downloads, API keys, or multi-provider confusion.

---

## 11. Cross-Platform Feasibility

> Analysis provided by oracle. This section explores whether mobile and non-Mac platforms should be a possible future goal.

### Summary

**Voiceitt's transport (Socket.IO + 16kHz PCM) is highly portable. The macOS UX (global hotkeys, floating panels, paste-at-cursor) is not.** Future platforms would get adapted companion experiences, not full macOS parity.

### Platform-by-Platform Assessment

#### Windows Desktop — Most Realistic for Parity
- Can support: global hotkeys, tray app, floating windows, clipboard/paste, active window detection
- Desktop workflow is closest to macOS
- **Best approach:** Electron app (good Socket.IO support, mature Windows tray/hotkey ecosystem)
- **Effort:** XL
- **Recommendation:** Highest-priority non-Mac platform if desktop parity matters

#### Browser Extension (Chrome/Edge) — Broadest Reach
- Covers: Windows, macOS, Linux, ChromeOS via browser
- Aligns with Voiceitt's own Chrome/Edge extension strategy
- Limited to browser text fields only (not system-wide)
- **Effort:** L–XL
- **Recommendation:** Strong candidate for broad reach, especially since Voiceitt already has browser extensions

#### Web App / PWA — Widest Platform Coverage
- Works on: any device with a browser (desktop + mobile)
- Good: microphone access, Socket.IO, AI enhancement via HTTP, transcript editing
- Bad: no global hotkeys outside browser, no paste into native apps, no floating utility behavior
- **Different product shape** — great for in-browser dictation, poor substitute for system-wide utility
- **Effort:** L–XL

#### iOS / iPadOS — Companion App Only
- **Feasible as a companion** (foreground dictation, note composer, share/export), **not as system-wide dictation**
- No global hotkeys, no paste-at-cursor in other apps, no floating panels
- Can share Swift code: Voiceitt auth, Socket.IO provider, SwiftData models, some SwiftUI, Keychain
- Must rewrite: audio capture (AVAudioEngine, not AUHAL), all AppKit integrations
- LLMkit supports iOS 17+ — dependency is compatible
- **Effort:** XL

#### Android — Separate Native App
- Feasible but essentially a **full rewrite** — no Swift/AppKit code reuse
- Potentially **better than iOS for cross-app text entry** via IME/keyboard or accessibility service
- Requires: new audio layer (AudioRecord), new UI, new secure storage
- **Effort:** XL

#### Linux — Low Priority
- Desktop integration is fragmented (X11 vs Wayland, inconsistent global hotkeys/tray/paste)
- Only realistic as: web app, or Electron "best effort"
- **Effort:** XL + ongoing platform risk
- **Recommendation:** Do not plan early

### What's Portable vs. What Must Be Rewritten

| Layer | Portability |
|---|---|
| Voiceitt auth flow (HTTPS) | **High** — portable everywhere |
| Socket.IO streaming + 16kHz PCM | **High** — libraries exist on all platforms |
| AI enhancement prompt logic | **High** — portable concepts |
| LLMkit (LLM API calls) | **Apple only** (macOS 14+ / iOS 17+) — abstract behind a protocol for future platforms |
| SwiftUI / SwiftData / Keychain | **Apple only** |
| Audio capture (AUHAL) | **macOS only** — each platform has its own API |
| Global hotkeys / floating panels | **Desktop only** — each OS has its own mechanism |
| Paste-at-cursor / active app detection | **Desktop only** — per-OS implementation |

### Key Blocker: Auth Credentials

The hardcoded App ID / API Key means shipping developer credentials in client apps on multiple platforms. A public multi-platform release may eventually need a **small backend/token broker** to avoid exposing these in web/mobile binaries.

### Recommended Expansion Order

1. **macOS native** (v1 — current)
2. **Browser extension** or **Windows desktop** (most realistic next steps)
3. **iOS companion app** (if Apple ecosystem matters)
4. **Android** (separate effort, only if demand exists)
5. **Linux** (best-effort via web/Electron only)
