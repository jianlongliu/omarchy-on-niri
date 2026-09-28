# 垫片 — Omarchy on niri 卷（shims）

> 文档只有一份：本文件（`docs/shims.md`）。
> 本卷 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽出（模块化拆分），**编号一律沿用原号** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，原处留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `docs/omarchy-on-niri-port.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 4. hyprctl 垫片（`~/bin/hyprctl`）
- 〔§4〕**窗口缝隙开关 `omarchy-hyprland-window-gaps-toggle`（2026-09-24 加）** —— 三处一起才生效（`port-bin` 垫片 + `hyprctl` 的 `getoption` 归零 + `layout.kdl` 尾部 `include optional=true`）；**壳层会跟着塌**（`Style.qml` 读同两个 `getoption` 值），实测菜单卡片圆角 12 → 直角；坑：壳层的 watch 只在启动时 `…/toggles/hypr/` 已存在才挂得上（`install.sh` 已补 `mkdir -p`）。⚠ **同日晚发现该 include 放在尾部可能整块无效**（niri 同名键取第一次定义）—— niri 侧那半**待重验**，见本节末
- 〔§4〕**内屏开关 / clamshell（2026-09-24 加）** —— `hyprctl` 的 `hl.monitor({ disabled })` 补上（写/删 `~/.config/niri/output-toggle-off.kdl`、validate、**读回核对**）+ `cmd_monitors` 的 `disabled/active` 改真实值 + 新垫片 `omarchy-hyprland-monitor-watch`（轮询盖子，开盖零 IPC）+ 用户单元 `omarchy-clamshell-watch.service`；**真屏实测关得掉也回得来（模式没掉 4K）**；⚠ 两条硬约束：**monitor.kdl 的 include 必须放首行**（同名键第一次定义才管用，尾部整块被忽略，已 A/B 实测）、**"不挂起"那半在 logind（root 改动，没动）**；本机无外屏 ⇒ "合盖+外屏"只有离线测试覆盖
- 〔§4〕**`hl.device` 触控板 / 触摸屏开关：在 niri 上曾"假成功"，2026-09-23 已补好**（垫片 + `include optional=true` 覆盖文件，用户拍板）；用户当日晚决定**功能留着但本人用不上**（TrackPoint 工作流）⇒ 菜单项不藏、Fn 键不绑（绑法与"那个键在 niri 上本是死的"都记在 §4）。同段落里另两项（workspace-layout / window-transparency）用户明确**不需要，别再补**
- 2. **`hyprctl` 垫片本轮修复**：`monitors` 输出补上 `activeWorkspace.id` 与 `transform`，并把
- 5. **hyprctl schema 精度**：个别 Hyprland-only 字段可能是占位值；如遇脚本异常再补映射。
- 7. **TUI 编辑器启动已修**：`omarchy-launch-tui` 原本走 `uwsm-app`+`xdg-terminal-exec`（Hyprland/uwsm
- 22. **应用启动类调用统一到一个 `uwsm-app` 垫片（2026-09-19 修）**：上游 Omarchy `bin/` 里有 ~30 处
- 34. **AUR 助手统一成 `yay` → paru 垫片（`~/bin/yay`，2026-09-22 修）**：上游的 AUR 调用全走 `yay`，本机只有 paru
- 〔§11〕**`omarchy-powerprofiles-{list,set}` 垫片：power-saver 档联动屏幕亮度（2026-09-24 加）** —— 本卷**不设专节**，语义与调法（三级优先 `环境变量 → …/powerprofiles/saver-brightness → 10`、智能恢复只在亮度仍等于压过的值时才回）见 `docs/behavior.md` 的「电池面板 POWER PROFILE 区为空」一条；同处也更正了「档位到底谁说了算」（壳层记忆 vs `TLP_PROFILE_AC/BAT`）
- 〔§23〕**`omarchy-launch-screensaver` 垫片：闲置「不插电到点锁屏」（2026-09-24 加）** —— 本卷**不设专节**。上游那份在终端跑 ASCII 屏保、且早被本机 `screensaver-off` 开关停掉；垫片接管它的那个时机（`idle.screensaver`，那天从 150 改成 300）：**不插电且非全屏**才 `omarchy-system-lock`（灭屏交给锁自己），插电 / 全屏 / 已锁一概不动——**不装 swayidle**。规格、四分支实测与回退见 `docs/behavior.md` 的 §8 第 23 条「screensaver 关掉并屏蔽」
- **通用剪贴板垫片 `omarchy-universal-clipboard` + `omarchy-sendkeys`（2026-09-27 加，`§8 第 42 条`）** —— niri 版 `Super+C/V/X`：niri 抓键，垫片按焦点窗口注入（终端 → `Ctrl+Insert`/`Shift+Insert`，其他 → `Ctrl+C/V`，剪切恒 `Ctrl+X`）。上游的 Hyprland `send_key_state` 在 niri 没有对应物 ⇒ 自造 uinput 注入原语（纯标准库、零安装）。⚠ 两条硬约束：**必须声明 1..248 全段键码**（否则 udev 只给 `ID_INPUT_KEY`、libinput 不当键盘）、**物理按住的 SUPER 会并进注入的和弦**（终端侧靠 ghostty 的 `super+ctrl+insert` 变体接住）；每次按键 ≈ 0.45 s（CPU 仅 36 ms）。终端里复制/剪切额外弹一次**壳层 OSD 卡片**（`omarchy-osd`，就是关机/重启那种卡片；**不用** ghostty 自带的 libnotify 通知，本机那条链路不显示）。见本卷「通用剪贴板垫片」

---

## 4. hyprctl 垫片（`~/bin/hyprctl`）

### 设计原则
- 纯 Python stdlib，无 jq / 无外部依赖。
- 目标是**让 Omarchy `bin/` 脚本能跑**，只覆盖实际用到的 hyprctl 子命令。
- 对 Hyprland-only 的特性（`hyprsunset`, `hl.config cursor`, `hl.device`,
  `hl.workspace_rule`, `setprop opaque`）降级为安全的无操作（no-op），避免脚本报错。
  （`hl.device` 这条 no-op **保持**——开关的实际实现不在 hyprctl 垫片里，而是**把上游那个脚本替掉**，
  见本节 §4「`hl.device` —— 触控板 / 触摸屏开关」；另两个 `hl.workspace_rule` / `setprop opaque`
  用户明确不要，别补。）
- **`hl.monitor` 译三样（2026-09-23 首修，2026-09-24 补齐 `disabled`）**：垫片有 `_eval_monitor()`
  分支，把 **`scale` / `position` / `disabled`** 翻译成 niri 侧动作；`mode` 故意跳过（niri 不认
  Omarchy 回传的 `WxH@Hz` 形式，且输出本来就在该模式上）。
  **`disabled`（2026-09-24 实现，不再是假成功）**：不写 `niri msg output <name> off`（那是一次性的运行时
  改动，上游脚本紧接着的 `hyprctl reload` 会把它忘掉，也没留下任何可持久的状态），而是写/删
  `~/.config/niri/output-toggle-off.kdl` 覆盖文件 —— 与 `hl.device` 同一套机制；写前 `niri validate`、
  写后**读回 `niri msg outputs` 核对**，不生效就往 stderr 报警（不再有"报了成功屏还亮着"）。
  规格、顺序规则（include 必须放**最前**，否则整块被忽略）与实测见本节「内屏开关 / clamshell」。
  `mirror` 仍无 niri 对等物（`niri msg output` 只有 off/on/mode/scale/transform/position/vrr，**没有 mirror**），
  用户已遗弃。

### 已映射的查询（可 `-j` 出 JSON，Hyprland schema）
- `clients`, `monitors`, `activewindow`, `activeworkspace`, `devices`, `binds`, `getoption`, `cursorpos`
- 辅助函数：`_window_to_client()`, `_addr_to_id()`, `cmd_monitors()`, `cmd_clients()`,
  `cmd_activewindow()`, `cmd_activeworkspace()`, `cmd_devices()`, `cmd_getoption()`。
- **`binds` 的实现**：`cmd_binds` 不读运行时，而是解析 niri 配置生成 Hyprland 格式 bind
  记录；经 `_niri_config_lines()` **递归展开 `include` 指令**后提取 `binds { }` 块——
  配置模块化拆分（§5.7）后仍能拿到全部键位。唯一消费者是键位菜单
  （`omarchy-menu-keybindings`），描述取 `hotkey-overlay-title`，arg 还原成可执行的
  shell 命令（spawn→命令本体，裸动作→`niri msg action X`）。

### 已映射的 dispatch/eval
- `exec` → niri 启动窗口；`hl.dsp.focus workspace/window` → 切换 workspace/窗口；
  `hl.dsp.dpms` → 关/开屏；`hl.dsp.window.close` → 关闭窗口；`fullscreen`。
- 其余 Hyprland-only dispatch 一律 no-op。

### `hl.device` —— 触控板 / 触摸屏开关（曾"假成功"，2026-09-23 已补）

**已实施（2026-09-23）**
- **产物**：`port-bin/omarchy-toggle-input-device`（装到 `~/bin/`，PATH 第一位，覆盖
  `$OMARCHY_PATH/bin` 里那个上游脚本）＋ `~/.config/niri/input.kdl` 末尾两行
  `include optional=true "input-toggle-touchpad.kdl"` / `…-touchscreen.kdl`（仓库副本
  `niri-config/local/input.kdl` 同步了同样两行，`kdl-sync.sh` 才不会判漂移）。
  改动前备份：`~/.local/state/backups/.config/niri/input.kdl.bak-20260923-inputtoggle`；
  回退一条命令 `cp` 回去即可。
- **行为**：`disable` = 写覆盖文件（`touchpad` → `input { touchpad { off } }`；
  `touchscreen` → `input { touch { off } }`），`enable` = 删该文件；写前先 `niri validate` 整份配置，
  不合法就删回来并报错退出；写/删之后显式 `niri msg action load-config-file`，最后发 `omarchy-osd`
  （OSD 失败不影响结果）。
- **验证（程序侧，全通过）**：`niri validate` 过（文件缺失时只有 `optional include not found` WARN）；
  `off` / `on` / `toggle` 三种调用都把文件状态改对；**走菜单那条真链路** `omarchy-toggle-touchpad off|on`
  也通；参数错误退出 1 并打 usage；收尾 `~/.config/niri/` 只剩 7 个正式配置、无残留。niri 日志每次改动后都有
  `DEBUG niri_config: loaded config from …` —— **新建与删除都会触发**，即文档承诺的"被 include 的文件会被 watch"
  实测成立（早先那次"新建后日志没动静"是 journald 时序假象，不是没 reload）。
- ⚠ **物理效果未由人验证**：`libinput` CLI 本机**没装**（`command not found`），而 `off` 是 libinput 层的静音
  （内核事件照旧在流），"触控板真的不动了"只能靠手指试。**用户 2026-09-23 晚表示用不上**（TrackPoint 工作流），
  所以这项**有意不追**——谁哪天想用，先按上面那条试一次再信。
  触摸屏那半同理（本机若无触摸屏，就只能确认文件与 reload 正确）。
- **与上游的差异（别混）**：上游按**设备名**开关（`hl.device({ name, enabled })`），niri 只能按**设备类型**关
  ⇒ 同类型的设备会一起被关；上游那套 `~/.local/state/omarchy/toggles/hypr/*-disabled-name` 持久化本垫片**完全不使用**，
  覆盖文件本身就是状态。
- **用户决定（2026-09-23 晚）**：功能**留着**（垫片与两行 `include` 都不回退，无副作用），但**本人目前用不上**——
  理由是 TrackPoint 工作流下触控板本来就不碍事。⇒ **菜单项不藏**（不加 `"when":"false"`）、**Fn 键也不绑**。
  真要时两个入口都现成：菜单 `Toggle ▸ Touchpad`（现在真生效），或绑键（见下）。
- **X1C 那个触控板键在这台机器上是死的（2026-09-23 实测，别再来回猜）**：`thinkpad_acpi` 报
  `hotkey_bios_enabled = 0`（BIOS 一个热键都没接管），该键以 `KEY_TOUCHPAD_TOGGLE (0x212)` 事件形式来自
  "ThinkPad Extra Buttons" 设备；**niri 不认这个键码**（二进制里无相关字样），`binds.kdl` 里也没绑
  ⇒ 在 niri 上按下去没有任何反应（GNOME/KDE 会自己吃掉这个键码，所以"ThinkPad 硬件自带"的印象在别的桌面成立）。
  要救活就是一行（`XF86TouchpadToggle` 已被 `niri validate` 接受）：
  `XF86TouchpadToggle { spawn-sh "omarchy-toggle-touchpad toggle"; }`
- **不想依赖开关、只想让触控板安静**：niri 的 `dwtp`（Input 页：disable-when-trackpointing）就是这个效果 ——
  本机 `input.kdl` 原先 **`dwt` 与 `dwtp` 都是注释掉的**（即"用 TrackPoint 自动禁用触控板"其实并不成立）；
  **2026-09-23 晚用户要求只开 `dwtp`，已开**（`dwt` 保持关着，他明确不需要）。本机 TrackPoint 设备存在：
  `TPPS/2 Elan TrackPoint`。

**（历史）现象（修复前，2026-09-23 核实）**：菜单 `trigger.hardware.touchpad`（守卫 `omarchy-hw-touchpad`）点下去，
脚本会调 `omarchy-osd` 报 "Touchpad disabled/enabled"，但**设备其实没被关**
⇒ 存在"提示说成功、实际没生效"的误导（OSD 在 niri 上是否真弹未单独验）。

链路（逐段读过）：
1. 菜单 → `omarchy-toggle-touchpad` / `omarchy-toggle-touchscreen`
   → `omarchy-toggle-input-device <kind>`（上游脚本，在 `~/.local/share/omarchy/bin/`）。
2. **生效那半**：`hyprctl eval "hl.device({ name = …, enabled = … })"`
   → 垫片**真 no-op**（`~/bin/hyprctl` 的 `cmd_eval` 兜底分支只认 `hl.dispatch` / `hl.monitor`）。
3. **持久化那半**：写 `~/.local/state/omarchy/toggles/hypr/<kind>-disabled-name`，
   由 **layer-2** 的 `default/hypr/disabled-input-device.lua`（经 `toggles.lua` require）在 reload 时
   读回、再调一次 `hl.device` ⇒ 这份回读在 niri 上**根本不跑**（layer-2 是死配置，见 `behavior.md` §8.6）。
   ⇒ 只改脚本不够，这一半必须一并搬到 niri 侧。
4. 本机现状：`~/.local/state/omarchy/toggles/hypr/` 不存在 ⇒ 这个开关在本机**从没被用过**；
   取设备名那半是好的（`omarchy-hw-touchpad` / `omarchy-hw-touchscreen` 正常返回值）。

**niri 侧能力（2026-09-23：先读官方 wiki，再在临时 kdl 上 `niri validate` 实测；niri 26.04）**：
- 关设备的旋钮是 `input { touchpad { off } }` —— Input 页原文：`off` = "if set, no events will be sent from this device"。
  它是**裸 flag**（Introduction 页「Flags」段："Writing out the flag enables it, and omitting it or commenting it
  out disables it"）；实测 `off true` / `off false` **都非法** ⇒ **"开" = 删掉该行或注释掉**（`//` 或 `/-`）。
- 触控板与触摸屏是**两段**：`touchpad { off }` / `touch { off }`（后者实测合法），对应上游 `touchpad` /
  `touchscreen` 两个 kind；`keyboard { off }` 实测非法（"unexpected node"）。
- 按设备名逐个配置**没有**：Input 页「Overview」原文 "Currently, there's no way to configure specific devices
  individually (but that is planned)" ⇒ 同类型的设备只能一起关。
- `niri msg` **没有**输入设备子命令（只有 `outputs / workspaces / windows / layers / keyboard-layouts / …`）。

**关键机制：用「可选 include」当覆盖文件（文档 + 实测都支持）**
- Include 页（[Since: 25.11]，本机 26.04）：「Includes work **only at the top level** of the config」；
  「All included files are **watched for changes**, and the config **live-reloads** when any of them change」；
  [Since: 26.04]「`include optional=true "optional-config.kdl"` —— By default, including a nonexistent file will
  cause an error. You can allow nonexistent includes by setting `optional=true`」。
- Introduction 页「Loading」原文：**"The configuration is live-reloaded. Simply edit and save the config file, and
  your changes will be applied. This includes key bindings, output settings like mode, window rules, and everything
  else."** ⇒ 改文件即生效，**不需要**再调 `niri msg action load-config-file`（那个 action 只当保险）。
- 实测三例（临时目录，全部 `config is valid`）：
  1. 主文件 `input { keyboard {…} }` + `include "over.kdl"`（over 里是 `input { touchpad { off } }`）→ valid；
  2. 主文件与覆盖文件**都含 `touchpad` 子段** → valid；
  3. `include optional=true "nope.kdl"`（文件不存在）→ `WARN optional include not found` + **config is valid**。
- 另一组实测限制仍然成立，但**不妨碍**上面这条路（我一度只凭它们误判成"覆盖文件死路"，已纠正）：
  `include` **不支持通配**（`*` 被当字面量）；**同一个文件里** `input` 只能出现一次
  （"duplicate node `input`, single node expected"，这也是 Introduction 页「Sections」段的例子）；
  `include` **不能写进块内**（`input { include … }` 报 "unexpected node"）。

**采用的机制（方案 A″，2026-09-23 已落地 —— 上面「已实施」就是这套，这里只留机制本身）**：
1. 一次性：在 `~/.config/niri/input.kdl` 末尾加**两行** `include optional=true "input-toggle-touchpad.kdl"` /
   `"input-toggle-touchscreen.kdl"`（两个 kind 各一个文件，互不干扰）。
2. `~/bin/omarchy-toggle-input-device` 垫片（`~/bin` 在 PATH **第一位**，见 `config.kdl` 的 `environment`；
   上游 `omarchy-toggle-touchpad` / `omarchy-toggle-touchscreen` 都是 `exec omarchy-toggle-input-device <kind>`，
   按 PATH 查找 ⇒ **一个垫片覆盖两个 kind**）只做两件事：
   - **关**：写对应那个覆盖文件 —— `touchpad` → `input { touchpad { off } }`；`touchscreen` → `input { touch { off } }`；
   - **开**：**删掉**这个文件（缺失时只是 WARN，不报错）。
   状态 = 文件在不在；上游那套 `~/.local/state/omarchy/toggles/hypr/*-disabled-name` + layer-2 回读整体作废。
3. 触发：这些 include 文件**被 watch、改了就 live-reload**（文档原文）⇒ 无需调 reload（垫片仍显式调一次当保险）。
- ⚠ **唯一仍未实测的点（非阻塞，有意不追）**：Include 页「Non-merging sections」原文把
  **"pointing device sections in `input`"** 列为**不合并**（"Some sections where the contents represent a combined
  structure are not merged … pointing device sections in `input`"）⇒ 覆盖文件里的 `touchpad { off }` 很可能是
  **整体替换**主配置那段，而不是"只加 off、其余保留"。`off` 期间设备本就不收事件 ⇒ 被替换掉的
  `tap` / `natural-scroll` 无实害；用户也不用这个开关，故**没去实测**（谁真要用，先按"物理验证怎么做"验一次）。
  若要"精确只加一行、其余原样保留"，得改成编辑 `input.kdl` 本体（备选 A′），代价见下。
- ⚠ **备选 A′ 的副作用**：把**开关状态**直接写进 `~/.config/niri/input.kdl` 本体，会让它和仓库
  `niri-config/local/input.kdl`（`scripts/kdl-sync.sh` 经 sed 参数化后对账）出现"配置漂移"。
  注意区分：那两行 `include` **本身**是配置事实（应该进本体、两份同步，现在就是这么做的）；
  漂移风险来自"开关状态"这种运行时数据 —— 它留在覆盖文件里（A″），所以 A′ 只在上面那条
  "整体替换"实测下来不可接受时才用。

**未采用的备选**：
- B. 不补实现：照 `hyprsunset` 的惯例把菜单项 `"when":"false"` 藏掉，文档记成已知缺口。
  **未采用**——2026-09-23 用户要的是"搞定他"（实现），菜单项保持可见。
- C. 走 libinput / udev 层绕过合成器：A″ 成立后**没必要**，只在"不想让 niri 配置文件被工具改"时才值得查。

**物理验证怎么做**：`libinput` CLI 本机**没装**，而 `off` 是 libinput 层的静音（内核事件照旧在流），
所以"设备真不动了"只能靠手指试一次；程序侧看 `journalctl --user -u niri` 有没有 `loaded config`、
以及 `niri validate` 的结果 —— **别只看 OSD**（修复前它就在骗人）。

**用户决定（2026-09-23）**：device 这条**要做**（`hl.device` 触控板 / 触摸屏开关）——当天已实现并落地，见本节上面的
「已实施」；用户随后说本人用不上（TrackPoint 工作流），但要求**留在配置里**。另外两项**不需要，别补**：
`omarchy-hyprland-workspace-layout-toggle`（菜单 `Toggle ▸ Workspace Layout`，键位 `SUPER+L`）与
`omarchy-hyprland-window-transparency-toggle`（键位 `SUPER+BACKSPACE`，niri 的 `binds.kdl` 里没有该键位）。

### 窗口缝隙开关 —— `omarchy-hyprland-window-gaps-toggle`（2026-09-24 加）

上游语义：`default/hypr/toggles/window-no-gaps.lua` 一次把 `gaps_out`/`gaps_in`/`border_size`/`decoration:rounding`
全归 0，且**壳层跟着塌** —— `shell/Commons/Style.qml` 就监听同一个 flag 文件，再 `hyprctl getoption` 重读值。
niri 没有运行时 IPC 能改这些，所以三层都要接：

- **产物**（三处一起才生效）
  1. `port-bin/omarchy-hyprland-window-gaps-toggle` → `~/bin/`（PATH 第一位，盖掉上游那个走
     `omarchy-hyprland-toggle` 的版本 —— 那个帮手从 `$OMARCHY_PATH/default/hypr/toggles/` 拷，而 layer-2
     那棵树在本移植里整体 no-op，见 `behavior.md` §8.6）。
  2. `port-bin/hyprctl` 的 `cmd_getoption`：flag 在时 `general:gaps_out` / `decoration:rounding`
     都返回 `int 0`（新增 `_no_gaps()`）。**这一半是壳层那条腿的全部依据**（也是写死的映射，
     不是从 niri 读的 —— 见下面"更正"）。
  3. `~/.config/niri/layout.kdl` 尾部 `include optional=true "layout-no-gaps.kdl"`（仓库副本
     `niri-config/local/layout.kdl` 同步同一行，否则 `kdl-sync.sh` 判漂移）。**位置待改**：
     按顺序规则这条 include 应该挪到 `layout {` 块**之前**才可能生效，见下面"更正"。
- **开=写覆盖文件、关=删**：`~/.config/niri/layout-no-gaps.kdl` =
  `layout { gaps 0; focus-ring { off }; border { off } }`（对应上游的 gaps_in/out、border_size、rounding）。
  `include` 是**位置性**的 ⇒ 只覆盖它点名的属性，主题里的 focus-ring/border **配色**原样不动；
  `optional=true` ⇒ 文件不在只有一条 WARN ⇒「恢复缝隙」就是删文件。写前 `niri validate`，
  不合法立刻删回来并退 1。
- **flag 文件**：`~/.local/state/omarchy/toggles/hypr/window-no-gaps.lua`（源在时逐字拷上游内容，170B）。
- **壳层哪几处跟着塌**：`Style.cornerRadius`（读到 12 → 0）与 `Style.gapsOut`（`int 8` → `0`，
  垫片给的 8 除以 2）⇒ `Ui/PopupCard.qml`（`margin: Style.gapsOut` / `radius: Style.cornerRadius`）、
  `notifications/Service.qml` 的 `barClearance = liveBarSize + Style.gapsOut`、`Ui/KeyboardPanel.qml` 的 `gap`。
- **验证（2026-09-24，程序侧 + 视觉）**：`niri validate` 干净；开/关两侧 `hyprctl -j getoption` 输出
  12/8 → 0/0；菜单卡片同一角落 A/B 截图（`grim -o eDP-1 -t ppm`）**圆角 12 → 直角**，像素级成立；
  用插桩过的 `hyprctl` 记调用，确认 flag **新建与删除都会**让壳层重跑那两个 `getoption`。
- ⚠ **更正（2026-09-24 晚，同一轮做 clamshell 时发现）：上面那些证据只证明"壳层侧"通了，niri 侧那半可疑。**
  两个理由：① `cmd_getoption` 是**写死**的（`rounding` 恒 12、`gaps` 恒 8，flag 在时归 0）——
  它**从不读 niri**，所以"getoption 12/8 → 0/0"根本不能当 niri 的证据；② 圆角/间距的 A/B 是**壳层**画的
  （`Style.qml` 读同一对 `getoption`，即同一条回路），也证明不了 niri 的 `gaps`。
  而按本轮实测出的顺序规则（同名键取**第一次**定义，见下面「内屏开关 / clamshell」小节），
  `layout-no-gaps.kdl` 里 `gaps 0` 与 `layout.kdl` 第 8 行 `gaps 8` **同名**，而 include 在**尾部**
  ⇒ 这个覆盖文件很可能一直是**空的**（三处里只有前两处真在干活）。
  当晚做过两次探针都不结论（`struts { left 100 }` 放在尾部与首行，`niri msg windows` 的 `tile_size`
  都是 1280×800 不变；`focused` 那个窗口本身就是满工作区尺寸，看不出一致性）⇒ **待重验**：
  拿一个非最大化/非贴边窗口配两张窗口的桌面，用 `grim` 量窗边到屏边的像素，分别在首行/尾部 include 下取数。
  **在重验之前，本卷不再声称"niri 侧也实测通"。**
- ⚠ **坑（已在 `install.sh` 补掉）**：壳层那条 `FileView` 的 watch **只在壳层启动时该目录（或文件）已存在**
  才挂得上。`~/.local/state/omarchy/toggles/hypr/` 在本机 2026-09-24 之前**从不存在**（layer-2 是死配置，
  没有任何东西创建它）⇒ 在"目录还没被创建过"的壳层里，这个开关只塌窗口、不塌卡片，**要重启壳层才对**。
  所以 `install.sh` 现在会 `mkdir -p` 这个目录；遇到"窗口变了拉花没变"，先 `omarchy-restart-shell` 再查。
- **不发通知**：上游靠窗口自己的边给反馈，而这是一键改全桌面的状态，吐司只会给已经看得见的状态加噪音；
  保留 stdout 打印 flag 状态（与 `omarchy-hyprland-toggle` 一致）。
- **回退**：`~/bin/omarchy-hyprland-window-gaps-toggle off`；要整套拆掉就删 `~/bin/` 那个垫片、
  `layout.kdl` 那行 include、菜单 override 里对应项。改动前备份（`~/.local/state/backups/`）：
  `.config/niri/{layout.kdl,config.kdl}.bak-20260924-nogaps`、`.config/omarchy/extensions/omarchy-menu.jsonc.bak-20260924-nogaps`、
  `bin/hyprctl.bak-20260924-nogaps`。
- **上游语义对齐**：`window-no-gaps.lua` 是 gaps_out/gaps_in/border_size + rounding 四项；覆盖文件用
  `gaps`（niri 内缝外缝共用一个值）/`border off`/`focus-ring off`/`rounding` 对应齐全。

### 内屏开关 / clamshell —— `hl.monitor({ disabled })` + `omarchy-hyprland-monitor-watch`（2026-09-24 加）

**上游语义**：`omarchy-hyprland-monitor-internal {on,off,toggle,recover}`（菜单 Toggle ▸ Laptop Display、
键位）与 `omarchy-hyprland-monitor-clamshell`（合盖 reconcile）都通过 `hl.monitor({ output, disabled })`
关内屏；触发器则是 Hyprland 那套 —— `omarchy-hyprland-monitor-watch` 读 Hyprland 的 `.socket2.sock`
等 `monitoradded/monitorremoved`，盖子半边靠 `default/hypr/bindings/utilities.lua` 里两条
`switch:*:Lid Switch` 绑定。**这两类触发器与 niri 都没有交集**（没有 Hyprland socket；niri 没有 switch 绑定，
只有 `switch-events {}` 配置且不带 lid 动作），所以四根针脚里"触发"那根必须自己接。

**产物（四件）**
1. `port-bin/hyprctl` 的 `_eval_monitor()` 补 `disabled` → `_set_output_disabled()`（写/删覆盖文件 + validate + 读回核对）；
   `cmd_monitors()` 的 `disabled`/`active` 改成真实值（`logical is None` ⇒ disabled）。**`disabled` 的真实值
   是 clamshell 判断"外屏在不在"的依据**（`omarchy-hyprland-monitor-external-active` 就是
   `select(.disabled == false)`），修好前它恒为 `false`。
2. `~/.config/niri/output-toggle-off.kdl` —— 状态文件本体：`output "<内屏名>" { off }`。
   `~/.config/niri/monitor.kdl` 的**第一行**是 `include optional=true "output-toggle-off.kdl"`
   （仓库副本 `niri-config/local/monitor.kdl` 同步，否则 `kdl-sync.sh` 判漂移）。
3. `port-bin/omarchy-hyprland-monitor-watch` → `~/bin/`（盖掉上游那个 Hyprland 版）：轮询循环，
   每 2 s 读一次 `/proc/acpi/button/lid/*/state`；**只在盖子合上时**才查 `niri msg outputs`（开盖状态
   零 IPC）；状态变了才调上游 `omarchy-hyprland-monitor-clamshell`（逻辑不重写，一处归上游）。
4. `default/systemd/user/omarchy-clamshell-watch.service`（装进 `~/.config/systemd/user/` +
   `graphical-session.target.wants/`）—— 上游那个 watcher 由 `default/hypr/autostart.lua` 拉起，
   而那棵树在本移植里整体 no-op ⇒ 不装单元它就永远不会跑。

**⚠ 顺序规则（本轮踩到并实测，此后所有 monitor 覆盖文件都按这条写）**：niri 对**同名键取第一次出现的定义**，
后面重复的 `output` 块**整块无效**（niri wiki Configuration: Introduction 原文：`output "eDP-1"` 出现两次
"This is NOT valid… It will either throw a config parsing error, or otherwise not work"）。
2026-09-24 在 niri 26.04 上用 `eDP-1` 的第二个块实测两侧：
- **尾部** include（放在 output 块**之后**）→ `scale 1.5` 与 `off` **都没生效**（`logical` 一直非 null）；
- **首行** include（放在 output 块**之前**）→ 两个都生效（先 `logical.scale=1.5`，后 `logical=null` = 屏真的黑了）。
**合并是按"键"不是按"块"**：覆盖文件为首行时，下面那块的自定义 modeline / position 照旧生效 ——
这也是覆盖文件里**只写 `off` 一个键**的原因（写多了就会抢掉 monitor.kdl 里的同名键）。
⇒ 同一个理由，`layout.kdl` 尾部那个 `layout-no-gaps.kdl`（`gaps` 与 `layout.kdl` 第 8 行同名）
**大概率是空的**，见下面 §4「窗口缝隙开关」那条待办。

**验证（2026-09-24，程序侧 + 真屏 + 离线）**
- 真机端到端：`~/bin/hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = true })'` ⇒ **屏真的黑了**
  （`niri msg --json outputs` 的 `logical` 变 `null`、`current_mode` 变 `null`），stderr **无**告警（读回核对通过）；
  上游口径同一时刻 `hyprctl monitors all -j` = `{"name":"eDP-1","disabled":true,"active":false}`；
  `disabled=false` ⇒ 屏回来、**模式仍是自定义那条 `2560x1600@59.97`（USERDEF）**，没掉回 4K。
  关屏瞬间 niri 日志是 `disconnecting connector: "eDP-1"`，回来是 `picking mode: … 2560x1600@59.97`。
