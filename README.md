# Local Mind

A private AI chat app for the Mac. It talks to the models you run with [Ollama](https://ollama.com),
so every conversation stays on your Mac: nothing goes over the internet.

## What it does

- **Chat with local models**: Gemma, gpt-oss, and anything else Ollama runs, with streaming replies,
  Markdown, code blocks, and thinking you can open when you want it.
- **Attach files**: images, PDFs, text, and audio, with previews. Gemma models can transcribe recordings.
- **Quick Ask**: a floating panel from any app with a global shortcut.
- **Menu bar aperture**: open when a model is loaded and ready, closed when it isn't.
- **Model Lab**: test each model on this Mac (speed, reasoning, code, instructions, documents, images,
  listening, tools) and see which one is best for each job. An optional Full Benchmark runs
  GSM8K, IFEval, and HumanEval samples.
- **Profiles**: each person gets their own conversations, with an optional password and photo.
- **Share and back up**: share a conversation as a PDF, copy or save it as Markdown, and export or
  import a whole profile's conversations.
- **Appearance**: light or dark, seven accent colors, and a see-through sidebar you can frost.

## Requirements

- macOS 26 or later, Apple silicon
- [Ollama](https://ollama.com) installed (Local Mind starts it when needed)
- Xcode 26 to build

## Build and run

```bash
./build.sh --open
```

This builds a release copy, installs it to `~/Applications/Local Mind.app`, and opens it.

## Test

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path ~/Library/Developer/Lantern/test-build
tools/selftest.sh
```

The unit tests cover the logic in `LanternKit`. The self-test runs the app's real functions against a
temporary database and a scripted Ollama, and never touches your own conversations.

## Make a DMG

```bash
tools/make_dmg.sh
```

Writes `dist/Local-Mind-<version>.dmg`. It's signed with a development certificate and not notarized, so it's
meant for your own Macs.

## Project layout

| Path | What's there |
|---|---|
| `Sources/Lantern` | The app (SwiftUI and SwiftData) |
| `Sources/LanternKit` | Logic with no UI: the Ollama client, Model Lab, benchmarks, attachments, profiles |
| `Tests/LanternKitTests` | Unit tests |
| `Icon/AppIcon.icon` | The app icon, an Icon Composer file |
| `tools` | Build, snapshot, self-test, icon, and DMG scripts |
| `docs` | The brief, user stories, and design notes |

The code still uses the project's first name, Lantern, for the package and the data folder, so existing
conversations carry over.
