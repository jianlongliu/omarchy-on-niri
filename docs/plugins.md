# Omarchy 插件层：现状与运维（主账户 jianlongliu）

> 核于 2026-09-20。姊妹文档 `omarchy-on-niri.md` 讲这套壳层怎么随 niri 移植，以及
> §8.11 / §8.17 那些**对插件源码的本地魔改**。
>
> **分工**：
> - **本文**：第三方 / 自研插件的**现状与日常运维** —— 装了哪些、怎么配、怎么验、怎么更新、踩过什么坑；
> - **魔改与正本**：改插件源码产生的 patch 存档在 `~/.config/omarchy/niri-port/plugin-patches/`，
>   自研插件（split-lock）的源码正本在 `~/omarchy-on-niri` 仓库。

## 1. 一页速查

本机在 `~/.config/omarchy/plugins/` 下有 7 个插件（其余 38 个都是第一方，在 `$OMARCHY_PATH/shell/plugins/`，
`$OMARCHY_PATH=~/.local/share/omarchy`）：

| 插件 id | 版本 | kind | 上游 | 干什么 | 本地改动 |
|---|---|---|---|---|---|
| `charlieras262.floating-bar` | 1.6.0 | bar | Charlieras262/omarchy-floating-bar | 浮空圆角 bar 本体（顶替 `omarchy.bar`） | 有 · §5.4 |
| `meviusisback.ai-subs` | 1.4.2 | bar-widget | meviusisback/omarchy-ai-subs | 各家 AI 订阅的用量 / 余额 | 有 · §5.1 |
| `ronald.input-sources` | 0.1.0 | bar-widget | ronaldlangeveld/omarchy-input-sources | fcitx5 输入源徽章 + 菜单 | 有 · §5.2 |
| `jrmmhm.pocket` | 0.4.1 | bar-widget | jrmmhm/omarchy-pocket | 把不常用的 bar 部件收进抽屉 | 无 |
| `yvonne.arch-logo` | 1.0.0 | bar-widget | 自研（无 git） | Arch logo + 菜单 | 自研 · §5.5 |
| `yvonne.workspaces` | 1.0.0 | bar-widget | 自研（clone of `omarchy.workspaces`） | 胶囊工作区 | 自研 · §5.5 |
| `yvonne.split-lock` | 0.1.0 | service | 自研（clone of `omarchy.lock`） | 分屏锁屏 | 自研 · §5.5 |

当前 bar 布局（`~/.config/omarchy/shell.json` → `bar.layout`）：

- 左：`yvonne.arch-logo` · `yvonne.workspaces` · `meviusisback.ai-subs`（Data 模式，默认显示 Command Code）
- 中：`omarchy.indicators` · `omarchy.clock` · `omarchy.weather` · `omarchy.system-update`
- 右：`omarchy.tray`（hidden: `Fcitx`）· `jrmmhm.pocket` · `ronald.input-sources` · `omarchy.agents` ·
  `omarchy.bluetooth` · `omarchy.network` · `omarchy.audio` · `omarchy.monitor` · `omarchy.power`

## 2. 插件层怎么运转

- **三个存放位置**：第一方 → `$OMARCHY_PATH/shell/plugins/<name>/`；第三方 / 自研 →
  `~/.config/omarchy/plugins/<author>.<name>/`。同 id 时用户目录优先。
- **`manifest.json`** 决定一切：`id`（必须是 `<author>.<name>`）、`kinds`（`bar` / `bar-widget` /
  `service` / `panel` / `overlay` / `menu`）、`entryPoints`、`activation`；
  bar 部件还要有 `barWidget`（`displayName` / `category` / `defaults` / `schema` —— `schema` 就是面板里
  那几行设置 UI）。`omarchy plugin validate <dir>` 复刻了壳层 `PluginRegistry.qml` 的校验。
