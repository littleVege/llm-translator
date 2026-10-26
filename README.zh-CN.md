# LLM Translator

[English](README.md) · **简体中文**

一款小巧的原生 macOS 菜单栏翻译工具，可接入任意大语言模型（LLM）。没有 Electron、
没有 Dock 图标——启动即用，安静地待在菜单栏里。

- **选中任意文字 → 按 ⌥T（Option+T）**——会在鼠标位置弹出一个浮窗，翻译结果通过
  SSE 实时流式显示，首个片段到达后立即可读，无需等待长内容全部生成。当前所在的应用
  不会失去焦点。
- **左键单击菜单栏图标**——打开一个类似聚焦搜索（Spotlight）的输入条；输入或粘贴
  文字，按回车翻译，按 Esc 关闭。
- **右键单击菜单栏图标**——弹出菜单：翻译选中内容、翻译剪贴板、打开翻译条、设置、退出。
- **自动识别语言**——完全在本机完成。如果检测到文字已经是你的目标语言，会改为翻译成
  你设置的 **备用目标语言**（例如：目标语言为中文时，英文 → 中文，而中文 → 英文）。
- **自带模型，随意接入**——可选择服务商（Anthropic、OpenAI、Google Gemini、
  DeepSeek、Mistral、OpenRouter、Ollama、LM Studio，或自定义地址）并填入 API 密钥。
  任何兼容 OpenAI 的 `/chat/completions` 接口都能用。
- 翻译指令（系统提示词）和默认语言都可以在设置里修改。
- **Markdown 结果**——标题、粗体、列表、引用、代码块和表格都会格式化显示；复制保留原始 Markdown。
- **多个结果置顶**——点击图钉，把结果固定为独立浮窗；可以同时保留多个结果并继续翻译。

---

## 安装

需要 **macOS 14（Sonoma）或更高版本**。

1. **打开 `LLM-Translator.dmg`**（双击）。

2. **把 `LLM Translator.app` 拖到窗口里的 `Applications` 文件夹上。**

3. **首次打开需要手动放行一次。** 因为这个 App 没有经过 Apple 公证（notarize），
   macOS 首次会拦截。用下面任意一种方式放行一次即可：

   **终端方式（最快）**——打开「终端」App，粘贴这行命令并回车：

   ```sh
   xattr -dr com.apple.quarantine "/Applications/LLM Translator.app"
   ```

   之后就可以像普通 App 一样从「应用程序」里打开 **LLM Translator** 了。

   **不想用终端？** 先双击 App，在弹出的警告上点 **完成（Done）**，然后打开
   **系统设置 → 隐私与安全性**，滑到最底部，点 **仍要打开（Open Anyway）**，
   再用触控 ID 或密码确认。（在 macOS 15 Sequoia 上，旧版「右键 → 打开」已不再有效，
   请使用这个按钮。）

打开后，菜单栏右上角会出现图标（一个「A/文」对话气泡）。App 没有 Dock 图标，这是刻意
设计的。

---

## 设置 API 密钥

**设置** 窗口会在首次启动时自动弹出（之后随时可以右键单击菜单栏图标 → **设置…** 再次打开）。

1. **从下拉菜单选择服务商（Provider）**——基础地址（Base URL）会自动填好。
2. **选择模型（Model）**——从下拉菜单里选，或选 **Other…** 手动输入。
3. **粘贴你的 API 密钥**——填入 API Key 一栏（⌘V 可用）。密钥保存在 macOS
   **钥匙串（Keychain）** 中，不会以明文形式存到文件里。

各服务商密钥获取地址：

| 服务商         | 获取密钥的地址                        | 备注                                |
|----------------|---------------------------------------|-------------------------------------|
| Anthropic      | console.anthropic.com                 | `claude-haiku-4-5` 又快又便宜        |
| OpenAI         | platform.openai.com/api-keys          |                                     |
| Google Gemini  | aistudio.google.com/apikey            |                                     |
| DeepSeek       | platform.deepseek.com                 |                                     |
| Mistral        | console.mistral.ai                    |                                     |
| OpenRouter     | openrouter.ai/keys                    | 一个密钥，多种模型                   |
| Ollama         | —                                     | 本地运行；API 密钥留空即可           |
| LM Studio      | —                                     | 本地运行；API 密钥留空即可           |

**用本地模型？** 选 **Ollama (local)** 或 **LM Studio (local)**，填入你已加载的
模型名称，API 密钥留空。记得先把本地服务跑起来。

**用其他服务？** 选 **Custom…**，填入任意兼容 OpenAI 的基础地址（App 会请求
`{基础地址}/chat/completions`）。

---

## 使用方法

**翻译选中的文字（⌥T）。** 在任意 App 里选中文字，按 **⌥T**（Option+T），鼠标位置会
弹出浮窗显示翻译结果。点复制图标可复制；按 **Esc**、点 ✕、或点浮窗以外的地方即可关闭。

**翻译条。** 左键单击菜单栏图标，打开浮动输入条。输入或粘贴文字，选择源语言/目标语言
（或用 ↔ 一键互换），按 **回车**。结果会在下方通过 SSE 逐步显示；长内容生成时视图会
自动跟随最新结果，仍可随时复制已收到的部分。

