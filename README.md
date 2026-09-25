# UOR-RC for Mac & iPhone — first version

Same idea and **same protocol** as UOR-RC on Windows/Android, so the pieces mix:

| Remote | Computer | Works |
|---|---|---|
| 📱 Android | 💻 Windows | ✅ (the full app) |
| 📱 **iPhone** | 💻 **Windows** | ✅ everything the iPhone app offers |
| 📱 Android | 🖥 **Mac** | ✅ the parts the Mac app understands |
| 📱 **iPhone** | 🖥 **Mac** | ✅ |

## What works now
Connect over Wi-Fi with the 4-digit PIN · next / previous / start / end / black & white screen ·
touchpad (move, tap, right-click, two-finger scroll) · type with the phone keyboard ·
🔴 laser · 🔦 spotlight · 🔎 magnifier · ✏️ pen / 🖍 highlighter / 🧽 eraser · 🔢 numbers · 📍 text labels ·
🧑‍🏫 whiteboard (pages, 4 backgrounds, 💾 save every page as a picture) ·
🎲 random picker (class list, no-repeats, 🎡 wheel) ·
🖼 photos & videos full-screen with a remote control · 📑 PDF pages driven like slides ·
📁 files both ways (they land in the **UOR-RC** folder on the Desktop) ·
slide number, speaker notes and the ⌛ timer on the projector.

Each page keeps its own drawings: slide 5, whiteboard page 2 and a photo each remember their own ink.

Also working now: 🗳️ **quiz** (students type their name, written answers, ⏱ countdown, speed scores,
🏆 leaderboard, quizzes saved on the phone) · 📷 **document camera** with 🎤 microphone ·
📸 **group photos** with captions, shown one by one or all together.

The quiz needs one permission on the Mac: the first time, macOS asks whether UOR-RC may accept
incoming connections — answer **Allow**, or the students' phones cannot open the page.

### Batch 3 additions
⌨️ **type on the computer** from the phone, with a key bar (⏎ ⌫ Esc Tab arrows ⌘A ⌘C ⌘V ⌘Z) ·
🎨 **tool settings** (laser size & colour, 8 spotlight styles, lens brightness and dim, pen sizes & colours) ·
🖼 **slide preview** on the phone and inside the touchpad · 🔢 **jump to a slide** (by number or title) ·
🖥 Desktop and ▶ back to the slides · ⌛ **timer panel** (down or up, on the projector, alarm at zero) ·
📺 **see the computer's screen** on the phone and tap it to move the real mouse ·
🔍 **projector zoom** · 📍 text labels typed on the phone · 📥 **files the computer sends you** ·
✏️ **Apple Pencil** drawing on iPad (turn on "pencil only" to rest your hand) ·
🗣 **Siri**: "next slide" · **کوردی** everywhere, with right-to-left layout.

### 📱 Sharing the iPhone's whole screen
Tap the 📱 button in the app, then **Start Broadcast**. Everything on the phone then appears on the
projector — including other apps. It works with **both** a Mac and a Windows PC running UOR-RC.
Apple runs this in a separate little program, which needs an **App Group**, so this one feature
requires a paid Apple developer account (99 $/year). Everything else works with a free account.

## Still only on Windows / Android
Bluetooth (Apple does not allow it for this kind of link) ·
volume-key slide changing on iPhone (Apple does not allow it).

## If the build fails
The Mac runners on GitHub may carry an older Xcode than XcodeGen writes for. This project is
pinned to the Xcode 15 file format and the workflow picks the newest Xcode on the runner, so
`xcodebuild: error: … future Xcode project file format` should not happen again. If a build
still stops, copy the first red line from the Actions log and I'll fix it.

## Build it
Nothing to install if you use GitHub: push this folder and **Actions** builds both apps
(`UOR-RC-Mac.zip` and an unsigned `.ipa`). On your own Mac:

```bash
brew install xcodegen
xcodegen generate
open UOR-RC.xcodeproj      # then press ▶ with your iPhone connected
```

## Install
- **Mac:** unzip, drag **UOR-RC.app** into Applications. Because the app is not signed with a paid
  Apple certificate, macOS blocks apps downloaded from the internet. Open Terminal once and run:

  ```bash
  xattr -dr com.apple.quarantine /Applications/UOR-RC.app
  ```

  then right-click the app → **Open** → **Open**. After that it starts normally. The first time, macOS asks for:
  **Accessibility** (to move the mouse and type), **Screen Recording** (magnifier) and
  **Automation → PowerPoint/Keynote**. System Settings → Privacy & Security.
- **iPhone:** Apple does not allow APK-style installs.
  - *Free:* open the project in Xcode with your Apple ID and press ▶ — works for 7 days, then press ▶ again.
  - *Paid (99 $/year):* TestFlight or Ad-Hoc — installs normally and stays.
  - The first run asks to allow **Local Network**; say yes or the phone can't see the computer.

## Use
1. Put the iPhone and the computer on the same Wi-Fi (the laptop hotspot is ideal).
2. Open UOR-RC on the computer — it shows a 4-digit PIN.
3. On the iPhone: **Connect** → pick the computer → type the PIN.
