# Fix log

## Menu bar item stayed off after test runs
Symptom: the menu bar item never appeared, and `showMenuBarItem` was stored as false.
Cause: self-test and snapshot runs hide the item through `isInserted`, and SwiftUI wrote that false back through the binding's setter, which saved it to the real preferences.
Fix: the setter ignores writes during self-test and snapshot runs.
Rule: A binding that hides something for a test run must never write to real preferences.

## Typed characters were lost in the message field
Symptom: fast typing dropped characters, so "Alpha" became "lA".
Cause: a SwiftUI `TextField` with a `selection` binding.
Fix: the message field is a real `NSTextView` (`ComposerField`).
Rule: Text entry people use constantly goes through `NSTextView`, not a selection-bound `TextField`.

## A busy Ollama looked like a lost connection
Symptom: a reply ended as "Interrupted" after a cancelled model load.
Cause: `/api/ps` took 23 seconds under memory pressure, past a 5 second timeout, and that failure ended the reply.
Fix: a longer timeout, and the check before a reply can no longer fail it.
Rule: A status check must never be able to fail the work it only informs.