- **`omarchy:` 兼容字段**：`clonedFrom` 标出它是从哪个第一方插件 clone 来的（`yvonne.workspaces` ←
  `omarchy.workspaces`，`yvonne.split-lock` ← `omarchy.lock`，`charlieras262.floating-bar` ← `omarchy.bar`）。
- **启用状态写在 `~/.config/omarchy/shell.json`**：
  - bar 部件：**在 `bar.layout.{left,center,right}[]` 里出现就是启用**（关掉 = 从数组里删掉）；
  - 非 bar 插件（service / panel …）：**默认启用**，关掉才写进顶层 `disabledPlugins[]`
    （本机 `omarchy.lock` 在那里，因为锁屏换成了 clone `yvonne.split-lock`）；显式列进顶层
    `plugins[]` 的是必须常驻的（本机 `yvonne.split-lock`）；
  - `cloneSourceRestores[]`：**禁用这个 clone 时，把它的上游源插件恢复启用**
    （本机 `yvonne.split-lock` → 关掉它，`omarchy.lock` 自动回来）。
- **部件的设置是平铺在该 bar 条目里的**（没有单独的设置文件）：

  ```json
  { "id": "meviusisback.ai-subs", "barDisplay": "Data", "defaultSub": "commandcode", "refreshIntervalSec": 900 }
  ```

  改这里是「跟着 shell.json 热重载」的；改**插件代码**不是（见 §4 的坑）。

## 3. CLI 速查

| 命令 | 作用 | 备注 |
|---|---|---|
| `omarchy plugin list` | 列已装插件 + `STATE` / `SOURCE` / `KINDS` | 本机 45 条（含第一方） |
| `omarchy plugin catalog` | 全部已知插件（含 `manifestPath` / `entryPoints`）JSON | 给脚本用 |
| `omarchy plugin add <git-url> [--enable] [--yes]` | 从 git 装第三方插件 | 交互式问确认；`--enable` 会顺带问放哪个 section |
| `omarchy plugin clone <source-id> [--edit]` | 把第一方插件复制成用户插件（写 `clonedFrom`） | 自研三件就是这么来的 |
| `omarchy plugin enable <id> [placement]` / `disable <id>` | 开关 | 实走 `omarchy-shell shell setPluginEnabled`，改 shell.json |
| `omarchy plugin update [id] [--yes]` | `git fetch` → `merge --ff-only` → `validate` | **工作树脏就拒绝**，见 §6 |
| `omarchy plugin remove [id] [--yes]` | 卸载 | |
| `omarchy plugin validate <dir>` | 校验 manifest / 入口文件 | 更新后也会自动跑 |

## 4. 验证与调试

```sh
# 每个 bar 部件的 x / width / visible（最可靠，别靠肉眼猜）
export OMARCHY_PATH=~/.local/share/omarchy
omarchy-shell shell debugBarGeometry | jq -r '.[] | "\(.id)\t\(.visible)\t\(.width)"'

# 截图（niri 单屏 eDP-1，2560x1600；bar 条带取 y≈8..48）
grim -o eDP-1 -t png /tmp/bar.png

# 壳层日志（systemd-cat 打进去了）
journalctl -t omarchy-shell --since "-10min" | tail -50
```

`visible:false` 的**正常**情形：`omarchy.system-update`（没有更新）、`omarchy.indicators`（没有指示）、
`omarchy.agents`（用量全 0）、`omarchy.tray`（托盘项全被隐藏时整体不显示）。

## 5. 逐插件

### 5.1 `meviusisback.ai-subs` —— bar 上的 AI 订阅用量

- **干什么**：bar 上一行显示「默认订阅」的窗口用量或余额；点开面板看全部 13 家。
  带窗口的后端（OpenCode、Command Code…）画进度条 + 重置倒计时（`5h 3% ▮ (1h) · W 21% ▮ (1d) · M 11% ▮ (24d)`），
  余额型（DeepSeek、Kimi…）只显示金额。
- **取数**：bar 部件每次刷新都跑
  `python3 <插件目录>/fetch_usage.py --env ~/.hermes/.env`，13 家并发查完输出一段 JSON。