- 离线契约测试：`port-bin/tests/test-hyprctl-shim.sh` 新增一节（写覆盖文件 / validate / reload / `disabled`
  读回 / 上游 `external-active` 三种局面 / 配置不合法时自动删回 / 不给别的输出删文件），**34/34 绿**；
  覆盖文件路径由 `XDG_CONFIG_HOME` 决定 ⇒ 测试碰不到真 `~/.config/niri`。
- watcher 离线测试：`port-bin/tests/test-clamshell-watch.sh`（假盖子、假 outputs、假 reconcile）**10/10 绿** ——
  开盖不动 / 合盖调一次 / 状态不变不重复调 / 外屏出现再调 / 开盖再调 / 无盖子直接退 0 / 关开关退 0。
- 常驻成本实测：单元起来后头一次 reconcile ~1.0 s CPU，之后 25 s 内 CPU 停在 1.09 s、RSS ~1 MB
  ⇒ 稳态就是每 2 s 一次 `/proc` 读，没有 IPC。
- **没验到的分支（别当成已验）**：本机没有外屏、也没真的合过盖（合盖会挂起，见下）⇒
  「合盖 + 外屏 ⇒ 关内屏」这条只有离线测试覆盖，真机只验了"无外屏 ⇒ 内屏保持开"以及手工关/开内屏。