**翻译剪贴板。** 右键单击菜单栏图标 → **Translate Clipboard**——在那些屏蔽 ⌘T
复制的 App 里很好用。

**Markdown。** 划词浮窗和翻译条都会自动渲染 Markdown，包括标题、粗体、斜体、列表、
引用、链接、代码块和表格。代码块和宽表格可横向滚动。原文换行会保留，复制按钮复制的
仍是模型返回的完整 Markdown 源码。

**固定多个结果。** 点击结果旁的图钉即可置顶，生成过程中也可以固定。翻译条的结果会
移到独立浮窗并继续生成；新的翻译不会覆盖已固定的结果。每个浮窗都可以拖动，切换应用、
点击外部或按 Esc 不会关闭它。再次点击图钉可取消固定，恢复普通浮窗的关闭方式；点击 ✕
只关闭当前结果。固定结果仅在本次运行中保留，退出应用后不会恢复。

---

## 设置项说明

- **语言（Languages）**——设置默认的 *源语言*（或 **Auto Detect** 自动识别）和
  *目标语言*。当自动识别发现文字已经是目标语言时，会用到 **备用目标语言
  （Alternate target）**。
- **快捷键（Shortcut）**——默认是 **⌥T（Option+T）**，不会和常见应用的快捷键冲突
  （它只占用了输入生僻符号 `†` 的组合）。也可以改成：⌘T（注意会覆盖浏览器的
  「新建标签页」）、⌃T（终端里是 fzf / 字符调换）、⇧⌘T（浏览器的「重新打开关闭的
  标签页」）或 ⌥⌘T。
- **指令（Instruction）**——发送给模型的系统提示词。用 `{from}` 和 `{to}` 作为
  语言名称的占位符。点「Reset to Default」可恢复默认。
- **开机启动（Launch at login）**——登录时自动启动 App。

---

## 权限

第一次按 ⌥T 时，macOS 会请求 **辅助功能（Accessibility）** 权限——App 需要它来读取
你在其他应用里选中的文字。请在 **系统设置 → 隐私与安全性 → 辅助功能** 里授权，然后
再次按 ⌥T。

**开关已开启，更新后仍提示没有权限？** 临时签名（ad-hoc）版本的授权可能仍绑定旧版
应用的签名。先退出 LLM Translator，在辅助功能列表选中它并点 **−** 移除，然后点
**+** 添加 `/Applications/LLM Translator.app`，开启开关，再重新打开应用。权限提示里
的 **Show This App in Finder** 可以定位实际运行的副本；**Check Again** 会重新检查
当前权限。应用每次启动最多主动请求一次系统授权弹窗。也可以先手动复制文字，使用
**Translate Clipboard**，这个入口不需要辅助功能权限。

---

## 常见问题

- **提示「文件已损坏 / 无法打开」。** 隔离标记没有清除——执行「安装」一节里的
  `xattr -dr com.apple.quarantine …` 命令即可。
- **按 ⌥T 没反应。** 先授予辅助功能权限（见上）。如果你重新构建或重装过 App，
  请在辅助功能列表里把它的开关关掉再打开——macOS 会把授权绑定到具体的 App 构建版本。
- **提示「No text selected」（没有选中文字）。** 有些 App 不对外暴露选区。可以先复制
  文字，再用右键 → **Translate Clipboard**。
- **结果为空或浮窗报错。** 检查设置里的 API 密钥、基础地址和模型，并确认你的接口支持
  OpenAI 兼容的 SSE 流式返回（请求体中的 `stream: true`）。App 同时兼容服务端忽略
  流式参数后返回的普通 JSON，但这种情况只能在完整响应到达后显示。
- **快捷键和其他应用冲突。** 在设置里换一个——⌥T 是最不容易冲突的选择。

---

## 从源码构建（面向开发者）

纯 SwiftPM 项目——没有 `.xcodeproj`。需要 Xcode 或命令行工具（Command Line Tools，
Swift 5.9+）。

```sh
make app        # 构建 dist/LLM Translator.app
make run        # 构建并打开
make dmg        # 构建 dist/LLM-Translator.dmg（拖拽到 Applications 的磁盘映像）
make zip        # 构建 dist/LLM-Translator.zip（保留代码签名的压缩包）
make install    # 把 App 复制到 /Applications
```

说明：

- 默认使用 **ad-hoc 签名（临时签名）**，这也是用户首次打开会看到 Gatekeeper 拦截的
  原因。若想让用户打开时完全没有提示，需要用 Apple 的 **Developer ID** 证书签名并
  公证：为 `scripts/package.sh` 设置 `CODESIGN_IDENTITY`，并增加一步 `xcrun notarytool`。
- macOS 会把辅助功能权限绑定到代码签名，所以每次 ad-hoc 重新构建后，可能需要重新授权
  （把列表里的开关关掉再打开）。
- 只要 `icon.png` 有变动，`Support/AppIcon.icns` 会自动重新生成。
- 已开启 `NSAllowsArbitraryLoads`，以便使用明文 `http` 的本地接口（Ollama、
  LM Studio、局域网机器）也能正常工作。
- 开机启动使用 `SMAppService`，仅在打包后的 `.app` 中生效。
