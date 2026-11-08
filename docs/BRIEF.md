# Lantern

A native Mac app for chatting with local Ollama models, made for one person who wants asking a private, offline model to become a daily habit.

Bundle id: `com.toofiuea.lantern`

## Replaces
The Ollama desktop app and `ollama run` in the terminal. Ollama stays installed as the engine; Lantern never modifies Ollama.app.

## Main jobs
1. Ask a quick question from any app with a global shortcut, and get a streaming reply in a floating panel.
2. Write and rewrite: drafts, emails, summaries, translations, fixing text, with one-click copy of the result.
3. Get coding help: explain errors, review snippets, learn code, with formatted code blocks and a copy button on each.
4. Ask about files and images: drop in a PDF, text file, screenshot, or photo and ask about it.

## Data
- Conversation: title, created, updated, model name, pinned
- Message: role, text, thinking text, created, model name, tokens per second
- Attachment: kind (image, PDF, text), file name, stored image data or extracted text

Settings (default model, shortcut, keep-loaded time) live in user defaults, not the data model.

## Shape
A sidebar window plus a quick-ask floating panel. macOS 26 or later. Native SwiftUI.
Local data. Works offline. No accounts.

Pages: Conversation, conversation search and pinned list in the sidebar, Models, Settings.

The engine is Ollama's local API at `localhost:11434`, used for streaming chat, thinking, images, and listing models. The app makes no other network calls.

Built for 16 GB of RAM:
- One model loaded at a time. Switching unloads the previous model first.
- The Models page shows what is loaded, its size, and an Unload button.
- Models unload after an idle time set in Settings.
- If Ollama isn't running, Lantern starts it, or shows one clear message if it can't.

Models show only the attachment and thinking controls they support, read from each model's capabilities.

## System hooks
- Global shortcut for the quick-ask panel: default ⌃⌥Space, changeable in Settings
- Menu bar item showing the loaded model, with Ask and Unload actions
- Open a quick-ask conversation in the main window to continue it

## Reference
None to clone. The leading AI desktop apps set the bar for chat quality.

## Look
Native Mac with the system accent color: standard sidebar, toolbar, and Liquid Glass. Chosen so it feels like a built-in app.

## Not in version one
- Projects with instructions and files, saved prompts, and local memory (next)
- Tools: file reading, web search, and MCP connections, with approval prompts (after that)
- Agent mode for code (only if the models handle it well)
- Audio attachments (the models list audio support; confirm how Ollama's API accepts it first)
- Downloading and deleting models in the app (`ollama pull` still does this)
- Accounts, sharing, and sync. Later, if wanted: iCloud sync
