# Pocket

**Your Mac's clipboard remembers one thing. Pocket remembers everything.**

A free, open-source clipboard history that lives in the MacBook notch. Hover the notch (or press **Ctrl + Shift + C**) and your last copies drop down: text, links, screenshots, images and files. Click one and it pastes into the app you're in. Your history stays on your Mac; the only time a clip leaves it is when you choose a cloud AI action (ChatGPT or an OpenAI key) on that clip.

![Pocket open in the notch](docs/pocket.png)

## Download

1. Grab **Pocket.zip** from the [latest release](../../releases/latest) and unzip it.
2. Drag **Pocket.app** into Applications.
3. The first time, **right-click Pocket → Open → Open**. (It's a free app that isn't notarised by Apple, so macOS asks once.)
4. Allow **Accessibility** when asked (System Settings → Privacy & Security → Accessibility → Pocket) so clicking a clip can paste for you.

Needs macOS 14 or later. Apple Intelligence actions need macOS 26.

## Features

- **Smart cards:** links show the site, colours show a swatch, code looks like code, files show their icon.
- **Search** finds text clips, file names and **the text inside screenshots** (read on-device with Apple Vision).
- **Pin** clips you reuse; pinned clips stay first and are never deleted automatically.
- **Keeps formatting** (bold, links, fonts) when pasting; ⌥-click pastes plain text.
- **Grab several at once:** hold **Shift** and tap the arrow keys (or Shift-click) to pick clips, then press **Return** to paste them all in order. ⌘-click and **Ctrl + Shift + V** still paste a queue one by one.
- **Big preview:** Space (or right-click → Preview) shows the whole text or full image.
- **Drag** any card out of the notch into another app.
- **AI actions** (sparkle button, ⌘J or right-click → AI): fix grammar, more formal, shorter, friendlier, summarise, explain, translate, or ask anything, including about a screenshot. The notch glows and shows a "thinking" animation while the AI works.
- **Privacy:** skips anything password managers mark as private, plus any apps you list in Settings. History stays on this Mac in `~/Library/Application Support/NotchClip`.
- **Demo mode** (menu bar → Demo Mode): switches to a separate history filled with sample clips, handy for screen recordings. Your real history is untouched.

![Picking three clips with Shift + arrows](docs/pocket-multi.png)

![Search finds the word "latte" inside a receipt screenshot](docs/pocket-search.png)

## AI options (Settings → AI)

| Option | Cost | Notes |
|---|---|---|
| Apple Intelligence | Free | Runs on this Mac, offline. Text only (including text read from screenshots). Needs macOS 26+. |
| ChatGPT (Sign in with ChatGPT) | Uses your ChatGPT Plus/Pro plan | Official [Sign in with ChatGPT](https://developers.openai.com/siwc) for open-source apps. No API key. Manage usage at chatgpt.com/settings/usage. |
| OpenAI API key | Billed to your API account | Key is stored in the macOS Keychain. |

ChatGPT sign-in follows OpenAI's open-source client guide: dynamic client registration, PKCE with a `127.0.0.1` loopback redirect, ID-token signature checks, refresh-token rotation and revocation on sign-out. Tokens are saved in an owner-only file (`chatgpt/auth.json`, mode 0600) and never logged.

## Keyboard

| Key | Action |
|---|---|
| Ctrl + Shift + C | Open / close (changeable in Settings) |
| Type | Search |
| ← → ↑ ↓ | Choose a clip |
| Shift + ← → ↑ ↓ | Pick several clips; Return pastes them all |
| Return / ⌥Return | Paste / paste as plain text (or the text from a screenshot) |
| ⌘1 … ⌘9, ⌘0 | Paste that clip |
| Space | Big preview |
| ⌘J | AI actions |
| ⌘S | Add to / remove from paste stack |
| Ctrl + Shift + V | Paste next clip from the stack |
| ⌘P / ⌘⌫ | Pin / delete |
| Esc | Back, clear search, close |

Auto-paste needs **Accessibility** permission (System Settings → Privacy & Security → Accessibility → Pocket). Without it, clicking copies and you press ⌘V.

## Build from source

The Swift package and executable are still called `NotchClip` (Pocket's working name).

```bash
swift test
scripts/build-app.sh --install   # builds, signs, copies to /Applications and launches
```

Developer helpers:
- `NotchClip --snapshot out.png [history-folder] [--keyboard] [--query words] [--preview] [--ai thinking|writing|done|failed] [--stack]` renders the open panel to an image.
- `NotchClip --ai-test "some text"` runs one on-device grammar fix and prints it.

## Licence

MIT. Made by [Rayan Abdul Cader](https://minutechbuilds.com) · [@minutechbuilds](https://instagram.com/minutechbuilds)
