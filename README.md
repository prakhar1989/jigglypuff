<div align="center">

<img src="assets/logo.png" width="160" alt="Jigglypuff Logo" />

# Jigglypuff

Voice dictation for macOS, powered by Gemini.

</div>

Jigglypuff is a menu bar app that types what you say. Press `⌥ Space`, talk, and the cleaned-up text is typed into whatever app you're in. It uses Google's Gemini speech models to remove filler words, fix self-corrections (*"meet Tuesday... actually Wednesday"* → *"meet Wednesday"*), and handle punctuation.

## Features

- Global hotkey (`⌥ Space`) with push-to-talk or toggle mode
- Floating HUD with a live waveform that stays above full-screen apps without stealing focus
- Auto-types into the frontmost app and leaves your clipboard alone
- Dictation modes: smart cleanup, verbatim, email, bullet points, code, or your own custom prompt
- Custom vocabulary for names, jargon, and unusual spellings
- Searchable history of past dictations
- API key stored in macOS Keychain, or read from `GEMINI_API_KEY`

## Install

Download `Jigglypuff.dmg` from [GitHub Releases](https://github.com/prakhar1989/jigglypuff/releases) and drag it to your Applications folder.

The app isn't notarized (no paid Apple Developer account), so macOS will warn you on first launch. Right-click the app and choose **Open**, or run:

```bash
xattr -cr /Applications/Jigglypuff.app
```

## Build from source

Requires macOS 14+, Xcode 15+, and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).

```bash
git clone https://github.com/prakhar1989/jigglypuff.git
cd jigglypuff
./scripts/build_app.sh
open build/Jigglypuff.app
```

To package a DMG instead, run `./scripts/create_dmg.sh`. To work in Xcode, run `xcodegen generate && open Jigglypuff.xcodeproj`.

## Setup

1. Get a Gemini API key from [Google AI Studio](https://aistudio.google.com/app/apikey).
2. Click the Jigglypuff icon in the menu bar → **Settings**, and paste in your key.
3. Grant **Microphone** and **Accessibility** permissions when prompted. (Accessibility is what lets Jigglypuff type into other apps.)
4. Press `⌥ Space` anywhere and start talking.
