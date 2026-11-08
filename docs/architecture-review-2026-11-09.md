# Architecture review, end of Milestone 2

The code is in good shape for its size: 3,000 lines, no file over 400, and no duplicated private types. Nothing needs refactoring now, so every card is below `Strong`.

## Reply writing inside AppModel  [Worth exploring]

Files: Sources/Lantern/AppModel.swift (366 lines, 28 functions)
Signal: end of milestone; the file is the app's largest and grows with every story.
Problem: `AppModel` holds connection state, model choice, conversation actions, and the reply loop. Quick Ask (S-021, S-022) will send replies from a second surface, and it would add more state here.
Proposal: before M4, move the reply loop into a `ReplyWriter` that owns `writingReplyID`, `writingPhase`, `stop()`, and `runReply`. `AppModel` keeps connection state and conversation actions.
Benefits: locality for streaming changes, and Quick Ask reuses one module.
Proof of same behavior: the 52 self-test checks and a live reply through `APP_SELFTEST_LIVE`.
Plan: one commit to add `ReplyWriter`, one to move callers.

## Search work on the main thread  [Speculative]

Files: Sources/Lantern/Views/ConversationSidebar.swift, Sources/LanternKit/ConversationList.swift
Signal: slow work on the main thread.
Problem: each keystroke scans every message in every conversation. That's instant today, but could lag with thousands of conversations.
Proposal: measure first, with the `performance` skill, once real history exists. Only then debounce or index.
Proof of same behavior: the S-015 unit tests.

## ScriptedTransport ships in the library  [Speculative]

Files: Sources/LanternKit/ScriptedTransport.swift
Signal: test hook outside the tests.
Problem: the self-test needs it inside the app, so it ships in the release build.
Proposal: leave it. It's about 100 lines, runs only with `--selftest`, and gives the `OllamaTransport` seam its second adapter.

## Top recommendation

Do nothing now. Extract `ReplyWriter` as the first step of M4, when Quick Ask gives it a second caller.

## Milestone 3 update

Still no `Strong` candidates. The code is 3,600 lines, and `AppModel` stayed at 377 because attachments went into `AppModel+Attachments.swift`. Repeated attachments now travel with every request in a conversation, so very long image conversations may get slow. Measure that before changing it.

## Considered, not recommended

- Splitting `Markdown.parse`: long, but one straight loop that's fully covered by tests.
- A protocol around SwiftData: only one store, and the self-test already uses a real one on a /tmp file.
