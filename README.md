# VoiceInk for Voiceitt (Experimental Fork)
  
## **What is VoiceInk?** 

A native macOS app (Swift / SwiftUI, requires macOS 14.4+) that transcribes speech to text and pastes it at the cursor. It supports local Whisper models, NVIDIA Parakeet, Apple's native Speech framework, and cloud providers (Groq, ElevenLabs, Deepgram, Mistral, Gemini, Soniox) — including real-time streaming for some of them. It optionally enhances transcriptions with LLM-powered AI before pasting. You can find all the information and download the official app from [tryvoiceink.com](https://tryvoiceink.com).

## What is Voiceitt?

Voiceitt is a speech recognition service that supports  ß enables accurate real time voice transcription  for people with speech disabilities (e.g., dysarthria, aphasia due to cerebral palsy, stroke, ALS, or other conditions), aging adults, and accented speakers. Users [sign up](https://web.voiceitt.com/sign-up) and create a personal by profile with a minimum of 50 word training. They then can use the service in a web based app, Zoom or Microsoft Teams

## What is this project & why does it exist?

Currently, this is a successful proof of concept that is evolving. It uses the source code of Voiceink and adds Voiceitt as a transcription provider. It is designed to be a drop-in replacement for the existing transcription providers, allowing for the use of the Voiceitt service across all applications on the MacOS platform with the addition of the post-processing available in VoiceInk. This work is never intended to be merged back into Voiceink , and the other transcription providers may be eventually stripped out so that this is only a client for Voiceitt.

This project developed out of personal passion and interest. [I am a developer/technologist looking for work](https://www.linkedin.com/in/dclark7/), who has cerebral palsy. I recently Googled out of frustration and found Voiceitt. I fell in love with it immediately --  it has been transformational. After discovering it had an API, I looked for ways to extend it to work in other situations. When I found Voiceink and the open source code for it. I started immediately trying to come up with a solution. Since I had been dabbling in AI (using [Amp](https://ampcode.com/home), I quickly found away develop this proof of concept.


## Building for Local Use (No Apple Developer Certificate)

If you don't have an Apple Developer certificate, use `make local`:

```bash
git clone https://github.com/dmclark/VoiceInk
cd VoiceInk
sh scripts/sync-upstream.sh
make local
open ~/Downloads/VoiceInk.app
```

**Note:** The default branch is `voiceitt` so that upstream changes (VoiceInk) can continue to be merged in.

This builds VoiceInk with ad-hoc signing using a separate build configuration (`LocalBuild.xcconfig`) that requires no Apple Developer account.

### How It Works

The `make local` command uses:
- `LocalBuild.xcconfig` to override signing and entitlements settings
- `VoiceInk.local.entitlements` (stripped-down, no CloudKit/keychain groups)
- `LOCAL_BUILD` Swift compilation flag for conditional code paths

Your normal `make all` / `make build` commands are completely unaffected.

## Requirements

- macOS 14.4 or later
- Xcode 15.3 or later installed
- Voiceitt API key & APP_ID
- Email & Password for Voiceitt user account (profile to use)

##  Configuration

Once you have the app running, configure Voiceitt to be the transcription provider.

- Open the app and go to the settings tab.
- Click on the "AI Model" section.
- Click on the "Cloud" tab.
- Select Voiceitt as the transcription provider. (Last option in the list )
- Enter your Voiceitt API key and APP_ID.
- Enter your Voiceitt email and password.

## Documentation

- [Building from Source](BUILDING.md) - Detailed instructions for building the project
- [Details on Voiceitt Integration](VOICEITT_INTEGRATION_PLAN.md) - Details on the Voiceitt integration - what has been done and what is left to do in this phase.
- [Plans for actual product](notes/PRD.md) - Plans for the actual product (Product Requirements Document)

---