- 单元**登录时自动拉起**没等到下次登录验（`WantedBy=graphical-session.target` + `…wants/` 软链，与 `omarchy-picker-warmup.service` 同款机制；本轮只 `systemctl --user start/restart` 手动验过 —— `Type=simple`，可以放心用 `restart`，不像 oneshot 那种会挂住）。

**没做的那半：不挂起**。合盖是否挂起不在 niri 手里，而在
`/etc/systemd/logind.conf.d/lid-suspend.conf`（**装机写入**，三档合盖都是 `suspend`，其中
`HandleLidSwitchDocked=suspend` 把"插着外屏"也算 docked）。要"合盖继续用外屏"就得把它改成 `ignore`：
root 改动 ⇒ **等用户拍板**；真要做：`cp` 备份到 `~/.local/state/backups/etc/systemd/logind.conf.d/lid-suspend.conf.bak-<后缀>`、
改一行、`systemctl reload systemd-logind`，回退就是把备份 `cp` 回去再 reload。**本机没外屏 ⇒ 改完也验不了**，
所以本轮**没动它**。

**关开关 / 回退**
- 停 watcher：`touch ~/.local/state/omarchy/toggles/clamshell-watch-off` —— 脚本下一个 tick
  （≤2 s）**干净退出**，单元变 inactive（日志留一行原因）；**恢复**：删 flag +
  `systemctl --user start omarchy-clamshell-watch.service`（或下次登录，那时 `ConditionPathExists`
  直接跳过）。⚠ 单元因此是 **`Restart=on-failure` 而不是 `always`**：`always` 会把"退出"变成
  每 2 s 起一次、起完就退的循环。彻底关掉：`systemctl --user disable --now omarchy-clamshell-watch.service`。
