# Transrib 🎙️✨

**Transrib** is a native macOS dictation and voice-to-text assistant inspired by **Wispr Flow**, powered by Google's newly released **Gemini 3.5 Transcribe** (`gemini-3.5-transcribe` and `gemini-3.5-transcribe-live`).

Transrib runs seamlessly in the background as a menu bar app. With a global shortcut (`⌥ Space`), a floating glass HUD pill appears, records your voice, cleans up speech disfluencies and self-corrections with Gemini 3.5 Transcribe, and automatically types the polished text into whatever application you are using.

---

## ⚡ Features

- **Gemini 3.5 Transcribe Powered**:
  - `gemini-3.5-transcribe`: High accuracy transcription via the Gemini Interactions API with native smart self-correction handling (*"meet Tuesday... actually Wednesday"* -> *"meet Wednesday"*), automatic filler word removal (*"um"*, *"ah"*), formatting, and custom vocabulary biasing.
  - Fallback support for `gemini-2.5-flash` (`generateContent` with inline audio) — required for the rewriting dictation modes (Email, Bullet Points, Code, Custom Prompt).
- **Wispr Flow-style Floating HUD Pill**:
  - Translucent liquid glassmorphic pill overlay that appears on top of all full-screen apps and spaces without stealing focus.
  - Live animated audio waveform reacting to your microphone in real-time.
- **Push-to-Talk & Toggle Modes**:
  - Press & hold or single-press trigger (default: `Option + Space`).
  - Tactile audio feedback cues on start, finish, and success.
- **Direct Auto-Typing**:
  - Automatically types/pastes transcribed text into the frontmost app (Xcode, Slack, Cursor, Notes, Chrome, Terminal, etc.) and preserves your previous clipboard.
- **Dictation Modes**:
  - 🪄 **Smart Flow**: Intelligent speech cleanup, self-correction fixing, perfect punctuation.
  - 💬 **Raw Verbatim**: Exact literal transcription without rewriting.
  - ✉️ **Email / Professional**: Formats thoughts into polished emails/messages.
  - 📋 **Bullet Points / Notes**: Summarizes speech into clear action items.
  - 💻 **Code & Technical**: Recognizes camelCase variable names, shell commands, and syntax.
  - ⚙️ **Custom Prompt**: Write your own custom transcription instructions.
- **Custom Vocabulary**: Add domain-specific jargon, acronyms, and names.
- **Searchable History**: Browse, search, and copy past dictations.
- **Secure Keychain Storage**: Gemini API Key is stored safely in macOS Keychain or loaded from the `GEMINI_API_KEY` environment variable.

---

## 🚀 Quick Start & Building

### Prerequisites
- macOS 14.0 or later
- Xcode 15+ / Swift 6.0+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- A Google Gemini API Key from [Google AI Studio](https://aistudio.google.com/app/apikey)

### Build & Run

1. **Clone or Navigate to the directory**:
   ```bash
   cd /Users/prakhar/Code/transrib
   ```

2. **Build the `.app` bundle**:
   ```bash
   ./scripts/build_app.sh
   ```

3. **Launch the App**:
   ```bash
   open build/Transrib.app
   ```

4. **Or open directly in Xcode**:
   ```bash
   xcodegen generate
   open Transrib.xcodeproj
   ```

---

## 🔑 Permissions & Setup

When you first launch Transrib:
1. Click the **Waveform** icon in your macOS Menu Bar -> select **Settings** (or press `Cmd+,`).
2. In **Model & API**, enter your Gemini API Key from Google AI Studio.
3. In **Permissions**, ensure **Microphone** and **Accessibility** access are granted (Accessibility allows Transrib to simulate typing into your active windows).
