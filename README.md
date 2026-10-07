# LLM Translator

**English** · [简体中文](README.zh-CN.md)

A tiny native macOS menu-bar app that translates with any LLM. No Electron, no
Dock icon — it starts instantly and lives in your menu bar.

- **Select text anywhere → press ⌥T (Option+T)** — a floating popup appears at
  your mouse cursor and renders the translation over SSE as soon as the first
  chunk arrives. You do not have to wait for a long response to finish, and the
  app you're in keeps focus.
- **Left-click the menu-bar icon** — a Spotlight-style bar opens; type or paste
  text, press Return to translate, Esc to close.
- **Right-click the menu-bar icon** — a menu: Translate Selection, Translate
  Clipboard, Open Translator Bar, Settings, Quit.
- **Automatic language detection** — on-device. If the text is already in your
  target language, it translates to your *alternate* target instead (e.g. with
  target 中文: English text → 中文, but 中文 text → English).
- **Bring your own model** — pick a provider (Anthropic, OpenAI, Google Gemini,
  DeepSeek, Mistral, OpenRouter, Ollama, LM Studio, or a custom endpoint) and
  paste your API key. Any OpenAI-compatible `/chat/completions` endpoint works.
- The translation instruction (system prompt) and default languages are editable
  in Settings.

---

## Install

Requires **macOS 14 (Sonoma) or newer**.

1. **Open `LLM-Translator.dmg`** (double-click it).

2. **Drag `LLM Translator.app` onto the `Applications` folder** shown in the
   window.

3. **Allow it to open the first time.** This app isn't notarized by Apple, so
   macOS blocks it on first launch. Clear that once, either way:

   **Terminal (fastest)** — open the **Terminal** app, paste this line, press
   Return:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/LLM Translator.app"
   ```

   Then open **LLM Translator** from your Applications folder as normal.

   **No Terminal?** Double-click the app, click **Done** on the warning, then
   open **System Settings → Privacy & Security**, scroll to the bottom, click
   **Open Anyway**, and confirm with Touch ID or your password. (On macOS 15
   Sequoia the old right-click → Open trick no longer works — use this button.)

Once opened, the menu-bar icon (a speech-bubble **A**/文) appears at the top-right
of your screen. There is no Dock icon — that's intentional.

---

## Set up your API key

The **Settings** window opens automatically the first time you launch the app
(you can reopen it any time by right-clicking the menu-bar icon → **Settings…**).

1. **Choose a Provider** from the dropdown. The base URL fills in automatically.
2. **Choose a Model** from the dropdown (or pick **Other…** to type one).
3. **Paste your API key** into the API Key field (⌘V works). It's stored in your
   macOS **Keychain**, never in a plain file.

Where to get a key:

| Provider       | Get a key at                          | Notes                          |
|----------------|---------------------------------------|--------------------------------|
| Anthropic      | console.anthropic.com                 | `claude-haiku-4-5` is fast & cheap |
| OpenAI         | platform.openai.com/api-keys          |                                |
| Google Gemini  | aistudio.google.com/apikey            |                                |
| DeepSeek       | platform.deepseek.com                 |                                |
| Mistral        | console.mistral.ai                    |                                |
| OpenRouter     | openrouter.ai/keys                    | One key, many models           |
| Ollama         | —                                     | Local; leave the API key blank |
| LM Studio      | —                                     | Local; leave the API key blank |

**Running a local model?** Pick **Ollama (local)** or **LM Studio (local)**,
type the model name you have loaded, and leave the API key blank. Make sure the
local server is running.

**Something else?** Pick **Custom…** and enter any OpenAI-compatible base URL
(the app calls `{base URL}/chat/completions`).

---

## How to use

**Translate selected text (⌥T).** Select text in any app, press **⌥T**
(Option+T), and a popup appears at your mouse cursor with the translation. Click
the copy icon to copy it; press **Esc**, click the ✕, or click elsewhere to
dismiss it.

**Translator bar.** Left-click the menu-bar icon to open a floating input bar.
Type or paste text, choose the from/to languages (or use ↔ to swap), and press
**Return**. The result streams in below over SSE and follows the latest output
while a long translation is still being generated.

**Translate the clipboard.** Right-click the menu-bar icon → **Translate
Clipboard** — handy in apps that block ⌘T copying.

---

## Settings reference

- **Languages** — set the default *Translate from* (or **Auto Detect**) and
  *Translate to*. **Alternate target** is used when Auto Detect sees text that's
  already in your target language.
- **Shortcut** — **⌥T (Option+T)** by default; it doesn't clash with normal app
  shortcuts (it only shadows typing the rarely-used `†`). Alternatives: ⌘T
  (careful — that's "new tab" in browsers), ⌃T (transpose/fzf in terminals),
  ⇧⌘T ("reopen closed tab" in browsers), ⌥⌘T.
- **Instruction** — the system prompt sent to the model. Use `{from}` and `{to}`
  as placeholders for the language names. "Reset to Default" restores it.
- **Launch at login** — start the app automatically when you log in.

---

## Permissions

The first time you press ⌥T, macOS asks for **Accessibility** permission — the
app needs it to read the text you've selected in other apps. Grant it in
**System Settings → Privacy & Security → Accessibility**, then press ⌥T again.

---

## Troubleshooting

- **"App is damaged / can't be opened."** The quarantine flag wasn't cleared —
  run the `xattr -dr com.apple.quarantine …` command from the Install section.
- **⌥T does nothing.** Grant Accessibility permission (see above). If you
  rebuilt or reinstalled the app, toggle its entry off/on in the Accessibility
  list — macOS ties the grant to the exact app build.
- **"No text selected."** Some apps don't expose their selection. Copy the text
  and use right-click → **Translate Clipboard** instead.
- **Empty result or an error in the popup.** Check the API key, base URL, and
  model in Settings, and that your endpoint supports OpenAI-compatible SSE with
  `stream: true`. Plain JSON is accepted as a fallback, but cannot appear until
  the complete response has arrived.
- **The shortcut clashes with another app.** Pick a different one in Settings —
  ⌥T is the safest choice.

---

## Build from source (developers)

Plain SwiftPM project — no `.xcodeproj`. Requires Xcode or the Command Line
Tools (Swift 5.9+).

```sh
make app        # build dist/LLM Translator.app
make run        # build + open
make dmg        # build dist/LLM-Translator.dmg (drag-to-Applications image)
make zip        # build dist/LLM-Translator.zip (signature-preserving archive)
make install    # copy the app to /Applications
```

Notes:

- The bundle is **ad-hoc signed** by default, which is why users see the
  Gatekeeper prompt on first launch. To ship without that prompt, sign with an
  Apple **Developer ID** certificate and notarize: set `CODESIGN_IDENTITY` for
  `scripts/package.sh` and add an `xcrun notarytool` step.
- macOS ties Accessibility permission to the code signature, so after each
  ad-hoc rebuild you may need to re-grant it (toggle the entry off/on).
- `Support/AppIcon.icns` is regenerated from `icon.png` whenever `icon.png`
  changes.
- `NSAllowsArbitraryLoads` is enabled so plain-`http` local endpoints (Ollama,
  LM Studio, LAN machines) work.
- Launch-at-login uses `SMAppService` and only works from the packaged `.app`.
