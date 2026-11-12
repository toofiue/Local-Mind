# Lantern user stories

Source: `docs/BRIEF.md`. No reference app, so `Screens:` names the snapshot pages that show each story.

Snapshot pages: `chat`, `chat-empty`, `chat-thinking`, `chat-attachments`, `offline`, `sidebar-search`, `models`, `settings`, `quick-panel`, `menu-bar`.

## M1 Core loop

### S-001 Connect to Ollama at launch
As the user, I open Lantern and it connects to Ollama and lists my models without any setup.
Screens: chat-empty
Acceptance:
- [unit] With Ollama reachable, the client returns every model from `/api/tags` with its name and size.
- [unit] Each model's capabilities are read from `/api/show` and stored by model name.
- [self] If Ollama isn't running, Lantern starts it and connects within 15 seconds.
- [snap] The model picker shows the default model's name once connected.
UX:
- Flow: open Lantern -> model picker fills -> message field has focus, ready to type. Way back: nothing to undo; connecting never blocks reading past conversations.
- Surface: inline on the conversation page (changes one value already on screen).
- States: loading "Starting Ollama…" only after half a second; failure goes to S-002; no models goes to S-034; long model names truncate with the full name in a tooltip.
- Words: "Starting Ollama…"; first view line "Replies are written on this Mac by local models. Nothing leaves it."
- Access: focus lands in the message field; VoiceOver announces "Connected to Ollama".
Status: done

### S-002 See why Lantern can't reach Ollama
As the user, I see one clear message and a Try Again button when Ollama can't be started.
Screens: offline
Depends: S-001
Acceptance:
- [snap] The window shows the message and a Try Again button, and the message field is disabled.
- [self] Try Again connects and returns to the chat when Ollama becomes reachable.
- [unit] A connection failure during a reply keeps the partial text and marks the message as interrupted.
UX:
- Flow: connection fails -> message and Try Again above the message field -> click or Return -> field is enabled again. Way back: past conversations stay readable the whole time.
- Surface: inline, next to the problem (information with a fix doesn't need an alert).
- States: error as below; while retrying the status reads "Starting Ollama…"; an interrupted reply keeps its text with "Interrupted" below it.
- Words: "Unable to start Ollama. Open Ollama from Applications, then try again."; button "Try Again"; "Interrupted. Lantern lost its connection to Ollama."
- Access: Try Again takes focus when the message appears; VoiceOver reads the message; the state uses words and an icon, not color alone.
Status: done

### S-003 Send a message and watch the reply stream
As the user, I type a message, press Return, and the reply appears as it is generated.
Screens: chat
Depends: S-001
Acceptance:
- [unit] The stream parser turns newline-delimited `/api/chat` chunks into text deltas and a final done event.
- [unit] Each request includes the whole conversation so far, in order.
- [self] Text appears before the reply finishes, and the view follows the newest line.
- [self] Shift-Return adds a new line instead of sending.
- [self] Scrolling up during a reply stops the view from following.
UX:
- Flow: type in the message field -> Return or Send -> message appears, reply streams -> focus stays in the field. Way back: Stop (S-004), then Retry (S-024) or edit the message (S-025).
- Surface: inline on the conversation page (a place people come back to).
- States: Send is disabled while the field is empty; a model being loaded shows S-006's text in the reply's place; when scrolled up, a "Jump to Latest" button appears; long replies scroll smoothly.
- Words: placeholder "Ask anything"; Send tooltip "Send this message to the model (↩)"; every reply is labeled with the name of the model that wrote it, which marks it as generated.
- Access: the field's VoiceOver label is "Message" (a chat field's placeholder is a deliberate exception to the visible-label rule); new reply text is announced when it finishes, not word by word.
Status: done

### S-004 Stop a reply
As the user, I press Stop or Escape to end a reply that is still generating.
Screens: chat
Depends: S-003
Acceptance:
- [self] The stream ends within one second and the text so far stays in the conversation.
- [snap] The Send button shows as Stop while a reply is generating.
- [unit] A stopped reply is saved with its partial text.
UX:
- Flow: Stop button, Escape, or Stop in the menu (S-026) -> writing ends -> text stays with "Stopped" below it -> focus in the message field. Way back: Retry (S-024).
- Surface: inline, the Send button changes to Stop in place without moving.
- States: Stop shows only while a reply is being written; "Stopped" appears at once, in the same frame.
- Words: "Stop"; tooltip "End this reply and keep its text so far (⎋)"; "Stopped".
- Access: Escape works from the message field; VoiceOver reads the button as "Stop" while writing and "Send" otherwise.
Status: done

### S-005 Keep conversations after a restart
As the user, I quit and reopen Lantern and all my conversations are still there.
Screens: chat
Depends: S-003
Acceptance:
- [unit] A Conversation with Messages survives saving and reloading from a new model container.
- [self] After a restart, the sidebar lists earlier conversations with the newest first.
- [self] Clicking a conversation shows its messages. Command-N starts a new one.
UX:
- Flow: Command-N, toolbar New Conversation, or File > New Conversation -> empty conversation with focus in the message field; or click a sidebar row -> its messages show. Way back: click the earlier row. An empty conversation isn't saved until its first message.
- Surface: sidebar page (a place people come back to).
- States: empty sidebar "No Conversations. Conversations you start appear here." with New Conversation; long titles truncate with the full title in a tooltip; a thousand rows still scroll smoothly.
- Words: "New Conversation"; tooltip "Start a conversation with the default model (⌘N)".
- Access: arrow keys move through the sidebar; VoiceOver reads each row's title and date.
Status: done

