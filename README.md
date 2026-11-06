# NotchClip

A clipboard history that lives in the MacBook notch. Hover the notch (or press **Ctrl + Shift + C**) and your last copies drop down: text and screenshots/images, 10 at a glance. Click one and it pastes into the app you're in.

- Search box: finds text clips **and the text inside screenshots** (read on-device with Apple Vision).
- Pin clips you reuse (right-click → Pin, or ⌘P); pinned clips stay first and are never dropped.
- Images with text get a TEXT badge: right-click → Paste Text from Image (or ⇧Return).
- Keyboard: type to search, arrows to choose, Return to paste, ⌘1–⌘9 / ⌘0 to paste directly, ⌘⌫ to remove, Esc to clear search / close.
- Skips anything password managers mark as private.
- History (last 50) is stored only on this Mac in `~/Library/Application Support/NotchClip`.
- Auto-paste needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility → NotchClip). Without it, clicking copies and you press ⌘V.
- Menu bar icon: open, turn on auto-paste, Open at Login, clear history, quit.

## Build

```bash
swift test
scripts/build-app.sh --install   # builds, signs, copies to /Applications and launches
```

`NotchClip --snapshot out.png [history-folder] [--keyboard]` renders the open panel to an image.