- **密钥来源**：`~/.hermes/.env`（`hermesEnvFile` 设置）。插件按「Hermes 配置目录」设计，
  本机没装 Hermes，**只把它当凭据文件目录用**。
- **支持的后端与键名**（⚠ 键名要和表里**完全一致**）：

  | sub | 徽标 | 取数方式 | 需要的键 |
  |---|---|---|---|
  | `opencode` | OC | API | `OPENCODE_GO_API_KEY` / `OPENCODE_ZEN_API_KEY` |
  | `openrouter` | OR | API | `OPENROUTER_API_KEY` |
  | `claude` | CL | **读本机用量记录**（无 key） | — |
  | `codex` | CX | **读本机用量记录**（无 key） | — |
  | `deepseek` | DS | API | `DEEPSEEK_API_KEY`（或 `~/.deepseek/config.toml`） |
  | `kimi` | KI | API | `KIMI_API_KEY` / `MOONSHOT_API_KEY`（或 `~/.kimi-code/config.toml`） |
  | `novita` | NV | API | `NOVITA_API_KEY` |
  | `zai` | Z | API | `ZAI_API_KEY` / `GLM_API_KEY` |
  | `alibaba` | AB | API | `DASHSCOPE_API_KEY` |
  | `arcee` | AR | API | `ARCEE_API_KEY` |
  | `commandcode` | CC | API | **`COMMANDCODE_API_KEY`** |
  | `copilot` | CP | OAuth 凭据（read-use-discard） | 本机 GitHub 凭据 |
  | `cursor` | CU | OAuth 凭据（read-use-discard） | 本机 Cursor 凭据 |

- **`~/.hermes/.env` 的硬约束**（不满足就整份被拒，日志里只有一行 stderr，界面表现是全部 `no-key`）：
  必须是**普通文件、单链接、非符号链接**、**没有组/其他用户权限位**（本机 0600）、
  且落在 `~/.hermes`（或 `$HERMES_HOME`，且它得在家目录里面）之内。报错文本：
  `hermes-usage: refusing credential file <path>: <原因>`。
- **本机配置与实测（2026-09-20）**：`~/.hermes/.env`（0700 目录 / 0600 文件）里有
  `COMMANDCODE_API_KEY`（Command Code **GOAT** 套餐）+ `DEEPSEEK_API_KEY`（DeepSeek 官方）。
  实测输出：CC = `5h 3% · W 21% · M 11% · 剩 $62.x`（月额度按 GOAT $70 算），DS = `48.08 CNY`。
- **面板设置（4 个）**：`refreshIntervalSec`（默认 900，30–3600）、`hermesEnvFile`（默认 `~/.hermes/.env`）、
  `barDisplay`（`Icon` / `Data`）、`defaultSub`（默认 `opencode`）。
  Data 模式下若 `defaultSub` 没配或没 key，会**回落到第一个已配置的订阅**（按插件内置顺序，
  `deepseek` 比 `commandcode` 靠前，所以本机显式写了 `defaultSub: "commandcode"`）。
- **排障**：

  | 现象 | 含义 | 处置 |
  |---|---|---|
  | 面板提示 `No Hermes provider keys configured` | `.env` 不存在 / 被拒 | 看 shell 日志里那行 `refusing credential file …` |
  | 某家 `no-key` | 键名不匹配或没配 | 对照上表；CC 是 `COMMANDCODE_API_KEY`，**不是** `COMMAND_CODE_API_KEY` |
  | `no-usage-data`（claude / codex） | 本机没有该 agent 的用量记录 | 正常，用过了才有 |
  | `no-token`（cursor） | 没登录 / 没凭据 | 正常 |
  | `http-401/403` | key 无效 | 换 key |
  | `network-error` | 网络 / 代理 | 本机走 mihomo，见 `mihomo-migration` |
  | `unexpected-response` | 上游改接口了 | 升级插件或等等 |

  一行验数命令：

  ```sh
  cd ~/.config/omarchy/plugins/meviusisback.ai-subs
  python3 fetch_usage.py | jq -r '.providers[] | "\(.id)\t\(.configured)\t\(.error // "")\t\(.label // "")"'
  ```