- 恢复内屏：`~/bin/hyprctl eval 'hl.monitor({ output = "eDP-1", disabled = false })'`
  或直接 `rm ~/.config/niri/output-toggle-off.kdl && niri msg action load-config-file`。
- 整套拆掉：删 `~/bin/omarchy-hyprland-monitor-watch`、单元（含 `…wants/` 软链）、
  `monitor.kdl` 首行 include（仓库副本同步删）。
- 改动前备份：`~/.local/state/backups/.config/niri/monitor.kdl.bak-20260924-clamshell`、
  `bin/hyprctl.bak-20260924-clamshell`。

### 验证命令
```sh
~/bin/hyprctl -j clients            # 返回合法 Hyprland schema JSON
~/bin/hyprctl dispatch exec ghostty # 启动终端
~/bin/hyprctl dispatch hl.dsp.focus workspace 3
```

> 已知限制：Hyprland 的 `clients` schema 字段（如 `address`、`class`）按 niri 数据映射，
> 若某脚本依赖 Hyprland 独有的字段值可能拿到空/占位，但不至于崩溃。

---

---

2. **`hyprctl` 垫片本轮修复**：`monitors` 输出补上 `activeWorkspace.id` 与 `transform`，并把
   `width`/`height` 修正为物理分辨率（`format_geo` 需 `width/scale` 得逻辑尺寸）。
   这修复了 `omarchy-capture-region` 的 `active_workspace()` 取空 → `""|tonumber` 报错。
   同时修正 `_focused_output_name()`：niri `focused-output` 输出形如 `Output "..." (eDP-1)`，
   原正则 `^[^:]+` 无冒号时吞掉整行，现改为提取末尾括号。

