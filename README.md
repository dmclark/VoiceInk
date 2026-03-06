<div align="center">
  <img src="VoiceInk/Assets.xcassets/AppIcon.appiconset/256-mac.png" width="180" height="180" />
  <h1>VoiceInk (Experimental Fork)</h1>
  <p>Voice to text app for macOS to transcribe what you say to text almost instantly</p>

  > ⚠️ **This is an unofficial, experimental fork.** For the official project, please visit [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk).

  [![License](https://img.shields.io/badge/License-GPL%20v3-blue.svg)](https://www.gnu.org/licenses/gpl-3.0)
  ![Platform](https://img.shields.io/badge/platform-macOS%2014.0%2B-brightgreen)
  <p>
    <a href="https://tryvoiceink.com">Website (official)</a> •
    <a href="https://www.youtube.com/@tryvoiceink">YouTube (official)</a>
  </p>
</div>

---

> **Note:** This is an experimental fork maintained by [@dmclark](https://github.com/dmclark) for personal exploration and testing. It may contain unstable or incomplete changes. The motivation is to explore the potential of VoiceInk using [Voiceeitt](https://voiceitt.com).   If you're looking for the official, supported version of VoiceInk, please go to [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk).

VoiceInk is a native macOS application that transcribes what you say to text almost instantly. You can find all the information and download the official app from [tryvoiceink.com](https://tryvoiceink.com).

## Get Started

**Only use this fork if you want to experiment with VoiceInk using Voiceitt. Otherwise, please use the official version from [Beingpax/VoiceInk](https://github.com/Beingpax/VoiceInk).**

### Build from Source

For build instructions, see our [Building Guide](BUILDING.md).

## Requirements

- macOS 14.4 or later

## License

This project is licensed under the GNU General Public License v3.0 - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

### Core Technology
- [whisper.cpp](https://github.com/ggerganov/whisper.cpp) - High-performance inference of OpenAI's Whisper model
- [FluidAudio](https://github.com/FluidInference/FluidAudio) - Used for Parakeet model implementation

### Essential Dependencies
- [Sparkle](https://github.com/sparkle-project/Sparkle) - Keeping VoiceInk up to date
- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) - User-customizable keyboard shortcuts
- [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin) - Launch at login functionality
- [MediaRemoteAdapter](https://github.com/ejbills/mediaremote-adapter) - Media playback control during recording
- [Zip](https://github.com/marmelroy/Zip) - File compression and decompression utilities
- [SelectedTextKit](https://github.com/tisfeng/SelectedTextKit) - A modern macOS library for getting selected text
- [Swift Atomics](https://github.com/apple/swift-atomics) - Low-level atomic operations for thread-safe concurrent programming


---