- **本地魔改**（两批，同一份 patch 存档）：
  1. Data 模式左内距 + 组间距（「太挤了」）——`leadingPad = Style.space(8)`（对齐第一方部件
     的 8px 惯例）、窗口组间距 6→10、组内（`5h` / `%` / 进度条 / `(1h)`）4→6。实测宽度 321px → 359px。
  2. **bar 字号提档（2026-09-20，「有的字大有的小」）**：部件内 bar 文字原来硬写 `Style.font.caption`(10)，
     比 bar 上其它数字小一档多（实测字形高 14–17 物理 px，右侧电量 19–20）。先试了 13（`Style.bar.iconFont`）
     —— **用户嫌太大**，最终定在 **12（`Style.font.body`，＝纯文本档，同托盘标题 / input-sources 徽章）**。
     共 **5 处**，全在 `dataButton` 里——窗口组的 `·` / 窗口标签 / 百分比 / 重置倒计时 + 回落单标签 `chipLabel`；
     **弹窗面板里的字号一处没动**（那是面板自己的尺度，如面板内 `Text { text: chip.label }` 仍是 `caption`）。
     实测：字形高 14–17 → **17–18**；部件右缘 939 → 1005 物理 px（13 档是 1038），
     与中间组（时钟前沿 x=1193）留 188 物理 px ≈ 94 逻辑 px 间隙 → 宽松。
     再往下就是 `bodySmall`(11)（字高 ≈16）和原来的 `caption`(10)（字高 ≈14–15，即用户嫌小的那档），别不打招呼就退回去。
  3. **顺手把全 bar 统一到 12（同日，用户「能不能打补丁似的一样大」）**：光把本部件调到 12 还不够 ——
     内置部件的数字仍是 13 档（`Style.bar.iconFont`）。做法是 `~/.config/omarchy/shell.toml` 写 `[bar] icon-font = 12`，
     但**上游 `Style.qml` 的 `[bar]` 分支只认 `size-horizontal`/`size-vertical`/`scale-with-font`、会静默丢弃
     `icon-font`** → 先把 `shell/Commons/Style.qml` 的白名单补全（进 `niri.patch`，症状与踩坑见主文档 §8 第 31 条）。
     生效后同图实测：内置数字/图标 19–20 / 21–24 → **17–19 / 19–22**，与时钟（18–19）、本部件（17–18）同档。
     **回退 = 删 shell.toml 里那行**（bar 回 13 档；插件这 5 处不受影响）。
  patch 存档 `~/.config/omarchy/niri-port/plugin-patches/meviusisback.ai-subs.patch`
  （`cd ~/.config/omarchy/plugins/meviusisback.ai-subs && git diff > <该路径>` 生成；
  `git apply --reverse --check` 通过 = 与工作树一致；当前 9 hunk / 1 文件，含上面三批）。
- **运维两条（都是「看着像坏了其实没坏」）**：
  ① **`barDisplay` 会被面板底部那个 `Icon` / `Data` 开关写回 `shell.json`** —— 被切成 `Icon` 时 bar 上只剩一个图标、
     **没有用量数字**（本机 2026-09-20 就被切走过一次，已按文档恢复 `Data`，快照 `shell.json.bak-20260920-bardisplay`）；
     排查"数字不见了"先看 `shell.json` 里这个键，别急着怀疑插件。
  ② **每次重启壳层后 bar 上最多空 15 分钟**才出数字：取数 `Timer` 的 `interval = refreshIntervalSec`(900s) 且
     `running: true`，而 QML 定时器**不会**立刻触发一次。要立刻取数：
     `qs -p ~/.local/share/omarchy/shell ipc call meviusisback.ai-subs refresh`（`open` / `close` / `toggle` 同理；
     不带 `-p` 会报 `Could not find default config directory` —— 这套壳层的配置不在 `~/.config/quickshell/`）。
     调完字号/重启壳层后想马上看效果，就走这条。