---

5. **hyprctl schema 精度**：个别 Hyprland-only 字段可能是占位值；如遇脚本异常再补映射。

---

7. **TUI 编辑器启动已修**：`omarchy-launch-tui` 原本走 `uwsm-app`+`xdg-terminal-exec`（Hyprland/uwsm
   组件，niri 会话没有），导致菜单 "Edit config file" 点了无反应。已回退到 `ghostty`（匹配 niri
   `Mod+Return` 终端），实测链路通（ghostty 打开→运行→退出）。
   **菜单指向已由 A 层重定向到 niri 真配置**（见 §8.6），不再打开 `~/.config/hypr/*.lua` 空文件。

---

22. **应用启动类调用统一到一个 `uwsm-app` 垫片（2026-09-19 修）**：上游 Omarchy `bin/` 里有 ~30 处
    `uwsm-app -- <command>`——它的本意是把应用挂进 transient systemd user unit，那是 Hyprland/uwsm
    会话才有的能力；本 niri 会话连 `uwsm` 都没有，于是这 30 处**全部静默死亡**：
    `setsid: failed to execute uwsm-app: No such file or directory`。用户可见症状是"点了没反应、也不报错、
    没有窗口"——`omarchy-launch-terminal`、`omarchy-launch-nautilus(-cwd)`、`omarchy-launch-browser`、
    `omarchy-launch-webapp`、`omarchy-launch-1password`、`omarchy-launch-discord-community`、
    `omarchy-restart-app`、各 `omarchy-install-*` 装完自动拉起应用、以及壳层 `services/AppLibrary.qml`
    的 App 列表全在内（§8 第 7、14、21 条当年只修了其中漏出来的几处）。
    **修法（统一，只加一个文件）**：新增 PATH-first 垫片 `~/bin/uwsm-app`（仓库副本 `port-bin/uwsm-app`，
    随 `install.sh` 的 `port-bin/*` glob 装进 `~/bin`；`~/bin` 在 niri 会话和 Quickshell 壳层的 `PATH`
    里都排第一，已实测）。它丢掉 uwsm-app 自身的选项和 `--` 之后 `exec "$@"`，**不做** systemd
    scope/unit/cgroup 记账——调用方只依赖"进程起得来、且已脱离调用者"，niri 不需要更多。这样**不必**去
    30 个调用点逐个打补丁（那会把 `niri.patch` 从 20 文件/36 hunk 顶到几十个 hunk，且每次上游更新都要
    重放一遍）。§3.2 里那 4 处 `command -v uwsm-app` 守卫**保持原样**：垫片在位时它们走 uwsm-app 分支
    （= 垫片 = 直接 exec，等价而更短），垫片被删时它们仍是"没装垫片的新机器"的兜底。
    验证：`port-bin/tests/test-uwsm-app-shim.sh`（**离线**：假命令 + 临时目录，13 项——参数透传 /
    uwsm-app 自身选项被丢 / 无 `--` 也认 / 无参 exit 1 / `--help`·`--version` exit 0 / 子命令退出码透传 /
    systemd-run unit 存活 / `bash -n`）13/13 绿；真机 `omarchy-launch-terminal`、`omarchy-launch-browser`
    实测均开出窗口。回退：`rm ~/bin/uwsm-app`。
    **v1.1（2026-09-20）——垫片里那句 `setsid` 是有害的**：v1.0 写的是 `exec setsid "$@"`，在"调用方自己
    已经 `setsid`"或"niri `spawn` 直接起"这两类路径上没问题（终端、编辑器、nautilus 都这么走，实测通），
    但**凡是调用方用 `systemd-run --user` 起的就会静默失败**：unit 里的主进程本身就是 session leader，
    `setsid` 只能 fork 后立刻退出 → systemd 判定 unit 已结束 → 按默认 `KillMode=control-group` 清掉整个
    cgroup → 刚起的应用被杀。症状极具误导性：**退出码 0、无任何报错、没有窗口**（因为这类调用方都带
    `--property=StandardError=null`）。踩到的是 `bin/omarchy-launch-browser`（默认浏览器＝Zen）。
    定位手法：`journalctl --user` 能看到 `Started [systemd-run] …/bin/uwsm-app -- /usr/lib/zen-browser/firefox`，
    说明 unit 起过；再做对照实验——直接 `systemd-run --user … /usr/lib/zen-browser/firefox`（不经垫片）
    3 秒就出窗口 → 锁定垫片。修法：垫片改成 `exec "$@"`（调用方要脱离自己会 `setsid`），并给回归测试加了
    "unit 在应用运行期间必须仍 active + 应用必须活到结束"两项。
    **边界（垫片只解决"调用死掉"，不解决调用方语义错误）**：`omarchy-toggle-nightlight` 调
    `uwsm-app -- hyprsunset`，niri 上 hyprsunset 本身没意义（§8 第 19 条一带）；`omarchy-launch-or-focus`
    的默认命令写成 `uwsm-app -- $WINDOW_PATTERN`，把窗口匹配串当命令——这两个是上游调用方的毛病，另议。

