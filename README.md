<div align="center">

<img src="assets/logo.png" width="160" alt="Jiggypuff Logo" style="border-radius: 36px; box-shadow: 0 10px 30px rgba(0,0,0,0.3);" />

# Jiggypuff 🎤✨

**The AI-Powered Voice Dictation & Audio HUD for macOS**  
*Sing your thoughts into words at the speed of speech.*

[![macOS](https://img.shields.io/badge/macOS-14.0%2B-black?style=flat-square&logo=apple)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-6.0-orange?style=flat-square&logo=swift)](https://swift.org)
[![Gemini 3.5](https://img.shields.io/badge/Engine-Gemini%203.5%20Transcribe-4285F4?style=flat-square&logo=google)](https://aistudio.google.com)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat-square)](LICENSE)

</div>

---

**Jiggypuff** is a native macOS dictation and voice assistant inspired by **Wispr Flow**, powered by Google's state-of-the-art **Gemini 3.5 Transcribe** (`gemini-3.5-transcribe` and `gemini-3.5-transcribe-live`).

Running quietly in the background as a menu bar app, Jiggypuff is always ready. Press your global hotkey (`⌥ Space`), and a liquid glass HUD appears with live real-time audio waveforms. Speak naturally—Jiggypuff cleans up speech disfluencies, handles self-corrections on the fly (*"meet Tuesday... actually Wednesday"* → *"meet Wednesday"*), removes filler words (*"um"*, *"uh"*), and automatically types the polished text into whatever application you are using.

---

## ✨ Highlights & Features

- **🎙️ Google Gemini 3.5 Transcribe Engine**:
  - **`gemini-3.5-transcribe`**: High-accuracy speech recognition with native self-correction handling, automatic filler word removal, context-aware punctuation, and custom vocabulary biasing.
  - **`gemini-2.5-flash` / Multimodal Fallback**: Powers specialized rewrite modes like Email formatting, Bullet Points, and Code generation.
- **🫧 Liquid Glass HUD Pill**:
  - Translucent liquid glassmorphic floating pill overlay that appears smoothly on top of all full-screen apps and spaces without stealing focus.
  - Live animated audio waveform reacting to your microphone in real-time.
- **⚡ Push-to-Talk & Toggle Modes**:
  - Press & hold or single-press trigger with global shortcut (`Option + Space`).
  - Haptic-like audio feedback cues on start, stop, and transcription completion.
- **⌨️ Direct Auto-Typing**:
  - Automatically simulates typing/pasting transcribed text into the frontmost app (Xcode, Slack, Cursor, Notes, Chrome, Terminal, etc.) while preserving your clipboard history.
- **🪄 Multiple Dictation Modes**:
  - 🪄 **Smart Flow**: Natural speech cleanup, self-correction fixing, perfect punctuation.
  - 💬 **Raw Verbatim**: Exact literal transcription without rewriting.
  - ✉️ **Email / Professional**: Formats spoken stream-of-consciousness into polished emails.
  - 📋 **Bullet Points / Notes**: Summarizes speech into clear, actionable bullet points.
  - 💻 **Code & Technical**: Recognizes camelCase variable names, shell commands, and syntax.
  - ⚙️ **Custom Prompt**: Define your own custom system instructions.
- **📚 Custom Vocabulary**:
  - Add domain-specific jargon, acronyms, team member names, or unusual spellings.
- **🕒 Searchable History**:
  - Search, inspect, and copy past voice dictations.
- **🔒 Secure Keychain Storage**:
  - Gemini API Key is safely stored in macOS Keychain or read from the `GEMINI_API_KEY` environment variable.

---

## 🚀 Installation & Quick Start

### Option 1: Download Pre-built DMG (Recommended)

1. Download the latest **`Jiggypuff.dmg`** from [GitHub Releases](https://github.com/prakhar1989/Transcrib/releases).
2. Open `Jiggypuff.dmg` and drag **Jiggypuff** into your **Applications** folder.
3. **First-Time Launch (macOS Gatekeeper)**:
   - Since Jiggypuff is free, open-source, and distributed without a paid Apple Developer certificate, macOS may show a warning: *"Jiggypuff cannot be opened because Apple cannot check it for malicious software"*.
   - **To open**: Right-click (or Control-click) `Jiggypuff.app` in your Applications folder and select **Open** → click **Open** again.
   - *Alternative*: Run this one-line command in Terminal:
     ```bash
     xattr -cr /Applications/Jiggypuff.app
     ```

---

### Option 2: Build from Source

#### Prerequisites
- macOS 14.0 (Sonoma) or later
- Xcode 15+ / Swift 6.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Google Gemini API Key from [Google AI Studio](https://aistudio.google.com/app/apikey)

#### Build & Run
1. **Clone the repository**:
   ```bash
   git clone https://github.com/prakhar1989/Transcrib.git
   cd Transcrib
   ```

2. **Build the `.app` bundle**:
   ```bash
   ./scripts/build_app.sh
   open build/Jiggypuff.app
   ```

3. **Or package a `.dmg` installer**:
   ```bash
   ./scripts/create_dmg.sh
   ```

4. **Or open in Xcode**:
   ```bash
   xcodegen generate
   open Jiggypuff.xcodeproj
   ```

---

## 🔑 Permissions & Setup

When you first launch Jiggypuff:
1. Click the **Waveform** icon in your macOS Menu Bar -> select **Settings** (or press `Cmd+,`).
2. In **Model & API**, enter your Gemini API Key from Google AI Studio.
3. In **Permissions**, ensure **Microphone** and **Accessibility** access are granted (Accessibility allows Jiggypuff to simulate typing into your active frontmost applications).
4. Hit `⌥ Space` anywhere in macOS to start dictating!
