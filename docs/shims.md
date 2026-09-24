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
- 〔§4〕**`hl.device` 触控板 / 触摸屏开关：在 niri 上曾"假成功"，2026-09-23 已补好**（垫片 + `include optional=true` 覆盖文件，用户拍板）；用户当日晚决定**功能留着但本人用不上**（TrackPoint 工作流）⇒ 菜单项不藏、Fn 键不绑（绑法与"那个键在 niri 上本是死的"都记在 §4）。同段落里另两项（workspace-layout / window-transparency）用户明确**不需要，别再补**
- 2. **`hyprctl` 垫片本轮修复**：`monitors` 输出补上 `activeWorkspace.id` 与 `transform`，并把
- 5. **hyprctl schema 精度**：个别 Hyprland-only 字段可能是占位值；如遇脚本异常再补映射。
- 7. **TUI 编辑器启动已修**：`omarchy-launch-tui` 原本走 `uwsm-app`+`xdg-terminal-exec`（Hyprland/uwsm
- 22. **应用启动类调用统一到一个 `uwsm-app` 垫片（2026-09-19 修）**：上游 Omarchy `bin/` 里有 ~30 处
- 34. **AUR 助手统一成 `yay` → paru 垫片（`~/bin/yay`，2026-09-22 修）**：上游的 AUR 调用全走 `yay`，本机只有 paru

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
- **`hl.monitor` 不在此列**（2026-09-23 修正，本节原先把它也写成 no-op，与代码不符）：
  垫片有 `_eval_monitor()` 分支，把 `scale`/`position` 翻译成 `niri msg output …`——
  `mode` 故意跳过（niri 不认 Omarchy 回传的 `WxH@Hz` 形式，且输出本来就在该模式上）
  ⇒ 显示器缩放 / 内屏开关 / 镜像 / clamshell 这几项在 niri 上是**真能用**的。

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