---

34. **AUR 助手统一成 `yay` → paru 垫片（`~/bin/yay`，2026-09-22 修）**：上游 Omarchy 的 AUR 调用全走
    `yay`（`install/omarchy-base.packages` 里就装着它），本机只有 paru、`yay` 不存在 ⇒
    `omarchy-pkg-aur-install`（菜单 Install → AUR）本体就是 `yay -Slqa | fzf`，列表取空 ⇒ **选择器打开
    是空的、预览也没内容**；同类调用还有 `omarchy-pkg-remove`（Remove → Package 的预览）、
    `omarchy-pkg-aur-add`、`omarchy-update-aur-pkgs`（本机 `omarchy-update` 垫片本来就绕过最后这个）。
    **修法（只加一个文件）**：PATH-first 垫片 `~/bin/yay`（仓库副本 `port-bin/yay`，随 `install.sh` 的
    `port-bin/*` glob 装进 `~/bin`），参数原样透传给 paru —— `-S --noconfirm --needed`、
    `-Slqa`（只出 AUR：119811 条，正是 `-Slq` 的 139987 减官方 `pacman -Slq` 的 20176）、
    `-Siia` / `-Qi` / `-Qqe`、`-Sua --noconfirm --cleanafter --ignore a,b`、`aur/<name>` 前缀，
    全部实测可用；`--noconfirm` 在 paru 里确实非交互（审核的门是 `!config.no_confirm`，paru
    `src/install.rs` 的 `review()` 开头），所以不会在菜单那个浮窗终端里冒出 PKGBUILD diff 分页器。
    **唯一的语义缺口是 `-Gp`**：yay 会在 PKGBUILD 前多打四行（空行/空行/`# 包名`/空行，yay `get.go`
    `printPkgbuilds` 的 `logger.Printf("\n\n# %s\n\n%s", …)`），这正是上游
    `--bind 'alt-b:change-preview:yay -Gpa {1} | tail -n +5'` 里 `tail -n +5` 的来历；paru 的 `-Gp`
    只打裸 PKGBUILD，**垫片把四行补回来** —— 否则 alt-b 预览会静默吃掉 PKGBUILD 的头四行。
    垫片扫 PATH 找真 paru 时跳过自己所在目录，且**不依赖外部命令**（`dirname` 在被裁过的调用环境
    `env PATH=/usr/bin:/bin` 里会失败，跳过自身目录随之静默失效 —— 这条是离线测试当场抓出来的）。
    验证：`port-bin/tests/test-yay-shim.sh`（离线，假 paru，4 项：参数原样透传 / `-Gp` 补头且
    `tail -n +5` 拿到完整 PKGBUILD / 非 `-Gp` 不加头 / `bash -n`），4/4 绿；真机在 pty 里跑了菜单那两个
    TUI（Install → AUR 列表 119811 条 + 信息面板、alt-b 预览首行 `# Maintainer: …`、Remove 的
    `paru -Qi` 预览），原始输出是合法 UTF-8、零 U+FFFD，装包数 1191 前后不变。回退：`rm ~/bin/yay`。

