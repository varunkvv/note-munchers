# note munchers

an iPad / iPhone / mac app that helps a kid learn to read sheet music on a real piano.

he sees a note on the staff and plays the key on his digital piano over MIDI. no tapping answers on screen. it moves to the next note only when he's solid on the ones he has. every note he learns gets its own silly muncher that grows as he finds that note faster.

- `NoteCore/` - swift package with all the logic (pitches, staff positions, curriculum, mastery, judging, session). no UI. `cd NoteCore && swift test`
- `App/` + `project.yml` - the app. `NoteMunchers.xcodeproj` is generated from `project.yml` with `xcodegen generate` and committed