- **bar 字号分层**（判「有的字大有的小」照这张表，都从 `[font] base-size` 派生，改字号全bar 一起走）：

  | token | 逻辑 px | 谁在用 | 实测墨高（物理 px @scale 2） |
  |---|---|---|---|
  | `Style.bar.iconFont` | **12**（本机 `[bar] icon-font = 12` 覆盖；上游默认 13） | 内置部件的图标**和数字**（时钟、电量 %、网速、蓝牙…） | 数字 17–19 / 图标 19–22 |
  | `Style.font.body` | 12 | 纯文本：托盘标题、input-sources 徽章、`WidgetButton`（时钟那格） | 17–18 |
  | `Style.font.bodySmall` | 11 | 托盘次级标签 | 16 |
  | `Style.font.caption` | 10 | 插件自定义内容（本部件改前的状态） | 14–15 |

  ⚠ **同档≠同高**：电池的 `%` 与时钟的数字现在都是 12 档，但一个走 `BarIconButton`（图标字体面）、一个走
  `WidgetButton`（UI 字体面），墨高会差 1–2 物理 px —— 别用高度差反推档位（我据此把时钟误判成 13 档过一次）。

  图标比同级数字高一截是 **Nerd Font 的光学对齐，不是错**。测法=**墨高指纹**：`grim` 截 bar 条 →
  逐列减背景取墨 → 按块量字高；`tesseract` 也能读（左组原本字号太小，OCR 一个字都认不出来，提档后能认出）。
- **回退**：`git -C ~/.config/omarchy/plugins/meviusisback.ai-subs checkout -- Panel.qml` + `omarchy-restart-shell`。
  备份：`Panel.qml.bak-20260920-fontsize`、旧 patch `…ai-subs.patch.bak-20260920-fontsize`（都在原地）。

### 5.2 `ronald.input-sources` —— 输入源徽章

- **依赖**：fcitx5（DBus `org.fcitx.Fcitx5`），后端是 fcitx5；`A` = 拉丁布局，`拼` / `あ` / `한` = 引擎。
  可见条件是 `fcitxAvailable && ims.length > 1`——**只有一个输入源时它不显示**。
- **本地魔改**：`Model.js` 的 `badgeOverrides`（rime 显示「拼」而不是 fcitx 的「ㄓ」）+
  `Panel.qml` 的 `startupSource`（默认 `"rime"`，开机/起壳层后把源回到 rime，防 fcitx5 重启后掉回
  `keyboard-us`）。patch：`plugin-patches/ronald.input-sources.patch`；
  细节与两条走不通的路见 `omarchy-on-niri.md` §8.17。
- **本机 shell.json 条目**：`{ "id": "ronald.input-sources", "showSourceName": false }`（只留徽章，不显示源名）。

### 5.3 `jrmmhm.pocket` —— bar 抽屉

- **干什么**：把不常用的 bar 部件收进一个标记后面，指针过去滑出。
- **配置**：`members`（string 逗号表或 JSON 数组，默认 `""`）= 被收进去的部件 id。
  本机**没配 members**（空抽屉，只留标记）；要收的话在 shell.json 那个条目里写，例如
  `{ "id": "jrmmhm.pocket", "members": ["omarchy.tailscale"] }`。
  注意：成员必须和 pocket 在**同一个 section**，且 pocket 要放在成员的**外侧**。
- 无本地改动。

### 5.4 `charlieras262.floating-bar` —— bar 本体

- 它顶替第一方 `omarchy.bar`，bar 本体设置就在 `shell.json.bar` 里，本机实际写了：
  `id: charlieras262.floating-bar`、`cornerRadius: 10`、`floatGap: 8`、
  `centerAnchor: omarchy.clock`、`layout`（§1 那张布局表）。
  `position` / `transparent` 等键没写，走插件默认（双击 bar 空白处会切换透明，那是运行时状态）。