### S-006 Choose a model for a conversation
As the user, I pick a model from the toolbar and the next message uses it.
Screens: chat
Depends: S-001, S-003
Acceptance:
- [unit] Switching model sends an unload request (`keep_alive: 0`) for the previous model before loading the next.
- [unit] A conversation remembers its model and each Message records the model that wrote it.
- [self] During the first load, the reply area says the model is loading.
- [snap] The picker lists all installed models with the current one checked.
UX:
- Flow: click the toolbar picker or press ⇧⌘M -> popover of models -> choose one -> picker shows it, focus returns to the message field. Way back: choose the previous model. The picker is disabled while a reply is being written.
- Surface: popover from the toolbar (SwiftUI can't open a toolbar menu from a shortcut, and ⇧⌘M needs to).
- States: first load shows "Loading gemma4:12b-mlx…" in the reply's place, with the model's real name; a failed load shows "Unable to load gemma4:12b-mlx. Close other apps to free memory, then click Retry."
- Words: label "Model"; tooltip "Choose which model writes the next reply (⇧⌘M)".
- Access: the list works with arrow keys and Return; VoiceOver reads the model's name on the button.
Status: done

### S-007 Read formatted replies
As the user, I see headings, lists, tables, bold text, and code blocks properly formatted.
Screens: chat
Depends: S-003
Acceptance:
- [snap] A seeded reply shows a heading, a list, a table, and a code block, in light and dark mode.
- [unit] An unclosed code fence during streaming renders as code, not as raw backticks.
- [self] Text in replies can be selected and copied.
UX:
- Flow: reply streams -> formatting applies as text arrives -> read and select. Way back: nothing to undo, formatting changes no data.
- Surface: inline in the conversation.
- States: while streaming, unfinished tables and code blocks show what has arrived without jumping; wide tables and long code lines scroll inside their own block and never widen the page.
- Words: none on screen.
- Access: VoiceOver reads headings as headings and tables as tables; text respects Increase Contrast and stays 10 pt or larger.
Status: done

### S-008 Copy a code block
As the user, I click Copy on a code block and only that code goes on the clipboard.
Screens: chat
Depends: S-007
Acceptance:
- [snap] Each code block shows its language and a Copy button.
- [unit] The copied text has no fence markers or language label.
- [self] The button shows Copied for about two seconds.
UX:
- Flow: click Copy on the code block -> clipboard filled -> button reads Copied, then returns. Way back: not needed, nothing in the conversation changes.
- Surface: inline in the code block header.
- States: a block with no language is labeled "Code"; Copy appears once the block has finished streaming.
- Words: "Copy", "Copied". It has a text label, so it needs no tooltip.
- Access: reachable with Tab; VoiceOver reads "Copy Swift code" using the block's language.
Status: done

### S-009 Copy a whole reply
As the user, I click Copy under a reply and paste the text somewhere else.
Screens: chat
Depends: S-007
Acceptance:
- [snap] Finished replies show a Copy action below them.
- [unit] The copied text is the reply's Markdown without the thinking text.
UX:
- Flow: click Copy below a reply, or ⇧⌘C for the latest reply -> clipboard filled -> icon changes to a checkmark for two seconds. Way back: not needed, nothing in the conversation changes.
- Surface: inline action row below the reply.
- States: the action row appears when the reply has finished. Retry and Edit join it in S-024 and S-025.
- Words: tooltip "Copy this reply as Markdown (⇧⌘C)".
- Access: always visible, not hover-only; VoiceOver reads "Copy reply" and announces "Copied".
Status: done

### S-010 See the model's thinking
As the user, I expand a Thinking section above a reply to read how the model reasoned.
Screens: chat-thinking
Depends: S-003
Acceptance:
- [unit] Thinking chunks and reply chunks are stored in separate fields.
- [snap] Finished thinking is collapsed under a Thinking label, and expands on click.
- [self] Thinking is visible while it streams, and collapses when the reply starts.
- [unit] Models without the thinking capability don't send the `think` option.
UX:
- Flow: model thinks -> "Thinking…" streams above the reply -> collapses to "Thinking" when the reply starts -> click to expand or collapse. Way back: click again.
- Surface: inline disclosure above the reply (shows detail in place).
- States: no thinking from the model means no section; long thinking scrolls inside a set height.
- Words: "Thinking…" while it streams, "Thinking" when finished.
- Access: Space toggles it when focused; VoiceOver reads "Thinking, collapsed"; Reduce Motion replaces the slide with a fade.
Status: done

## M2 Organize

### S-011 Name a conversation automatically
As the user, a new conversation gets a short title from my first message.
Screens: chat
Depends: S-005
Acceptance:
- [unit] The title is the first line of the message, trimmed to 50 characters at a word boundary.
- [snap] The sidebar shows the title, not "New Conversation", after the first message.
Status: done

### S-012 Rename a conversation
As the user, I rename a conversation from its context menu.
Screens: chat
Depends: S-005
Acceptance:
- [self] Rename turns the row into a text field, and Return saves it.
- [unit] A title I set is not replaced by the automatic title.
UX:
- Flow: context menu Rename, or Conversation > Rename (⇧⌘R) for the selected one -> row becomes a text field with its title -> Return or clicking away saves. Way back: Escape keeps the old title.
- Surface: inline in the row (changes one value already on screen).
- States: an empty title keeps the old one; long titles scroll inside the field.
- Words: "Rename"; field label "Title".
- Access: focus moves to the field and back to the message field after saving; VoiceOver reads "Title".
Status: done

### S-013 Pin a conversation
As the user, I pin a conversation so it stays at the top of the sidebar.
Screens: chat
Depends: S-005
Acceptance:
- [snap] Pinned conversations appear in a Pinned section above the rest.
- [unit] Pinned conversations sort by most recently updated.
- [self] Unpin returns it to its place in the list.
UX:
- Flow: context menu Pin, or Conversation > Pin (⇧⌘P) -> row moves into Pinned at once. Way back: Unpin in the same places.
- Surface: inline, a sidebar section (a place people come back to).
- States: no pinned conversations means no section headers at all; with pins, sections read "Pinned" and "Recent"; pinning doesn't change a conversation's date.
- Words: "Pin", "Unpin"; a pin symbol on pinned rows isn't needed because the section header says it.
- Access: VoiceOver reads the section header; the menu item's name changes between Pin and Unpin.
Status: done

### S-014 Delete a conversation
As the user, I delete a conversation from its context menu after confirming.
Screens: chat
Depends: S-005
Acceptance:
- [self] Delete asks for confirmation, then removes the row and selects the next one.
- [unit] Deleting a Conversation also deletes its Messages and Attachments.
UX:
- Flow: context menu Delete, Conversation > Delete, or the Delete key on the selected row -> confirmation -> Delete removes it and selects the next row. Way back: Cancel or Escape.
- Surface: confirmation dialog (a rare action that destroys data and can't be undone).
- States: Delete is unavailable while that conversation's reply is being written; deleting the last one shows the new conversation page.
- Words: title "Delete “<title>”?", message "You can't undo this action.", buttons "Delete" and "Cancel".
- Access: Escape cancels; the Delete button is marked destructive.
Status: done

### S-015 Search conversations
As the user, I type in the sidebar search and see conversations that match.
Screens: sidebar-search
Depends: S-005
Acceptance:
- [unit] Search matches conversation titles and message text, ignoring case.
- [snap] Results show the title and a snippet around the match.
- [self] Clicking a result opens the conversation. Clearing search restores the list.
- [self] Command-F focuses the search field.
UX:
- Flow: click the search field, ⌘F, or Edit > Search Conversations -> type -> list narrows as you type -> click a result to open it. Way back: clear the field or press Escape to see the whole list again.
- Surface: system search field in the sidebar (filters a place people come back to).
- States: no matches shows the system "No Results" view with your search text; a match only in the title shows the start of the conversation as its snippet; thinking text isn't searched.
- Words: placeholder "Search"; menu item "Search Conversations".
- Access: results are ordinary list rows with arrow-key movement; VoiceOver reads each title and snippet.
Status: done

## M3 Files and images

### S-016 Attach an image
As the user, I drop or paste an image into the message field and ask about it.
Screens: chat-attachments
Depends: S-003
Acceptance:
- [unit] The request sends the image as base64 in the message's `images` field.
- [snap] A thumbnail shows above the field before sending and in the sent message.
- [unit] Images are stored with their Message and survive a restart.
- [self] A screenshot pasted from the clipboard attaches the same way as a dropped file.
UX:
- Flow: drop a file anywhere on the conversation, paste with ⌘V, click the paperclip, or File > Attach Files… (⇧⌘A) -> thumbnail appears above the message field -> write and send. Way back: the X on the attachment (S-019).
- Surface: inline above the message field.
- States: images are shrunk to at most 1,568 pixels before sending; a sent message shows its thumbnails above its text.
- Words: "Attach Files…"; paperclip tooltip "Attach images, PDFs, or text files (⇧⌘A)"; a pasted image is named "Pasted Image".
- Access: every drop has a keyboard path through ⇧⌘A; VoiceOver reads each thumbnail's file name.
Status: done

### S-017 Attach a PDF
As the user, I drop a PDF and ask about what it says.
Screens: chat-attachments
Depends: S-003
Acceptance:
- [unit] PDF text is extracted and added to the prompt with the file name.
- [self] A PDF with no text layer shows a message that it has no readable text.
- [unit] Text that exceeds the model's context is flagged before sending.
- [snap] The attachment shows as a chip with its name and page count.
UX:
- Flow: same ways in as S-016 -> chip with name and page count -> write and send. Way back: the X on the chip.
- Surface: inline chip above the message field.
- States: no text layer shows "“scan.pdf” has no readable text." and nothing attaches; too long shows a warning but still lets you send.
- Words: "12 pages"; warning "“report.pdf” is longer than this model can read at once. It may only see part of it."
- Access: warnings use words and an icon; VoiceOver reads the name and page count.
Status: done

### S-018 Attach a text or code file
As the user, I drop a text or code file and ask about it.
Screens: chat-attachments
Depends: S-017
Acceptance:
- [unit] UTF-8 text files are read and added to the prompt with the file name.
- [self] A binary file is refused with a message naming the file.
UX:
- Flow: same ways in as S-016 -> chip with the file name -> write and send. Way back: the X on the chip.
- Surface: inline chip above the message field.
- States: an unreadable file shows "Unable to read “app.zip”. Attach an image, PDF, or text file." and nothing attaches.
- Words: as above; the chip's detail reads "Text".
- Access: as S-017.
Status: done

### S-019 Remove an attachment before sending
As the user, I click the X on an attachment to remove it from my message.
Screens: chat-attachments
Depends: S-016
Acceptance:
- [self] The chip or thumbnail disappears and the file is not sent.
UX:
- Flow: click the X -> the attachment disappears at once. Way back: attach it again.
- Surface: inline on the attachment.
- States: sent attachments have no X.
- Words: tooltip "Remove this attachment"; VoiceOver "Remove <file name>".
- Access: the X is always visible, not hover-only, and reachable with Tab.
Status: done

### S-020 Only see attachment options a model supports
As the user, I can't attach an image when the chosen model can't read one.
Screens: chat-attachments
Depends: S-006, S-016
Acceptance:
- [unit] Image attachment is available only for models with the vision capability.
- [self] Dropping an image on an unsupported model shows a message naming the model.
UX:
- Flow: attach an image with a model that can't read one -> message above the field, nothing attaches. Switching to such a model with an image already attached blocks Send with the same message.
- Surface: inline above the message field.
- States: PDFs and text files work with every model, so only images are checked.
- Words: "gpt-oss:20b can't read images. Choose a model that can."
- Access: the message uses words and an icon.
Status: done

## M4 Speed

### S-021 Open quick ask from any app
As the user, I press the global shortcut in any app and a floating panel appears, ready to type.
Screens: quick-panel
Depends: S-003
Acceptance:
- [manual] Control-Option-Space opens the panel over a full-screen app and on the current Space.
- [snap] The panel shows one field and the current model name.
- [self] The field has focus as soon as the panel opens.
- [self] Pressing the shortcut again or Escape hides the panel.
- [self] The panel doesn't activate the main window.
UX:
- Flow: ⌃⌥Space from any app, or Conversation > Quick Ask -> panel appears in the top third of the screen under the pointer, field focused. Way back: Escape, the shortcut again, or clicking away hides it.
- Surface: non-activating panel (input people repeat beside other work), so the app you were in stays in front.
- States: an open Quick Ask starts fresh each time unless a reply is still being written; if Ollama can't be reached it says so where the reply would be.
- Words: placeholder "Ask anything"; the model's name at the trailing edge.
- Access: focus is in the field the moment it opens; VoiceOver reads "Message".
Status: done

### S-022 Get a streaming reply in the panel
As the user, I type in the panel, press Return, and the reply streams right there.
Screens: quick-panel
Depends: S-021, S-007
Acceptance:
- [self] The panel grows to fit the reply, then scrolls past a set height.
- [unit] Each quick ask is saved as a normal Conversation.
- [snap] The formatted reply and a Copy action show in the panel.
UX:
- Flow: type -> Return -> reply streams under the field, panel grows -> type again to follow up in the same conversation. Way back: Escape hides the panel and the reply keeps being written; Stop ends it.
- Surface: the same panel, growing downward from a fixed top edge.
- States: past 480 pt tall the reply scrolls; while another reply is being written elsewhere, Send is unavailable and the panel says "Lantern is finishing another reply."
- Words: Copy and Retry as in the main window, "Stop".
- Access: Return sends and Shift-Return adds a line, as in the main window.
Status: done

### S-023 Continue a quick ask in the main window
As the user, I click Open in Window and carry on with the same conversation.
Screens: quick-panel, chat
Depends: S-022
Acceptance:
- [self] The main window comes forward with that conversation selected, and the panel closes.
UX:
- Flow: Open in Window button or ⌘↩ -> main window comes forward with that conversation selected, panel hides. Way back: ⌃⌥Space opens a fresh Quick Ask.
- Surface: a button in the panel's footer, shown once there's a conversation.
- States: if the main window was closed, it reopens first.
- Words: "Open in Window"; tooltip "Continue this conversation in the main window (⌘↩)".
- Access: works from the keyboard with ⌘↩.
Status: done

### S-024 Retry a reply
As the user, I click Retry under the last reply to get a new one.
Screens: chat
Depends: S-003
Acceptance:
- [unit] Retry replaces the last reply and resends the conversation up to my last message.
- [snap] Retry shows only on the latest reply.
Status: done

### S-025 Edit my last message and resend
As the user, I edit my last message and get a new reply to it.
Screens: chat
Depends: S-024
Acceptance:
- [self] Edit puts the message in an inline field. Saving replaces it and generates a new reply.
- [unit] Editing removes the reply that followed the old text.
UX:
- Flow: pencil below your last message, or Conversation > Edit Message (⇧⌘E) -> message becomes an inline field -> Return saves and writes a new reply. Way back: Escape keeps the original.
- Surface: inline in the conversation (changes one value on screen).
- States: only your latest message can be edited, and not while a reply is being written; an empty edit keeps the original; its attachments stay.
- Words: "Edit Message"; tooltip "Change this message and write a new reply (⇧⌘E)".
- Access: focus moves to the field and returns to the message field after saving.
Status: done

### S-026 Use the app from the keyboard
As the user, I move between conversations and send without touching the mouse.
Screens: chat
Depends: S-005
Acceptance:
- [self] Command-[ and Command-] select the previous and next conversation, as do Command-Up and Command-Down in a one-line field.
- [self] The message field regains focus after a conversation is selected.
- [self] The menu bar lists New Conversation, Search Conversations, and Stop with their shortcuts.
UX:
- Flow: ⌘[ and ⌘], or Conversation > Previous and Next Conversation, from anywhere; ⌘↑ and ⌘↓ too when the message field holds one line. Focus lands in the message field. Way back: the opposite key.
- Surface: menu commands.
- States: at either end nothing moves; ⌘↓ from a new conversation selects the first one. In a multi-line draft ⌘↑ and ⌘↓ keep their normal text meaning.
- Words: "Previous Conversation", "Next Conversation".
- Access: the whole path works without the mouse.
Status: done

## M5 Models and memory

### S-027 See what's loaded
As the user, I open the Models page and see every installed model and which one is using memory.
Screens: models
Depends: S-001
Acceptance:
- [unit] Loaded state and memory size are read from `/api/ps`.
- [snap] Rows show name, disk size, capabilities, and a Loaded badge with memory used.
- [self] The page refreshes within two seconds of a model loading or unloading.
UX:
- Flow: Models at the bottom of the sidebar, or Conversation > Models (⇧⌘L) -> page lists every installed model. Way back: click any conversation.
- Surface: sidebar page (a place people come back to).
- States: the loaded model shows a "Loaded" badge and its memory; the page refreshes every two seconds while it's open.
- Words: "Models", "Loaded", capabilities as "Images, Audio, Thinking, Tools".
- Access: the badge uses a word and an icon, not color alone; VoiceOver reads each row's name, size, and state.
Status: done

### S-028 Unload a model
As the user, I click Unload on the Models page to free its memory.
Screens: models
Depends: S-027
Acceptance:
- [unit] Unload sends `keep_alive: 0` for that model.
- [self] The Loaded badge disappears after unloading.
- [self] While a reply is generating from that model, Unload is disabled.
UX:
- Flow: Unload on a loaded row -> badge disappears when the memory is free. Way back: the next message loads the model again.
- Surface: inline button in the row (acts on one thing on screen).
- States: unavailable while that model is writing a reply, with a tooltip saying why; only loaded rows show it.
- Words: "Unload"; tooltip "Free the memory this model is using".
- Access: reachable with Tab; VoiceOver reads "Unload <model name>".
Status: done

### S-029 Unload models when idle
As the user, I set how long a model stays loaded after I stop using it.
Screens: settings
Depends: S-003
Acceptance:
- [unit] Each chat request sends the `keep_alive` value from Settings.
- [snap] Settings offers 1, 5, 15, and 30 minutes. The default is 5 minutes.
UX:
- Flow: Settings > Models -> choose a time -> applies to the next reply.
- Surface: Settings tab, one picker.
- States: default 5 minutes; a model already loaded keeps its old timer until its next reply.
- Words: "Keep a model loaded for" with "1 minute", "5 minutes", "15 minutes", "30 minutes", and the note "After its last reply. Models use a lot of memory while loaded."
- Access: standard picker.
Status: done

### S-030 Check the model from the menu bar
As the user, I glance at the menu bar and open a menu that shows the loaded model, with Ask and Unload.
Screens: menu-bar
Depends: S-021, S-028
Acceptance:
- [snap] The menu shows the loaded model and its memory, or "No model loaded".
- [self] Ask opens the quick panel. Unload frees the model.
- [manual] Not yet clicked by hand: the item exists, but this Mac's menu bar tucks it behind the » divider, out of reach of automated tests.
UX:
- Flow: click the lightbulb in the menu bar -> menu shows the loaded model -> Quick Ask, Unload, Open Lantern, or Quit. Way back: click away.
- Surface: menu bar item with a menu. Everything in it is also in the main window, and Settings > Models can hide it.
- States: the bulb is filled while a model is loaded; "No Model Loaded" with Unload unavailable otherwise.
- Words: "gemma4:12b-mlx · 7.68 GB", "Quick Ask", "Unload", "Open Lantern", "Quit Lantern"; Settings "Show Lantern in the menu bar".
- Access: standard menu, works with the keyboard.
Status: done

## M6 Polish

### S-031 Set a default model
As the user, I choose the model that new conversations and quick asks use.
Screens: settings
Depends: S-001
Acceptance:
- [unit] New conversations use the default model.
- [unit] If the default model is removed, the last used model, then the smallest installed, is used instead.
- [snap] Settings shows the default model picker.
UX:
- Flow: Settings > Models > Default model -> choose one -> the next new conversation and Quick Ask use it. Way back: choose Last Used.
- Surface: Settings tab, one picker.
- States: "Last Used" is the default; if the chosen model is gone, Lantern falls back to the last used model, then the smallest installed.
- Words: "Default model", "Last Used".
- Access: standard picker.
Status: done

### S-032 Change the quick-ask shortcut
As the user, I record a different global shortcut in Settings.
Screens: settings
Depends: S-021
Acceptance:
- [manual] The new shortcut opens the panel and the old one stops working.
- [self] A shortcut already taken by the system shows a message.
- [unit] The shortcut survives a restart.
UX:
- Flow: Settings > Quick Ask > click the shortcut -> "Type a Shortcut…" -> press keys -> it saves and takes effect at once. Way back: Escape cancels; Use Default restores ⌃⌥Space.
- Surface: Settings tab, one recorder button.
- States: a shortcut with no ⌘, ⌃, or ⌥ is refused; one macOS or another app uses shows a message and the old shortcut keeps working.
- Words: "Include ⌘, ⌃, or ⌥ in the shortcut.", "macOS already uses that shortcut. Choose another.", "Another app already uses that shortcut. Choose another."
- Access: the recorder is a button reachable with Tab; VoiceOver reads the current shortcut.
Status: done

### S-033 See reply speed
As the user, I see how fast a reply was generated, in tokens per second.
Screens: chat
Depends: S-003
Acceptance:
- [unit] Tokens per second is `eval_count` divided by `eval_duration` from the final chunk, saved on the Message.
- [snap] The speed shows in small text below finished replies.
UX:
- Flow: a reply finishes -> its speed appears in the row below it.
- Surface: inline, small text beside Copy and Retry.
- States: replies with no timing from Ollama, such as stopped ones, show nothing.
- Words: "28 tokens per second".
- Access: plain text VoiceOver can read.
Status: done

### S-034 Understand empty states
As the user, I see helpful text when there are no conversations, no search results, or no models.
Screens: chat-empty, sidebar-search, models
Depends: S-015, S-027
Acceptance:
- [snap] A new conversation shows the model name and a focused message field.
- [snap] With no models installed, the page shows the `ollama pull` command with a Copy button.
- [snap] Search with no matches says so.
UX:
- Flow: with no models installed -> the page explains it and gives the command with Copy -> install in Terminal -> come back and the models appear.
- Surface: the system empty-state view, inline on the conversation and Models pages.
- States: Lantern checks for new models whenever you switch back to it.
- Words: "No Models Installed", "Install one in Terminal. It appears here when you come back.", "ollama pull gemma4", "Copy", "Copied".
- Access: the command is selectable text.
Status: done

### S-035 Recognize the app in the Dock
As the user, I see a Lantern icon in the Dock and menu bar.
Screens: menu-bar
Acceptance:
- [snap] The app icon renders in light, dark, and tinted looks.
- [snap] The menu bar icon is a template image that adapts to the bar.
Status: done

## M7 Your models

### S-036 Tell the toolbar controls apart and stop Jump to Latest lingering
As the user, I see New Conversation and the model as separate controls, and Jump to Latest goes away when I scroll back to the bottom.
Screens: chat
Acceptance:
- [snap] The model button and New Conversation are separate controls with the same look.
- [manual] Scrolling back to the bottom by hand hides Jump to Latest.
- Note: both scroll logs reach the new check at the real bottom, but a person still needs to confirm the button clears.
Status: done

### S-037 Name a model
As the user, I give a model my own name, and see it in conversations and Quick Ask with the original name in small text below where there's room.
Screens: models, model-picker, chat
Acceptance:
- [unit] A name I set is saved, and an empty name restores the original.
- [snap] The picker and Models page show my name with the original below it.
- [self] Replies and Quick Ask show my name.
UX:
- Flow: pencil on a Models row -> field -> Return saves. Way back: Escape keeps the old name; saving an empty name restores the original.
- Surface: inline in the row.
- Words: "Name This Model"; field label "Model name".
Status: done

### S-038 Change the model in Quick Ask
As the user, I switch models from the Quick Ask panel.
Screens: quick-panel
Depends: S-021, S-037
Acceptance:
- [self] Choosing a model changes the one the next message uses, including in a conversation already started.
- [self] The menu is unavailable while a reply is being written.
UX:
- Flow: click the model name in the panel -> menu -> choose. Way back: choose another.
- Surface: a menu, so the panel keeps keyboard focus and stays open.
Status: done

### S-039 Warn before a model that won't fit
As the user, when a model is too big for the memory free right now, Lantern tells me which apps to close before it loads.
Screens: chat
Acceptance:
- [unit] Fit is comfortable, needs closing apps, or too large, from the model's size and this Mac's memory.
- [self] Sending is held with a warning, and Send Anyway goes ahead.
- [self] A model already loaded is never warned about.
UX:
- Flow: send -> warning above the field naming what's using memory -> close apps, then Check Again; or Send Anyway. Way back: change the model.
- Surface: inline above the field, in the main window and Quick Ask. Lantern never closes apps itself.
- Words: "Check Again", "Send Anyway".
- Privacy: memory and app names are read on this Mac and never leave it.
Status: done

### S-040 Test what a model is good at
As the user, I run a test on any model and see what it's suitable for and where it struggles.
Screens: model-lab
Depends: S-027, S-039
Acceptance:
- [unit] Each test is graded from the model's reply by a fixed rule.
- [unit] Image and tool tests only run for models that support them.
- [unit] The report turns scores into "Good for" and "Limits".
- [self] A run saves its report, and Stop ends it.
- [manual] A full run on a real model finishes and frees its memory.
UX:
- Flow: Test on a Models row -> page shows this Mac and the model's fit -> Run Test -> progress -> results. Way back: Models.
- Surface: a page in the main window, since a run takes minutes.
- States: only one thing runs at a time, so sending waits while a test runs.
Status: done

### S-041 Show only my name for a model while chatting
As the user, I see just my custom name in the toolbar, and the original name only where I'm choosing from all models.
Screens: chat, model-picker
Acceptance:
- [snap] The toolbar shows one line: my custom name.
- [snap] The picker shows my name with the original below it.
Status: done

### S-042 Manage models on a page designed for it
As the user, I rename, test, and unload models from clear controls on a tidy page.
Screens: models
Depends: S-037
Acceptance:
- [snap] Models are grouped into In Memory and Installed, each row with its name, original name, size, abilities, and test result.
- [self] Rename opens a sheet with the model's name; Save applies it, and Use Original removes it.
UX:
- Flow: the More menu or a right-click -> Rename… -> sheet -> Return saves. Way back: Cancel or Escape.
- Surface: a sheet, a short task that finishes or cancels.
- Words: "Name This Model", "Use Original", "Cancel", "Save".
Status: done

### S-043 See what each test measures and which standard it follows
As the user, I see what's being tested, the rule that scores it, the standard it's based on, and what the model actually said.
Screens: model-lab, model-lab-intro
Depends: S-040
Acceptance:
- [unit] Every area states what it measures and how it's scored, and names its standard or says it has none.
- [unit] Each result keeps what was asked and what was expected.
- [unit] The long document test checks facts at the start, middle, and end.
- [snap] Before a run the page lists every area; after a run it shows the overall score, then each area with its tests.
UX:
- Words: results say plainly that this is a quick check, and that scores can't be compared with published benchmark numbers.
Status: done

### S-044 Run the real published benchmarks
As the user, I run a model through the actual GSM8K, IFEval, and HumanEval question sets and get a score I can trust.
Screens: model-lab
Depends: S-040
Acceptance:
- [unit] Each set's published format is read correctly, and a file that isn't the exact expected one is rejected.
- [unit] All 25 IFEval instruction types are checked, and strict scoring needs every rule met.
- [unit] Samples pick the same questions for every model, and report a margin of error.
- [self] Model-written code runs with no network, no file writes, no new processes, and no access to personal files, and is killed if it runs too long.
- [self] Only complete sets are described as comparable to published scores.
- [manual] A real sample finishes on a real model.
UX:
- Flow: Test page -> Download -> choose how many questions -> Run Benchmark -> results per set. Way back: Stop keeps what's scored so far.
- Surface: a section on the Test page.
- States: HumanEval is off until you turn it on, because it runs code a model wrote.
Status: done

### S-045 Attach audio for models that can listen
As the user, I attach a voice note or audio file, and a model that lists audio actually hears it.
Screens: chat-attachments
Depends: S-016
Acceptance:
- [unit] Audio in any format macOS reads is converted to 16 kHz mono WAV, which Ollama accepts.
- [self] The audio reaches the model with the message, and a model without audio is refused by name.
- [manual] A real model answers a question about a real recording.
UX:
- Words: chip detail shows the length, like "0:03"; "<model> can't listen to audio. Choose a model that can."; "“<file>” is longer than 5 minutes. Attach a shorter clip."
Status: done

### S-046 Attachment messages clear themselves
As the user, a message about a file that couldn't be attached disappears after a few seconds.
Screens: chat-attachments
Acceptance:
- [self] The message clears after 4 seconds, and a newer message gets its own 4 seconds.
Status: done

### S-047 The model knows when audio or an image is attached
As the user, I attach audio partway through a conversation and the model uses it instead of saying nothing was attached.
Screens: chat
Depends: S-045
Acceptance:
- [unit] Each image or audio attachment is named in the text the model gets, while my message stays as I wrote it.
- [manual] With earlier messages in the conversation, a real model transcribes attached audio.
Status: done

### S-048 Warn about memory only when it matters
As the user, I'm only warned when a model clearly won't fit, in one short line.
Screens: memory-warning
Depends: S-039
Acceptance:
- [unit] A model that fits in free memory plus what macOS can easily reclaim isn't warned about.
- [snap] The warning is one line with Send Anyway; the apps using the most memory are in its tooltip.
Status: done

### S-049 Preview what I attach
As the user, I click an attachment to see the image, hear the audio, or read the PDF.
Screens: chat-attachments
Depends: S-016
Acceptance:
- [self] Clicking an attachment, in the draft or a sent message, opens it in Quick Look.
- [unit] PDFs and text files keep their original file, so the preview shows the real document.
Status: done

### S-050 No length limit on audio
As the user, I attach a recording of any length, and the model decides what it can handle.
Depends: S-045
Acceptance:
- [unit] A long recording isn't refused by Lantern.
Status: done

### S-051 Test how well a model hears
As the user, I see how accurately each model transcribes speech, across voices and lengths.
Screens: model-lab
Depends: S-040, S-045
Acceptance:
- [unit] Transcripts are scored by word error rate, the standard measure for speech recognition.
- [self] Audio tests run only for models that list audio.
Status: done

### S-052 See the best model for each job
As the user, I see which model scored best in each area, and I can test every model in one go.
Screens: models
Depends: S-040
Acceptance:
- [unit] For each area, the model with the highest score wins, and faster wins a tie.
- [self] Test All Models runs the quick check on each model in turn, and Stop ends the queue.
Status: done

### S-053 Iris, with an aperture that shows the model
As the user, I see the app as Iris, and the menu bar aperture tells me at a glance whether a model is on.
Screens: menu bar, app icon
Depends: S-024
Acceptance:
- [self] The aperture is closed with no model, half open while one loads, and open when one is in memory.
- [self] Every visible name says Iris; settings and conversations carry over from Lantern.
Status: done

### S-054 Local Mind, in clay and cream
As the user, I see the app as Local Mind, with a two-color clay and cream identity.
Screens: app icon, all
Depends: S-053
Acceptance:
- [self] Every visible name says Local Mind.
- [self] Clay is the brand accent, shown when the accent follows the Mac.
Status: done

### S-055 A warmer, more personal Local Mind
As the user, a new conversation greets me simply, and the whole app has a warm, calm character.
Screens: chat-empty, chat, settings-appearance
Depends: S-054
Acceptance:
- [snap] A new conversation shows only the mark and a greeting.
- [snap] The Appearance preview shows a small Local Mind window in the chosen color.
Status: done

### S-056 Choose light or dark, and how frosted the sidebar is
As the user, I pick System, Light, or Dark for Local Mind, and slide the sidebar between clear and frosted.
Screens: settings-appearance
Depends: S-055
Acceptance:
- [self] Light and Dark set the app's look; System follows the Mac.
- [self] The frost setting is kept between launches.
Status: done

### S-057 Delete several conversations at once
As the user, I click a conversation to open it and double-click to rename it. To delete several, I right-click and choose Select Multiple, tick the ones I want, and delete them together after one confirmation.
Screens: sidebar
Depends: S-014
Acceptance:
- [self] Delete with several picked asks once, then removes them all and shows the next conversation left.
- [self] A conversation being written is kept.
Status: done

### S-058 Models as cards, and the model's state in the toolbar
As the user, I see each model as a card with its score and memory, the best model for each job above them, and whether the chat's model is in memory right in the toolbar.
Screens: models, chat
Depends: S-052, S-053
Acceptance:
- [snap] Every card is the same height, and a model in memory is outlined in the accent.
- [snap] The toolbar's model button shows an open aperture when the model is in memory.
Status: done

### S-059 A way home, a draft per chat, and messages that wait their turn
As the user, I get back to a new conversation from anywhere, each chat keeps its own unsent text, and I can send in one chat while another is replying.
Screens: sidebar, chat
Depends: S-057
Acceptance:
- [self] Switching chats keeps each one's unsent text and files.
- [self] New Conversation on a new conversation empties the message box; ⌘Z brings the text back.
- [self] A message sent while another chat is replying waits, then starts by itself.
- [snap] New Conversation sits beside the model name on every page.
Status: done

### S-060 A calmer sidebar: day groups and in-place renaming
As the user, I see conversations under Today, Yesterday, Previous 7 Days, and so on, with no time on each row, and I rename one right where it sits, with no box around the text.
Screens: sidebar
Depends: S-059
Acceptance:
- [unit] Conversations group by day, newest first.
- [snap] Renaming shows the name on a gray row with no box; the selected text is in the accent.
Status: done

### S-061 A welcoming home
As the user, a new conversation greets me by name in the middle of the window, with the message box and a few ways to start right under it; when I send, the box glides down and the conversation begins.
Screens: chat-empty
Depends: S-055
Acceptance:
- [snap] The greeting, message box, and starter buttons sit together just above the middle.
- [self] A starter button fills the message box.
Status: done

### S-062 Send past the memory warning with Return
As the user, when the memory warning shows, pressing Return or Send again sends my message anyway, the same as Send Anyway.
Screens: memory-warning
Depends: S-043
Acceptance:
- [self] A second send while the warning shows goes ahead and loads the model.
Status: done

### S-063 Profiles, each with their own conversations
As the user, I share my Mac and my models without sharing my conversations: each person has a profile with a name, an optional password, and their own conversations.
Screens: sidebar, lock
Depends: S-001
Acceptance:
- [unit] Passwords are kept only as a salted, slow hash.
- [unit] The first profile keeps the existing conversations where they are; each new one gets its own folder.
- [self] A new profile gets its own conversation store, and a wrong password doesn't unlock.
- [snap] The sidebar's bottom row shows the profile, Models, and Settings; a locked profile shows only the lock screen.
Status: done

### S-064 A profile photo, and one calm corner
As the user, I pick a photo for my profile, and the bottom-left corner is one row with my photo and name that opens profiles, Models, and Settings.
Screens: sidebar
Depends: S-063
Acceptance:
- [self] A picture becomes a small square photo, can be removed, and a non-picture is refused.
- [snap] The corner shows one row: photo or initial, name, and a chevron.
Status: done

### S-065 Settings as a board in the window, and pages that use a wide window
As the user, Settings opens as a board in the middle of the window, sized to fit the window; the Models page uses the room a big window gives it.
Screens: settings-board, models
Depends: S-064
Acceptance:
- [snap] The board has a largest size and keeps a margin from the window's edges; Escape or a click outside closes it.
- [snap] On a wide window the Models page fills more of it, and the Best For tiles wrap instead of running off the edge.
Status: done

### S-066 One type system, and calm Settings rows
As the user, the app's text follows one calm system (SF Pro for the interface in two weights, New York for display moments, SF Mono for code), and each setting is a row with its name, a short description, and its control.
Screens: settings-board, settings, models
Depends: S-065
Acceptance:
- [snap] No bold headings; hierarchy comes from size and color.
- [snap] Settings rows show a title, a description, and the control on the right, with a line between rows.
Status: done

### S-067 One place for models, inside Settings
As the user, everything about models is in Settings > Models: my models, testing, Best For, which model new conversations use, and how long models stay loaded. Settings holds Profile, Models, Appearance, and General.
Screens: models, settings-board, model-picker
Depends: S-066
Acceptance:
- [snap] Settings > Models shows the two defaults as rows, then one equal-height row per model with aligned size and score columns, then Best For as a short list.
- [snap] Controls in Settings are neutral; the accent marks only a loaded model.
- [self] Every way to Models (profile menu, ⇧⌘L, Manage Models…) opens Settings on Models.
- [snap] The model picker ends with Manage Models….
Status: done

### S-068 A consistent accent, and a curated set of colors
As the user, every Settings section follows one rule (the accent for pickers, switches, and the chosen segment; gray for plain buttons), and I choose from a short set of refined accents.
Screens: settings-appearance, settings-board
Depends: S-067
Acceptance:
- [snap] Pickers and switches use the accent in every section; plain buttons are gray.
- [snap] Accents: System, Clay, Azure, Lagoon, Emerald, Violet, Raspberry, Graphite. A saved accent that's gone falls back to System.
Status: done

### S-069 Thinking stays closed until you open it
As the user, a reply's thinking stays folded away, even while the model is thinking; a "Thinking…" line shows it's working, and a click opens it.
Screens: chat-thinking
Depends: S-008
Acceptance:
- [snap] While a model thinks, its thinking is closed and the line reads "Thinking…".
Status: done

### S-070 Share and export a conversation
As the user, I share a conversation through the Mac's share sheet, copy it as Markdown, or save it as Markdown or PDF.
Screens: chat
Depends: S-001
Acceptance:
- [unit] Markdown has the title, then each turn in order under who said it, with attachments named.
- [self] Save as PDF writes a real PDF.
Status: done

### S-071 Back up and move conversations
As the user, I save all of a profile's conversations to one file and bring them back on this or another Mac.
Screens: settings-profile
Depends: S-063
Acceptance:
- [unit] A backup round-trips exactly, attachments included.
- [self] Importing restores what's missing and skips what's already here.
Status: done

### S-074 Always ready in the background, and a Quick Ask that stays put
As the user, closing the window keeps Local Mind running in the menu bar (out of the Dock), it can open at login without a window, and Quick Ask stays open when I click elsewhere, where I last dragged it.
Screens: quick-panel, settings-general
Depends: S-021, S-024
Acceptance:
- [self] Clicking another window leaves Quick Ask open.
- [manual] Closing the window removes the Dock icon; opening Local Mind again brings the window and the icon back.
- [manual] Open at login starts Local Mind with no window and the shortcut working.
Status: done

## Later
Next after version one:
- Projects with their own instructions and files
- Saved prompts
- Local memory

After that:
- File-reading tools with approval prompts
- Optional web search
- MCP connections
- Agent mode for code, if the models handle it well
- Audio attachments, once Ollama's API support is confirmed
- Downloading and deleting models in the app
- iCloud sync

## Dropped
- Accounts and sign-in: one user on one Mac
- Sharing and teams: personal app
- Billing and upgrade prompts: personal app
- Onboarding tour: S-001 needs no setup, and S-034 covers empty states
- Analytics: nothing leaves the Mac
