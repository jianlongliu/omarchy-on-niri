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
- 对 Hyprland-only 的特性（`hyprsunset`, `hl.config cursor`, `hl.device`, `hl.monitor`,
  `hl.workspace_rule`, `setprop opaque`）降级为安全的无操作（no-op），避免脚本报错。

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