- **本地魔改**：圆角 + `blurRegion`（毛玻璃跟着圆角走），patch 存档
  `plugin-patches/charlieras262.floating-bar.patch`；五处缺一不可的 blur 全栈见 `omarchy-on-niri.md`。
- 它对 `hyprctl -j getoption general:gaps_out` 有依赖（在 niri 上由 `~/bin/hyprctl` 垫片兜住），
  `floatGap` 显式写在 shell.json 里所以不靠它。

### 5.5 自研三件（`yvonne.*`）

| 插件 | 源码 | 说明 |
|---|---|---|
| `yvonne.arch-logo` | 只在 `~/.config/omarchy/plugins/`（无 git、仓库里没有） | Arch logo 按钮 + 菜单 |
| `yvonne.workspaces` | 同上 | 胶囊工作区（`clonedFrom: omarchy.workspaces`），第一方 `omarchy.workspaces` 已停用；**点数动态**（§5.5 末） |
| `yvonne.split-lock` | 正本在 `~/omarchy-on-niri/split-lock/`（含 `install.sh`、测试、`face-pam.sh`） | 分屏锁屏，`clonedFrom: omarchy.lock`；在 `shell.json` 的 `plugins[]` 里常驻 |

三者都**没有 `.git`**，所以 `omarchy plugin update` 不会碰它们（更新只收有 `.git` 的目录）。
⚠ 后两个的源码改动要**同时**同步到 `~/.config/omarchy/plugins/` 那份才生效（install.sh 负责拷贝）。
锁屏相关的两个结构性缺口（howdy 没进 `omarchy-lock-password`、`faceConfigured` 写死 false）见
`omarchy-on-niri.md`。

**`yvonne.workspaces` 点数改动态（2026-09-20，用户要的「1+1 → 有 app 就三个」）**

- 旧行为：`workspaceIds()` 写死 `[1, 2, 3, 4, 5]` + 补 6–10 的实际 id，**永远 5 个点**。
- 新行为：显示 `1..N`，`N = 最靠右的「有窗口 **或** 正在聚焦」的工作区 + 1`，**最少 2 个、封顶 10**。
  - 空桌面（只有 ws1）→ 「胶囊 + 1 个空点」＝用户说的「1+1」；
  - 第二个工作区一有 app（或只是聚焦过去）→ 三个点（1、2 + 预留的空位 3）。
- ⚠ 关键是**按「占用」算、不按「工作区是否存在」算**：niri 会长期留着空工作区（实测去 ws2 转一圈回来，
  空 ws3 还挂在 `niri msg workspaces` 里），胶囊照样只画 2 个点 —— 否则一逛工作区就永远回不去 2 个点。
- 聚焦空工作区时也把它算进 `N`（`w.focused` 那半边），不然跳过去的瞬间胶囊会把自己藏掉。
- 改法：`~/.config/omarchy/plugins/yvonne.workspaces/Workspaces.qml` 的 `workspaceIds()`；
  备份 `Workspaces.qml.bak-20260920-capsuledots`（原地），patch 存档
  `plugin-patches/yvonne.workspaces.patch`（**该目录没有 git**，用 `diff -u --label a/… --label b/…` 生成，
  `git apply --reverse --check` 通过 = 与工作树一致）。它**不进 `omarchy plugin update` 那条流程**（§6 只管有 `.git` 的）。
- 生效/验收：QML 不热更 → `omarchy-restart-shell`；`debugBarGeometry` 里 `yvonne.workspaces` 宽度
  只有 ws1 时 **~104 → 52**；肉眼数点子用 `grim -g "0,0 200x40" /tmp/bar.png`。
- 回退：`cp Workspaces.qml.bak-20260920-capsuledots Workspaces.qml && omarchy-restart-shell`。

## 6. 更新与本地改动（重要）

`omarchy plugin update [id] [--yes]` 干这三件事：