---

## 通用剪贴板垫片（`omarchy-universal-clipboard` + `omarchy-sendkeys`，2026-09-27 加，`§8 第 42 条`）

**是什么**：niri 版的 Omarchy「通用复制 / 粘贴 / 剪切」。`Mod+C/V/X` 由 niri 抓走
（`niri-config/local/binds.kdl`），垫片按**焦点窗口**决定注入哪组键 —— 终端 `Ctrl+Insert` /
`Shift+Insert`，其他 `Ctrl+C/V`，剪切恒 `Ctrl+X`。键位表照抄上游
`~/.local/share/omarchy/default/hypr/bindings/clipboard.lua`，终端名单照抄
`default/hypr/apps/terminals.lua` 的正则（匹配 niri 的 `app_id`，`org.omarchy.*` 与 `TUI.*` 都在内）。
两个脚本都在 `port-bin/`，随 `install.sh` 的 `port-bin/*` glob 装进 `~/bin`；`~/bin` 在 niri 的
`config.kdl` `environment { PATH … }` 里排第一，所以 bind 里可以直接写命令名。

**终端里的复制会给一次视觉反馈**：注入完（剪贴板真写了）再弹一张壳层 OSD 卡片
`omarchy-osd -i <nf-md-content_copy U+F018F> -m Copied -d 1200` —— 就是关机/重启那种卡片
（`bin/omarchy-system-logout` 同款调用）。**剪切不弹卡片**：ghostty 没有 cut 动作
（`ghostty +list-actions` 里只有 copy/paste），终端里 `Ctrl+X` 只是**转发给应用**（vim/tmux 里才真会切），
剪贴板纹丝不动 —— 实测判据：探针 PTY 收到 `0x18`、`wl-paste` 读回原哨兵，所以弹 "Cut" 是虚报。
（若哪天想让终端里的 X 当复制使唤，图标备好：`U+F0190` nf-md-content_cut＝剪刀，Nerd Font 里有、渲染验过。）
**不用 ghostty 自己的通知**：`app-notifications = clipboard-copy`
走 libnotify 吐司，本机那条链路看不到东西，所以 `~/.config/ghostty/config` 里保持
`no-clipboard-copy`。反馈只给**终端分支的复制**（浏览器里频繁复制不该被卡片打扰）；
无选区时 ghostty 的 copy 其实是空操作，卡片仍会弹（垫片没法知道有没有选到东西）。

