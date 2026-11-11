# Local Mind: product review

2026-11-12. Written as a product manager at an AI company would look at it before launch.

## Verdict

A polished, private chat app for local models with a real point of view: it runs on your Mac,
tells you honestly what each model is good at, and stays out of the way. The core loop (ask, read,
attach, switch models, test models) is complete and well made. It is **not yet ready to give to
someone else**: a new person can't get a model without the Terminal, can't install the app without
a security warning, and can't take a conversation out of the app.

## What's strong (keep)

- **Private by design.** Everything stays on the Mac; profiles keep people's chats apart.
- **Quick Ask** from any app, and the **menu bar aperture** that shows whether a model is ready.
- **Model Lab.** Testing models on this Mac and naming the best one for each job is unusual and
  genuinely useful. Most apps leave people guessing.
- **Audio and attachments**, with previews, and transcription that was measured, not assumed.
- **Design.** Calm, native, with its own character: the swirl mark, the serif greeting, Clay.

## Must have before sharing it (P0)

1. **Download models inside the app.** Today the empty state says "run `ollama pull gemma4`".
   Most people will stop there. Add a small catalog of recommended models (sized for the Mac's
   memory) with a Download button and progress, using Ollama's `/api/pull`. Also Delete.
2. **Ship it properly.** The app is signed with an *Apple Development* certificate, so on any
   other Mac it is blocked by Gatekeeper. Needs a Developer ID certificate, notarization, and a
   DMG. Then automatic updates (Sparkle), or people stay on the first version forever.
3. **Share and export a chat.** Copy as Markdown, Save as PDF, and the Mac share sheet. (Discussed
   earlier and deferred.)
4. **First run.** One short welcome: what Local Mind is, check Ollama, pick a first model sized for
   this Mac. Today a new person lands on an empty chat.

## Should have (P1)

5. **Talk to it.** A microphone button that records and sends audio, since the models already hear
   well. A natural, delightful next step after transcription.
6. **Custom instructions.** A short "how should replies sound" text per profile, sent as the
   system prompt. Every major assistant has this.
7. **Think on or off.** Thinking models always think today. A switch beside the model picker
   trades depth for speed.
8. **Backup and move.** Export all of a profile's conversations to one file and import it again.

## Could have later (P2)

9. Folders or projects for conversations.
10. Translations (the app is English only).
11. Model settings for experts (temperature, context length), hidden under Advanced.

## Change or remove

- **Full Benchmark** (downloads research datasets, runs code in a sandbox) is impressive but niche.
  Keep it, but move it under an "Advanced" heading in the Lab so the Quick Check is the obvious path.
- **Profile passwords** keep people out of the app, not out of the files. Say so in Edit Profile, or
  later encrypt each profile's conversations.
- **The name.** Check "Local Mind" for existing apps and trademarks before publishing anywhere.

## Suggested order

Download models → First run → Share and export → Developer ID, notarization, DMG, updates →
Microphone → Custom instructions → Think switch → Backup.