1. `git fetch origin HEAD`；
2. **`git merge --ff-only FETCH_HEAD`** —— 工作树有本地改动（我们的 patch）时**直接失败**并打印
   `cannot fast-forward '<id>'; you have local changes in <dir>`；
3. `omarchy-plugin-validate` 不过则 `git reset --hard ORIG_HEAD` 回滚。

本机有本地 patch 的三个插件：`charlieras262.floating-bar`、`meviusisback.ai-subs`、
`ronald.input-sources`。**更新配方**：

```sh
cd ~/.config/omarchy/plugins/<id>
git checkout -- .                                   # 丢掉本地魔改（patch 已存档，不用担心）
omarchy plugin update <id> --yes                    # 或交互式跑，看清 diff 再确认
git apply ~/.config/omarchy/niri-port/plugin-patches/<id>.patch   # 冲突时用 -3 或手改
omarchy-restart-shell                               # QML 不热更，必须重启壳层
```

⚠ **这些 patch 没有自动重放器**：`~/bin/omarchy-niri-repatch` 只管 omarchy overlay
（`$OVL/niri.patch` + `$OVL/Niri.qml` + `$OVL/plugins/*` 整插件拷贝）。store 装来的插件被更新覆盖后，
要照上面手工 `git apply`。

## 7. 坑清单

- **键名陷阱**：ai-subs 要 `COMMANDCODE_API_KEY`；Ante 自己用的是 `COMMAND_CODE_API_KEY`
  （存在 `~/.ante/auth/api_keys.json`）。两边**不是同一个名字**，别互抄。
- **`.env` 被静默拒绝**：软链接 / 0644 / 多硬链接 / 不在 `~/.hermes` 内 → 插件全 `no-key`，
  只有 stderr 一行提示。
- **改插件 QML 不会热更到 bar**：shell 日志会打 `Local plugin changed, reloading: <id>`，但那只是重扫元数据，
  运行中的部件的实例**不重建**；会话锁屏时更是完全冻结（实测：把 padding 改成 60px、甚至整个还原成上游，
  `debugBarGeometry` 的宽度纹丝不动）。**唯一可靠方式：`omarchy-restart-shell`**。
- **锁屏时不要重启壳层**：`omarchy-restart-shell` 自己会先问锁服务（`lock status` 报 secure/requested
  就 `exit 1`），别绕过它——杀掉锁客户端会把人挡在桌面外。
- **`plugin update` 失败 ≠ 坏了**：带 patch 的插件必然 ff 失败，先按 §6 清理。
- **bar layout 里别重复写同一个 id**；`omarchy.tray` 即使当前没内容也别删（托盘项以后会再长出来）。
- 排查 bar 渲染前先 `niri msg layers` 确认存在 namespace `omarchy-bar`（niri 的 blur 规则按它匹配）；
  聚焦环只在有焦点时绘制，锁屏后的截图里没有环是正常的。

## 8. 相关文件

| 路径 | 说明 |
|---|---|
| `~/.config/omarchy/plugins/` | 第三方 / 自研插件 |
| `~/.config/omarchy/shell.json` | 插件开关 + bar 布局 + 内联设置 |
| `~/.config/omarchy/niri-port/plugin-patches/` | 第三方插件的本地魔改存档 |
| `~/omarchy-on-niri/split-lock/` | `yvonne.split-lock` 源码正本 |
| `~/omarchy-on-niri/docs/plugins.md` | 本文档的仓库镜像（与 `~/Documents/omarchy-niri-plugins.md` 逐字节一致） |
| `~/Documents/omarchy-on-niri.md` | 移植正本（§8.11 bar 插件层 / §8.17 输入源 / blur 全栈） |
| `$OMARCHY_PATH/shell/services/PluginRegistry.qml` | 壳层实际执行的插件注册与启用规则 |
| `$OMARCHY_PATH/bin/omarchy-plugin-*` | §3 那些 CLI 的实现 |