**为什么要自造注入原语**：上游在 Hyprland 上靠 `hl.dsp.send_key_state`（合成器自带键注入）。
niri 的 bind 只有 `spawn`，没有等价能力 ⇒ 用 uinput 垫片 `omarchy-sendkeys`：临时建一把键盘、
发和弦、销毁。**零安装**：`/dev/uinput` 对本机用户有 rw ACL（不需要 root / polkit / udev 规则 /
额外包）。`wtype` 已否掉：它走 wayland 虚拟键盘，会把自己那份最小 keymap 推给客户端，GTK4 客户端
收得到 `key` 事件却解不出字符（`WAYLAND_DEBUG=1` 下 `key`/`modifiers` 齐全，PTY 侧零输出）。

**两条硬约束（实测，不是推测）**：

1. **必须声明 1..248 全段键码**。只声明实际要用的两三个键时，udev 只给 `ID_INPUT_KEY`（而非
   `ID_INPUT_KEYBOARD`），libinput 就不把它当键盘 ⇒ 客户端收不到键，合成器 bind 也不认
   （判据：`udevadm monitor --subsystem-match=input --property` 里看 `ID_INPUT_KEYBOARD`）。
2. **物理按住的 SUPER 会并进注入的和弦**（上游 `clipboard.lua` 注释里那条在 niri 上同样成立）：
   按住 Super 时注入 `Ctrl+Insert`，客户端实际收到 `Super+Ctrl+Insert`（终端里回显 `ESC[2;13~`）。
   终端侧由 `config/ghostty/config` 里的 `super+ctrl+insert` / `super+shift+insert` 变体接住
   （上游那份没有这两条，是本机补的）；非终端（浏览器等）没有这个余地，只能靠"用户已松开 Super"
   —— 注入本身 ~0.25 s 起步，轻点 `Super+C` 不受影响。补发一个合成的 `super` 松开事件**不能**清掉
   它（niri 的修饰键状态按设备算、客户端看并集，实测无效）。

**成本**：每次按键 wall ≈ 0.45 s，其中 CPU 仅 36 ms（`python3 -c pass` 启动 29 ms，峰值 RSS 11 MB）；
余下 0.40 s 是 `UIKEY_WAIT`(0.25) + `UIKEY_TAIL`(0.15) 两个刻意 sleep，等 libinput / 合成器把新设备
枚举进来。**这段是内核/netlink 侧开销，换 C 重写省不掉**（ydotool 快是因为它常驻、设备只建一次）。
要毫秒级就得常驻；两个变量都可用环境变量覆盖，便于往下压阈值。

**验证**：

```sh
omarchy-universal-clipboard copy  --dry-run --app-id=com.mitchellh.ghostty   # → ctrl+Insert（终端分支）
omarchy-universal-clipboard paste --dry-run --app-id=zen                     # → ctrl+v（非终端分支）
omarchy-sendkeys super+c     # 真实链路：niri 的 bind 抓走 Super+C → 垫片 → 注入
```

`--dry-run` 只打印判定不注入；`--app-id=` 是测试用的覆盖。走真机判据时用探针窗口：
`XDG_CONFIG_HOME` 指到临时目录的 ghostty + `keybind = ctrl+insert=text:PROBE_CTRLINS`，
终端 raw 模式读 PTY（`stty -icanon min 1 -echo`，否则行缓冲会让人误判"没送到"）。
单独看那张卡片：`omarchy-osd -i 󰆏 -m Copied -d 3000`（`󰆏` = U+F018F）。整条链要按 bind 的
执行环境验，别用自己的 shell：`niri msg action spawn-sh "omarchy-universal-clipboard copy"`
（焦点在终端时才会注入 + 弹卡片，截图前后比对能看出卡片位置）。
**顺手的一个用途**：注入器现在认识 `comma`/`period`，所以 `omarchy-sendkeys ctrl+shift+comma` 等于给运行中的
ghostty 按一次 `reload_config` —— 实测够用：改配置后重载，新增的 keybind 立即生效（探针实例上验过：
按新键先出 `PROBE_BEFORE`，改配置 + 重载后出 `PROBE_THIRD`），不必重启终端窗口。

**回退**：`~/.local/state/backups/.config/niri/binds.kdl.bak-20260927` 与
`~/.local/state/backups/.config/ghostty/config.bak-20260927`；或删掉三个 bind + 四个 ghostty keybind，
并 `rm ~/bin/omarchy-universal-clipboard ~/bin/omarchy-sendkeys`。

