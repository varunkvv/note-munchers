# note munchers

an iPad / iPhone / mac app that helps a kid learn to read sheet music on a real piano.

he sees a note on the staff and plays the key on his digital piano over MIDI. no tapping answers on screen. it moves to the next note only when he's solid on the ones he has. every note he learns gets its own silly muncher that grows as he finds that note faster.

- `NoteCore/` - swift package with all the logic (pitches, staff positions, curriculum, mastery, judging, session). no UI. `cd NoteCore && swift test`
- `App/` + `project.yml` - the app. `NoteMunchers.xcodeproj` is generated from `project.yml` with `xcodegen generate` and committed

## put it on the iPad

needs a mac with Xcode and a free apple ID. xcodegen is not needed, the project file is committed.

1. `git clone https://github.com/varunkvv/note-munchers.git` and open `NoteMunchers.xcodeproj`
2. Xcode > settings > accounts: add your apple ID
3. pick the NoteMunchers target > signing & capabilities > team: your personal team. if the bundle id is taken, change `com.varunkvv.notemunchers` to something of your own
4. plug the iPad in with the cable, pick it as the run destination and press run
5. first time only: on the iPad, settings > privacy & security > developer mode on (it asks for a restart), then trust the developer under settings > general > VPN & device management

keep in mind - with a free apple ID the app stops opening after 7 days. plug in and press run again (day 6 is a good habit). a paid developer account makes it last a year.

the iPad has one port and the piano's MIDI cable needs it. so after the first install, open window > devices and simulators, select the iPad and tick "connect via network". from then on Xcode installs over wifi while the piano stays plugged in.

check the piano first: hold the grey gear on the home screen for 3 seconds to open the parent area, then MIDI monitor. press a few keys across the keyboard and check the names (middle C is C4).

the mac build runs the same app on the mac with no apple ID needed. plug the piano's cable into the mac and pick "my mac" as the destination.
