# Omarchy on niri — 移植方案与运维文档

> 目的：把 DHH 的 Omarchy v4（原本 Arch + Hyprland + QuickShell）移植到 niri
> 滚动平铺 Wayland 合成器上，运行在 `yvonne` 账户，并保持 niri 原生体验。
> 本文档是"上下文丢失也能重建"的持久记录。最后更新：2026-09-19（文档合并：`~/Documents` 母本与
> 仓库 `docs/omarchy-on-niri-port.md` 归并为一，两份逐字节一致；补回仓库版缺的 §5.7/§5.8、媒体键 OSD、
> `binds` 递归展开、发布流程等块，并补入仓库版今天的 §8.9 上游合并基线与 §9/§10 新条目；新增
> §8.10 主题动态取色、§8.11 bar 插件层；修正 §5.6 C 层回归（已修）、§8.8 浮栏模糊规则变更）。

---

## 1. 硬性约束（不可违背）

1. **不破坏隔壁 `jianlongliu` 账户（uid 1000）**，用户仍在使用。
   - 所有改动只落在 `/home/yvonne/`（`~/.config`, `~/.local`, `~/bin`）。
   - 不写 `/home/jianlongliu`，不运行影响全系统的安装。
2. **系统底层不做变动**：
   - 保持 systemd-boot 引导加载器不变。
   - 保持 greetd / dms-greeter 显示管理器不变。
   - 保持 plymouth 不变。
   - 不装/不删任何系统包（`pacman` 需 sudo 密码，非交互不可用，天然保护）。
3. **视觉效果维持 Omarchy 原样**（Quickshell bar / menu / 配色）。
4. **快捷键 `Super+Space` 维持 Omarchy 那套**（`omarchy-menu toggle`）。

---

## 2. 架构总览

```
niri (Wayland compositor, KDL config)
   │   niri msg -j (JSON IPC)   ▲ 命令行调用
   ▼                           │
hyprctl 垫片 (~/bin/hyprctl, Python)     Niri.qml 单例 (Commons)
   │  为 Omarchy bin/* 脚本翻译          │  为 Quickshell Bar 提供
   │  hyprctl → niri msg                 │  Hyprland.* 等效数据模型
   ▼                           │
Quickshell (layer-shell UI, compositor-agnostic)
   ▼
Omarchy shell (~/.local/share/omarchy/shell)
```

Omarchy v4 本身是 **Hyprland-only** 的（`config/` 内有 80 处 hyprland 引用，无 niri）。
但它的 shell 是 QuickShell 写的，仅 `import Quickshell` / `Quickshell.Io`，**不依赖 Hyprland
原生模块**。真正与合成器打交道只有两条链路，都已被桥接：

- **`hyprctl` 命令调用**（53 个 `bin/` 脚本）→ 用 Python 垫片翻译成 `niri msg`。
- **QuickShell `Hyprland` QML 模块**（bar 读 `workspaces/.focusedWorkspace/.focusedMonitor`）
  → 用 `Niri.qml` 单例订阅 `niri msg -j event-stream` 提供等效数据（2026-09-19 前为 500ms 轮询，见 §6）。

参考的中间层模式：DankMaterialShell (DMS, AvengeMedia) —— Go daemon + unix socket JSON 协议，
原生支持 niri。本方案选用的是更轻量的"hyprctl 垫片"而非 DMS daemon，因为 Omarchy 的
hyprctl 调用面有界、可直接映射。

---

## 3. 文件清单（改动/新建/备份）

### 3.1 新建的核心交付物

| 路径 | 作用 |
|---|---|
| `~/bin/hyprctl` (624 行, +x) | hyprctl 垫片：Omarchy 的 `hyprctl` 调用 → `niri msg`，纯 stdlib，不依赖 jq；`cmd_binds` 支持 `include` 递归展开（config.kdl 模块化后键位仍可见，见 §4） |
| `~/.local/share/omarchy/shell/Commons/Niri.qml` (186 行) | QuickShell 单例，**订阅 niri 事件流**（`niri msg -j event-stream`），暴露 `workspaces/focusedWorkspace/focusedMonitor` + `overviewOpen`（§6、§8.15） |
| `~/.local/share/omarchy/shell/plugins/blurwallpaper/` (`BlurWallpaper.qml` + `manifest.json`) | 移植自有 QuickShell 插件（id `omarchy.blurwallpaper`，kind `service`）：overview 期间渲染强模糊壁纸；图层**常驻映射**、由 niri 只在 overview 内合成（§8 第 10 条、§8.16） |
| `~/bin/omarchy-niri-apply-theme` (Python, +x) | 把当前 Omarchy theme 的边框色写进 niri 的 `focus-ring`（C 层换色）；**沿 `include` 定位**含 `focus-ring` 的模块、支持渐变取首个色站（§5.6） |
| `~/bin/materal-update` (Python, +x) | **主题动态取色生成器**：读当前壁纸 → matugen 出 M3 配色 → 映射成 omarchy `colors.toml` → 重套主题（§8.10；仓库副本 `port-bin/materal-update`） |
| `~/.config/omarchy/themes/tonal-spot/` | 用户级主题（`matugen.toml` + 自生成 `backgrounds/` + 静态 ANSI 16 色），`omarchy theme set Tonal-Spot` 选用（§8.10） |
| `~/.config/omarchy/hooks/theme-set.d/20-materal` | 换 theme 时重新取色（与 `10-niri-border` 并列，§8.10；仓库副本 `hooks/theme-set.d/20-materal`） |
| `~/.config/systemd/user/materal-recolor.{path,service}` | 盯 `current/` 与 `current/background` 的 path/service 单元：换壁纸即自动重取色（§8.10） |
| `~/.config/omarchy/plugins/yvonne.arch-logo/`、`~/.config/omarchy/plugins/yvonne.workspaces/` | 用户级 bar 部件（仓库外、抗 `omarchy update`）：Arch logo、胶囊式工作区指示（§8.11） |
| `~/.config/omarchy/plugins/ronald.input-sources/` | 第三方 bar 部件：fcitx5 输入源徽章/切换菜单（`omarchy plugin add … --enable` 装的 git 克隆；仓库外、抗更新，§8.17） |
| `~/.config/omarchy/backgrounds/{tonal-spot,catppuccin}` | 共享壁纸库软链 → `/data/Pictures/Wallpapers`（所有主题翻同一套图，§8.12） |
| `~/omarchy-wallpaper-aio/` | 参考仓库 `jianlongliu/omarchy-wallpaper-aio` 的克隆：只含 `setup.sh`（把主题背景目录软链到壁纸库，§8.12） |
| `~/bin/omarchy-niri-system` (+x) | **统一系统动作入口**：logout→`niri msg action quit --skip-confirmation`、reboot→logind D-Bus `Manager.Reboot`、shutdown→logind D-Bus `Manager.PowerOff`（均免密），统一 OSD+关窗+分发 |
| `~/bin/omarchy-niri-repatch` (+x) | 上游更新后重放 niri 移植覆盖层（patch + `Niri.qml` + `plugins/*`）|
| `~/bin/omarchy-powerprofiles-list` + `~/bin/omarchy-powerprofiles-set` (+x) | **TLP 感知**的电源 profile 脚本（见 §8 第 11 条）：优先 `powerprofilesctl`，缺则回退 D-Bus `net.hadess.PowerProfiles` |
| `~/.config/omarchy/hooks/theme-set.d/10-niri-border` | 换 style 时自动 `omarchy-niri-apply-theme`（只写不重载，保护 SCALE）|
| `~/.config/omarchy/hooks/post-update.d/10-niri-repatch` | `omarchy update` 后自动重放覆盖层 |
| `~/.config/omarchy/niri-port/`（`niri.patch` + `Niri.qml` + `plugins/` + `plugin-patches/` + `backups/`）| 移植覆盖层产物（仓库外，重放用）|
| `~/.ante/projects/-home-yvonne/memory/project-omarchy-niri.md` | 项目记忆 |

### 3.2 修改

| 路径 | 改动 |
|---|---|
| `~/.local/share/omarchy/shell/Commons/qmldir` | 加一行 `singleton Niri 1.0 Niri.qml` |
| `~/.local/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml` | 去掉 `import Quickshell.Hyprland`；`Hyprland.workspaces`→`Niri.workspaces`、`Hyprland.focusedWorkspace`→`Niri.focusedWorkspace` |
| `~/.local/share/omarchy/shell/plugins/menu/Menu.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`（只磨砂菜单卡片，不全屏，见 §8.8）|
| `~/.local/share/omarchy/shell/Ui/KeyboardPanel.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`（覆盖所有 bar 弹窗面板，见 §8.8）|
| `~/.local/share/omarchy/shell/plugins/bar/Bar.qml` | 去掉 import；`Hyprland.focusedMonitor`→`Niri.focusedMonitor` |
| `~/.local/share/omarchy/shell/plugins/osd/Osd.qml` | OSD 改"卡片大小 surface" + 磨砂（§8.8） |
| `~/.local/share/omarchy/shell/services/AppLibrary.qml` | 加 `command -v uwsm-app` 回退（niri 无 uwsm-app，§8 第 14 条） |
| `~/.local/share/omarchy/shell/plugins/background/Background.qml` | `readlinkProc` 回调强制即时切换背景（见 §8 第 1 条 b）|
| `~/.local/share/omarchy/bin/omarchy-launch-tui` | 加 uid 终端回退（ghostty），因 niri 无 `uwsm-app`/`xdg-terminal-exec` |
| `~/.local/share/omarchy/bin/omarchy-launch-editor` | 同上：`uwsm-app` 存在才用、否则直接 `setsid $editor` 启动（niri 无 uwsm）|
| `~/.local/share/omarchy/bin/omarchy-launch-floating-terminal-with-presentation` | 同上：`uwsm-app`+`xdg-terminal-exec` 缺时遍历 `ghostty/kitty/alacritty/foot` 起演示终端 |
| `~/.local/share/omarchy/bin/omarchy-theme-set` | 背景走持久文件而非过渡快照（niri 黑桌面竞态，见 §8.9） |
| `~/.local/share/omarchy/bin/omarchy-system-{logout,reboot,shutdown}` | 转调 `~/bin/omarchy-niri-system`（niri quit / logind D-Bus，§8 第 9 条） |
| `~/.local/share/omarchy/bin/omarchy-refresh-hyprland` | **niri 感知**：`XDG_CURRENT_DESKTOP=niri` 时整脚本变 no-op（不再重建 `~/.config/hypr`）|
| `~/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc` | **菜单指向 niri 真配置**（见 §8.6）|
| `~/.config/niri/config.kdl` | 编排器：`environment`/`spawn`/`animations`/`screenshot-path` + 6 个 `include`（§5.7）；`focus-ring` 在 `layout.kdl`，颜色由主题驱动（§5.6）|
| `~/.config/niri/{input,monitor,layout,window-rules,effects,binds}.kdl` | 模块化拆分出的子配置（§5.7）：输入/显示器/布局/窗口规则(含圆角)/磨砂(effects)/按键 |
| `~/.config/niri/effects.kdl` | 2026-09-19 给 `^omarchy-bar$` 配 `background-effect { xray false }`（浮栏磨砂；圆角模糊区域由插件端下发，§8.8）|
| `~/.config/omarchy/shell.json` | bar：`id` = `charlieras262.floating-bar`、`floatGap` 8、`cornerRadius` 10；`layout.left` = `yvonne.arch-logo` + `yvonne.workspaces`；`layout.right` 2026-09-19 摘掉空转的 `charlieras262.omablur`、并由 `ronald.input-sources` 取代 `ryuhzk.ime`；`layout.center` 同日摘掉 `omarchy.keyboard-layout`（与插件徽章重复，§8.11、§8.17）|
| `~/.config/ghostty/config` | 半透明 (`background-opacity = 0.85`) + 关自带模糊 (`background-blur-radius = 0`)，blur 交给 niri（§5.8） |

### 3.3 备份（重要，可回滚）

> ⚠ 现状核对（2026-08-30）：下列两个 `config.kdl.bak-*` 文件**已不存在**（随后续重构清理）。
> 当前 niri 配置的回滚手段为：`~/bin/hyprctl.bak-20260825-211843`（垫片旧版）、
> `~/.config/omarchy/niri-port/`（patch + Niri.qml 覆盖层）、以及 pub 仓库
> `github.com/jianlongliu/omarchy-on-niri`（移植差分快照）。

| 备份 | 对应（历史，现已清理） |
|---|---|
| `~/.config/niri/config.kdl.bak-20260824-185918` | 最原始 niri 配置（未加 environment/spawn/binds） |
| `~/.config/niri/config.kdl.bak-port-20260824-193206` | 加了 environment 后、改 spawn/binds 前 |

> 现有 `~/.config/omarchy/niri-port/backups/` 里另有较新的可直接回滚的快照：
> `shell.json.bak-20260919-013624`（加 bar 部件前）、`shell.json.bak-20260919-014210-prebar`
> （上浮栏前）、`20260918-pre-merge/`（合并上游前整包）。

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

## 5. niri 配置（`~/.config/niri/config.kdl`）

### 5.1 environment 块（注意语法：`KEY "value"`，无 `=`，无 `$PATH` 展开）

```kdl
environment {
    OMARCHY_PATH "/home/yvonne/.local/share/omarchy"
    PATH "/home/yvonne/bin:/home/yvonne/.local/share/omarchy/bin:/home/yvonne/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
}
```

niri 语法要点：**不能写 `=`，不能写 `$PATH`**（不会展开），必须写全字面 PATH。

### 5.2 启动 QuickShell（替换 niri 自带的 waybar）

```kdl
spawn-sh-at-startup "quickshell -n -p /home/yvonne/.local/share/omarchy/shell"
```

### 5.3 Omarchy 绑定（不冲突子集）

```kdl
Mod+Space        hotkey-overlay-title="Omarchy Menu" { spawn-sh "omarchy-menu toggle"; }
Mod+Alt+Space    hotkey-overlay-title="Apps menu"    { spawn-sh "omarchy-menu toggle apps"; }
Mod+K             hotkey-overlay-title="Keybindings"  { spawn-sh "omarchy-menu-keybindings"; }
Mod+Ctrl+L        hotkey-overlay-title="Lock system"  { spawn-sh "omarchy-system-lock"; }
Mod+Ctrl+V       hotkey-overlay-title="Clipboard"    { spawn-sh "omarchy-shell shell toggle omarchy.clipboard"; }
Mod+Ctrl+E       hotkey-overlay-title="Emojis"       { spawn-sh "omarchy-shell shell toggle omarchy.emojis"; }
Mod+Ctrl+A       hotkey-overlay-title="Audio"        { spawn-sh "omarchy-shell shell toggle omarchy.audio"; }
Mod+Ctrl+B       hotkey-overlay-title="Bluetooth"    { spawn-sh "omarchy-shell shell toggle omarchy.bluetooth"; }
Mod+Ctrl+D       hotkey-overlay-title="Display"      { spawn-sh "omarchy-shell shell toggle omarchy.monitor"; }
Mod+Ctrl+W       hotkey-overlay-title="Network"      { spawn-sh "omarchy-shell shell toggle omarchy.network"; }
Mod+Ctrl+P       hotkey-overlay-title="Power"        { spawn-sh "omarchy-shell shell toggle omarchy.power"; }
Mod+Ctrl+Alt+D   hotkey-overlay-title="Calendar"     { spawn-sh "omarchy-shell shell toggle omarchy.clock"; }
Mod+Return       hotkey-overlay-title="Terminal"     { spawn "ghostty"; }
Print            { spawn-sh "omarchy-capture-screenshot"; }
Mod+Escape       hotkey-overlay-title="System menu" { spawn-sh "omarchy-menu toggle system"; }
Mod+Shift+Escape allow-inhibiting=false             { toggle-keyboard-shortcuts-inhibit; }
```

**媒体键重定向到 OSD 脚本（2026-08-25）**：原 niri 裸绑定只改值、不出 OSD。已改为经 Omarchy
脚本来「改值 + 调 `omarchy-osd`」，并加 `hotkey-overlay-title`（在 Super+K 菜单可查）：
`XF86AudioRaiseVol/Lower`→`omarchy-audio-output-volume raise/lower`、`XF86AudioMute`→`... mute-toggle`、
`XF86AudioMicMute`→`omarchy-audio-input-mute`、`XF86MonBrightnessUp/Down`→`omarchy-brightness-display +5%/-5%`。
`playerctl`（播放控制）保留不动——因为 `omarchy-shell media` 在本移植上是 `unhandled`（接 prev/next 会坏）。
ODS 已确认在 niri 渲染（`omarchy-osd -i volume-high -p 40` + grim 截图）。依赖 `brightnessctl`（见 §8 第 15 条）。

### 5.4 niri 平铺/焦点/工作区键位（用户自定义方向键方案）

已移除 niri vim 键（`Mod+H/J/K/L`），改用方向键；`Mod+K`/`Mod+Ctrl+L` 让给 Omarchy：

```kdl
Mod+Left   { focus-column-left; }            // 向左移动
Mod+Right  { focus-column-right; }           // 向右移动
Mod+Up     { focus-window-up; }              // 垂直聚焦
Mod+Down   { focus-window-down; }
Mod+Page_Down { focus-workspace-down; }      // 下一个工作区（按编号）
Mod+Page_Up   { focus-workspace-up; }        // 上一个工作区
Mod+Ctrl+Up    { move-window-to-workspace-up; }   // 窗口移到上一工作区
Mod+Ctrl+Down  { move-window-to-workspace-down; } // 窗口移到下一工作区
Mod+Ctrl+Left  { move-column-left; }         // 列左移
Mod+Ctrl+Right { move-column-right; }        // 列右移
Mod+O          { toggle-overview; }          // 总览（Mod+O 保留）
Mod+Tab repeat=false { toggle-overview; }    // 总览（用户指定 Super+Tab）
```

### 5.5 仍未改绑定的 Omarchy 键（保留 niri 原生 tiling）

这些 Omarchy 默认键仍被 niri 平铺/窗口占用，未强行覆盖，如需再让出可后续处理：
- `Mod+comma` / `Mod+Period`（consume / expel-column）
- `Mod+Ctrl+R`（reset-window-height）
- `Mod+Tab`（Omarchy 为 Next workspace，现让给 niri overview —— 用户指定）

**已让出（2026-08-31）**：`Mod+Escape` 从 inhibitor 逃生键改回 Omarchy 的 System menu
（`omarchy-menu toggle system`），逃生键挪到 `Mod+Shift+Escape`（`allow-inhibiting=false`，
抑制激活时仍可用）。`Super+Alt+K`（Tmux keybindings）与 `Super+Ctrl+K`（Herdr keybindings）
因本机不用 tmux/herdr，不再绑定。

### 5.6 窗口边框色跟随 Omarchy 主题（A+C 的 C 层）

Omarchy 的 look'n'feel（`looknfeel.lua`）默认把 gaps/rounding/动画/layout 全注释掉走 Hyprland
默认值，style 真正落到合成器上的只有**窗口边框色**：生成的 `theme/hyprland.lua` 里
`active_border_color` / `inactive_border_color`（catppuccin 为 `#89b4fa` / `rgba(595959aa)`）。

niri 上这个颜色由 `focus-ring` 块决定（模块化拆分后位于 `~/.config/niri/layout.kdl`，§5.7）。
`omarchy-niri-apply-theme`（Python）读当前 `theme/hyprland.lua`，把 `active-color`/`inactive-color`
就地写进 `focus-ring`（Hyprland 的 `rgba(rrggbbaa)` 归一化成 niri 的 `#rrggbbaa`），并备份。
默认只写不重载：重载会重置 niri 的运行时覆盖（如 SCALE 按钮改的 scale/mode），所以换色在下次
`load-config-file`/重启时生效。

```sh
~/bin/omarchy-niri-apply-theme        # 只写 focus-ring
~/bin/omarchy-niri-apply-theme --reload  # 写 + niri msg action load-config-file
```

换 style 时由 `theme-set.d/10-niri-border` 钩子自动触发（只写，不重载）。

> ✅ **回归已修（2026-09-19）**：模块化拆分（§5.7）把 `focus-ring` 块搬进 `layout.kdl`，而脚本的写入
> 目标一直硬编码 `config.kdl`（`NIRI_CFG`），于是**每次换主题都静默失败**（`no focus-ring block found
> in config.kdl`，退出码 1），窗口边框色自拆分以来一直停在旧值，`theme-set` 才以为"已应用"。
> 修法（不再写死文件名，将来再挪模块也不会断）：
> - **沿 `include` 指令递归**找含 `focus-ring` 的模块（脚本自己走 include 树，与垫片 `cmd_binds`
>   同一思路），找到即写。
> - **支持渐变**：`hyprland.lua` 里 `active_border_color` 可能是 Lua **table**
>   （`{ colors = { "rgba(...)", ... }, angle = 45 }`）而非字符串；niri 没有渐变焦点环，取**首个色站**。
> 验证：`omarchy theme set Tonal-Spot` 后 `layout.kdl` 的 `focus-ring` 变成该主题的
> `active_border_color`（见 §9）。脚本在 `~/bin/`，不在 omarchy 仓库内，故不进 `niri.patch`。

### 5.7 模块化拆分 + 显示/字体/圆角（2026-08-25 调校）

`config.kdl` 已拆成 Omarchy 式模块化：主文件只做编排，大块配置各自 `include`。

**文件结构（`~/.config/niri/`）**

| 文件 | 内容 |
|---|---|
| `config.kdl` | 编排器：`environment` / `spawn` / `animations` / `screenshot-path` + 6 个 `include` |
| `input.kdl` | 输入设备（键盘 / 触摸板 / 鼠标 / trackpoint） |
| `monitor.kdl` | `output "eDP-1"`：分辨率 / modeline / scale |
| `layout.kdl` | gaps / focus-ring / border / shadow / struts |
| `window-rules.kdl` | 逐应用规则 + 全局圆角 |
| `effects.kdl` | 磨砂 blur 参数 + layer-rule（§8.8，2026-08-26 磨砂时追加，注意它也被 include）|
| `binds.kdl` | 全部按键绑定（须包在 `binds { }` 内） |

`include` 路径相对 config 目录，niri 26.04 原生支持。改任意模块后：
`niri validate && niri msg action load-config-file` 热重载。**注意**：只改被 include 的
模块文件不会触发重载（niri 只监听 `config.kdl` 的 mtime），需 touch/改一下 `config.kdl`
或显式 `load-config-file`。

**显示器（monitor.kdl）** — 本机 eDP-1 是 CSO1411 面板，自定义 EDID 把
`2560x1600@60`（cvt -r 时序 268.5MHz）写进基础块 DTD2。调校值：

```kdl
output "eDP-1" {
    modeline 268.50 2560 2608 2640 2720 1600 1603 1609 1646 "+hsync" "-vsync"
    scale 2.0
    position x=0 y=0
}
```

- **只写 `modeline`，绝不写 `mode` 行**：niri 重载时不会重建自定义时序，写了 `mode` 名会
  fallback 回 4K 并报 `GL_INVALID_VALUE`，也更耗电。
- `scale 2.0` 是整数缩放 → X11 应用锐利，且比 1.5/1.6 更大更舒适；逻辑分辨率
  = 2560/2 × 1600/2 = 1280×800。
- 参考邻居 `jianlongliu` 的 `~/Documents/README-vantage.md`（pkexec 可读）：vantage `res`
  三档为 **原生 4K/2.25、均衡 2560×1600/1.5、省电 1920×1200/1.25**。本机最终用
  「均衡模式 + scale 2.0」。

**字体（12px）**

- Omarchy 栏字体（Layer 1）：`~/.config/omarchy/shell.toml` 的 `[font] base-size = 12`。
- GTK 应用字体（GTK3 与 GTK4 要分别设）：`~/.config/gtk-3.0/settings.ini` 与 `~/.config/gtk-4.0/settings.ini` 的 `gtk-font-name = "SF Pro 12"`。GTK4 应用（Nautilus 等）只读 gtk-4.0，两处都要 12，否则 Nautilus 会偏小（曾为 11）。

**窗口圆角（window-rules.kdl）** — 全局规则（无 `match` = 套用所有窗口）：

```kdl
window-rule {
    geometry-corner-radius 10
    clip-to-geometry true
}
```

- `geometry-corner-radius` 为圆角半径（逻辑 px），`clip-to-geometry` 真正裁切内容。半径可调
  （改这里即生效，热重载）。
- 若 CSD 应用（自带圆角标题栏）边角发虚，可在 `config.kdl` 取消注释 `prefer-no-csd`
  （需重启应用）。
- 全屏看视频若也被裁圆角，把该规则收窄（排除全屏）。
- 坑：`niri msg` 没有 `binds` 子命令，验证绑定只能靠 `niri validate` + 干净
  `load-config-file` 重载，不能 `niri msg binds`。

---

### 5.8 Ghostty 磨砂模糊（2026-08-26）

需求：给 ghostty 终端加毛玻璃模糊。niri 上 blur **不能**靠 ghostty 自带的
`background-blur-radius`（niri 不实现 KDE blur 协议，该设置在 niri 上无效），而是用
niri 侧的 `background-effect` 窗口规则 frost 窗口背后的壁纸。

**两处改动**

`~/.config/ghostty/config`（半透明 = blur 的载体）：

```kdl
background-opacity = 0.85      # 必须 < 1.0，否则窗口不透明、模糊无处可显
background-blur-radius = 0     # 关掉 ghostty 自带模糊，避免和 niri 双层模糊
```

`~/.config/niri/window-rules.kdl`（给 ghostty 加 frost）：

```kdl
window-rule {
    match app-id=r#"^com\.mitchellh\.ghostty$"#
    draw-border-with-background false   // 关键：焦点环不再透出
    background-effect {
        xray true                       // 稳定地只模糊壁纸（窗口背后通常就是壁纸）
        blur true
    }
}
```

**根因（诡异现象）**：niri 默认把 focus-ring / border 画成窗口**背后**的实心矩形；一旦窗口
半透明（ghostty `background-opacity < 1`），这层焦点环就会**透过**窗口显示出来——而只有
**选中（聚焦）的窗口**才有焦点环，所以只有它"诡异"，失焦窗口正常。`draw-border-with-background
false` 让 niri 把焦点环画在窗口**周围**而非背后，问题解决（niri FAQ 的 documented 行为；
若仍发虚可再在 `config.kdl` 开 `prefer-no-csd`，需重启应用）。

**生效注意**：ghostty 改 `background-opacity` 会热重载；但 niri 只监听 `config.kdl` 的 mtime
（见 §5.7），改 `window-rules.kdl` 后需 `touch ~/.config/niri/config.kdl` 或
`niri msg action load-config-file` 才会重载。

---

## 6. Niri.qml（QuickShell 数据单例）

核心逻辑：常驻一个 `niri msg -j event-stream` 进程（`SplitParser` 逐行解析 JSON），事件驱动地维护一个
仿 `Hyprland.workspaces` 的模型，供 Bar 的 Workspaces.qml / Bar.qml 使用。
（2026-09-19 之前是每 500ms 轮询 `niri msg -j workspaces|windows|overview-state`；改动缘由与实测见 §8.15。）

- 事件流在**连接时会先重放全量状态**（`WorkspacesChanged` / `WindowsChanged`），之后只推增量；
  所以初始无需额外查询就有完整数据（探针实测：连接后立刻收到这两条）。
- `OverviewOpenedOrClosed` → 直接翻转 `root.overviewOpen`，不再有最多 500ms 的延迟。
- `WorkspacesChanged` / `WorkspaceActivated` / `WorkspacesReordered` / `WorkspaceUrgencyChanged`
  → 触发一次 `niri msg -j workspaces` 全量查询；`WindowsChanged` / `WindowOpenedOrChanged` /
  `WindowClosed` → 同理查 `windows`。事件只带增量（重建窗口计数最省事），且 40ms 去抖把一串事件
  合并成一次查询。
- 断线（niri 重启）→ `onExited` 后 1s 重连；重连即拿到全量状态，无需额外的 resync 逻辑。
- 空载不再每 500ms 起 ~6 个 `niri msg` 进程；实测空载 quickshell 0.07–0.21%、niri 9.6–11.9% 单核。
- `root.workspaces.values[]` 每项含：`niriId, id, name, output, active, focused,
  toplevels.values[]`（`toplevels.values.length` 由 windows 按 workspace_id 计数得出）。
- `root.focusedWorkspace` = 当前聚焦 workspace。
- `root.focusedMonitor` = `{ "name": 聚焦 workspace 的 output }`。
- `root.overviewOpen`（bool）：由事件流推送，供 overview 模糊壁纸插件
  （`shell/plugins/blurwallpaper/`）在打开时重解析壁纸软链（图层本身**常驻映射**，见 §8.16）。
- 写成 `property Process x: Process { id: x; ... }` 形式（匹配 Omarchy Style.qml 惯例），
  并给 StdioCollector 加 `waitForEnd: true`，否则编译报
  "Cannot assign to non-existent default property"。

> 注意：只读数据才走这里。真正执行合成器动作靠 `hyprctl` 垫片。Hyprland 原生模块中
> 用来发信号的 `HyprlandFocusGrab`（target: Hyprland）等其他 import 会继续解析为
> QuickShell 的内建模块，但 niri 数据只喂给 Niri.qml。

---

## 7. 部署步骤（全新环境重现用）

> Omarchy v4 的 `install/` 是**全系统安装器**（udev/snapper/firewall/pacman），
> 出于约束**刻意跳过**，只部署 config/bin/shell 到 home。

1. 克隆仓库（branch `quattro`，4.0.0.alpha）到 `~/.local/share/omarchy`：
   ```sh
   git clone -b quattro --depth 1 https://github.com/basecamp/omarchy ~/.local/share/omarchy
   ```
1b. **锁屏认证（必做，安装器步骤）**：`pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock`
   —— 手工部署漏掉它会让锁屏**直接拒绝执行**（`lock()` 返回 `missing-pam`），详见 §8.18。
2. 写入 `~/bin/hyprctl` 垫片（见 §4），`chmod +x`。
3. 生成 `~/.local/share/omarchy/shell/Commons/Niri.qml` 并追加到 `qmldir`。
4. patch `Bar.qml` / `Workspaces.qml`（见 §3.2），并把自研插件 `shell/plugins/blurwallpaper/` 拷进去。
5. 编辑 `~/.config/niri/config.kdl`：environment 块 + `spawn-sh-at-startup` quickshell + 绑定。
6. 校验并应用：
   ```sh
   niri validate
   niri msg action reload-config
   ```
7. 启动 QuickShell（如需手动，设置 `HYPRLAND_INSTANCE_SIGNATURE=1` 以消除只读警告）：
   ```sh
   HYPRLAND_INSTANCE_SIGNATURE=1 quickshell -n -p ~/.local/share/omarchy/shell
   ```
8. A 层（菜单指向 niri 真配置 + Hyprland 层降级）：
   - patch `default/omarchy/omarchy-menu.jsonc`（§8.6）。
   - patch `bin/omarchy-refresh-hyprland` 加 niri no-op 守卫（§8.6）。
9. C 层（边框色跟随主题）：
   - 写 `~/bin/omarchy-niri-apply-theme`，跑一次写入 `focus-ring`；建
     `~/.config/omarchy/hooks/theme-set.d/10-niri-border`。
10. 更新覆盖层（让上游更新能重放我们的改动）：
    - `git diff > ~/.config/omarchy/niri-port/niri.patch`，`cp shell/Commons/Niri.qml ~/.config/omarchy/niri-port/`。
    - 写 `~/bin/omarchy-niri-repatch`，建
      `~/.config/omarchy/hooks/post-update.d/10-niri-repatch`。
    - 每次 `omarchy update` 之后钩子自动重放；若冲突（上游改了同一函数）则手动合并（找 Ante）。
11. bar 部件与主题取色（**用户级，抗更新**）：
    - 拷 `~/.config/omarchy/plugins/{yvonne.arch-logo,yvonne.workspaces}/`；装第三方浮栏
      `omarchy plugin add https://github.com/Charlieras262/omarchy-floating-bar.git --yes`，
      再按 `niri-port/plugin-patches/charlieras262.floating-bar.patch` 打 niri 适配（见 §8.11）。
    - 拷 `~/bin/materal-update`、主题 `~/.config/omarchy/themes/tonal-spot/`、钩子
      `hooks/theme-set.d/20-materal`、单元 `~/.config/systemd/user/materal-recolor.{path,service}`
      （`systemctl --user enable --now materal-recolor.path`，见 §8.10）。
12. 共享壁纸库（可选，见 §8.12）：`~/omarchy-wallpaper-aio/setup.sh <壁纸库目录>`，再为**仓库层**主题
    手工补 `ln -s`；库目录要先存在（脚本不建目录、不含图）。

---

## 8. 已知缺口、待办与专题记录

1. **CLI 依赖已装**：`jq` / `satty` / `inotify-tools` 已用 `pkexec pacman -S --needed jq satty inotify-tools` 装好
   `wl-clipboard`（`wl-copy`/`wl-paste`）系统自带，`swappy`（可选截图编辑器）仍缺，非核心。
   Omarchy 的 `bin/` CLI 脚本（截图、剪贴板等）此前因缺 jq 报错，现已正常。
   另装 **`qt6-imageformats`**（`pkexec pacman -S --needed qt6-imageformats`）：提供 Qt 的 webp
   图像插件（`libqwebp.so`）。此前缺它，Qt Quick 无法解码 Omarchy 的 `.webp` 壁纸 → 桌面背景全黑，
   bar 用 QML 渲染所以正常。这是"没有壁纸"的真正根因。
1b. **壁纸/背景已修**（2026-08-24）：除装 `qt6-imageformats` 外，两处代码改动——
   - `shell/plugins/background/Background.qml`：`readlinkProc` 回调改用 `transitionBackground("",p,p,true,true)`
     （force+instant）。避免切换主题时 `currentBackground` 已等于链接目标、而 `displayedBackground`
     还停在已删除的过渡快照上被短路卡死；强制让实时背景链接始终覆盖。
   - `bin/omarchy-theme-set`：`set_theme_background` 的 `background themeTransition` 改为传**实际背景文件**
     （old/new），不再传会被 `sleep 3`+`rm` 提前删除的 `next-/previous-*.webp` 快照，消除异步加载竞争。
   - 验证：`grim` 截图底部条带出现波纹高光像素（壁纸已显示）。
2. **`hyprctl` 垫片本轮修复**：`monitors` 输出补上 `activeWorkspace.id` 与 `transform`，并把
   `width`/`height` 修正为物理分辨率（`format_geo` 需 `width/scale` 得逻辑尺寸）。
   这修复了 `omarchy-capture-region` 的 `active_workspace()` 取空 → `""|tonumber` 报错。
   同时修正 `_focused_output_name()`：niri `focused-output` 输出形如 `Output "..." (eDP-1)`，
   原正则 `^[^:]+` 无冒号时吞掉整行，现改为提取末尾括号。
3. **快捷键重映射已按用户方案落地**（2026-08-24）：tiling 改成方向键方案、移除 vim 键，
   `Mod+K`=keybindings、`Mod+Ctrl+L`=锁屏 让给 Omarchy。`Mod+Ctrl+R`/`Mod+comma`
   仍被 niri 占用，待后续让出。**`Mod+Escape` 已于 2026-08-31 让出**（改回 System menu，
   逃生键挪至 `Mod+Shift+Escape`，见 §5.5）。
4. **显示器缩放 SCALE 生效**：`omarchy-hyprland-monitor-scaling` → `hyprctl eval hl.monitor(...)` 被
   `_eval_monitor` 处理。原实现把 `mode`+`scale`+`position` 塞进**一次** `niri msg output`，而 niri
   一次只能接受一个 action，导致整条命令失败、scale 不生效（字体大小走 shell 内部所以正常）。
   现拆成独立多次 `niri msg output` 调用，并**跳过 `mode`**（Omarchy 重发当前 `WxH@Hz` 会被 niri 拒绝，
   且输出本就在该模式上）。验证：1.5→1.6 生效。
5. **hyprctl schema 精度**：个别 Hyprland-only 字段可能是占位值；如遇脚本异常再补映射。
6. **锁屏**：niri 侧 `Super+Alt+L`（swaylock）与 Omarchy `Mod+Ctrl+L`（`omarchy-system-lock`
   → `omarchy-shell lock lock`）两条路线并存；后者依赖 QuickShell 的 `omarchy.lock` 插件，
   在 niri 上是否真正锁住待实测。
7. **TUI 编辑器启动已修**：`omarchy-launch-tui` 原本走 `uwsm-app`+`xdg-terminal-exec`（Hyprland/uwsm
   组件，niri 会话没有），导致菜单 "Edit config file" 点了无反应。已回退到 `ghostty`（匹配 niri
   `Mod+Return` 终端），实测链路通（ghostty 打开→运行→退出）。
   **菜单指向已由 A 层重定向到 niri 真配置**（见 §8.6），不再打开 `~/.config/hypr/*.lua` 空文件。
8. **A+C 落地 / 更新覆盖层（2026-08-24）**：本节最后两项。
   - **§8.6 A 层（菜单指向 niri 真配置 + Hyprland 层降级）**。
   - **§8.7 更新覆盖层（上游更新自动重放我们的移植改动）**。
9. **system 开关已修并统一标准化（2026-08-25）**：菜单 `system.logout/reboot/shutdown` 走 `omarchy-system-*`，
   原实现依赖 Hyprland/uwsm，niri 上失灵。已新增**单一统一入口 `~/bin/omarchy-niri-system`**：三个脚本的
   niri 分支都 `exec omarchy-niri-system <logout|reboot|shutdown>`，它统一做 OSD 提示 + 优雅关窗 +
   免密分发（以下动作全部免密，见提权结论）：
   - `logout` → `niri msg action quit --skip-confirmation`（不吃 niri 的 Super+Shift+E 确认框，合成器退出 → greetd 回登录页）。
   - `reboot` → logind D-Bus `Manager.Reboot`；`shutdown` → logind D-Bus `Manager.PowerOff`（均经
     `busctl --system call`,免密）。
   - `omarchy-niri-system` 对非法参数退出 2、非 niri 退出 1（已测）；3 脚本 + 分流器 `bash -n` 通过；
     覆盖层 patch 含这 3 个文件（共 11 个），stash 往返重放验证干净。
   - 非 niri 分支保留原 Hyprland 实现（`uwsm stop` / `systemd-run --user … systemctl …`）。
   - **提权结论（实测）**：logout/reboot/shutdown **均免密**。区分两层接口：
     `systemctl reboot`（systemd1，polkit `allow_active=auth_admin_keep`，需 root、且本会话无 polkit 认证
     agent 弹不出框）→ 需提权；但 **logind**：`login1.reboot/power-off`（`allow_active=yes`）、
     `login1.manage`（terminate，`auth_admin_keep`→需密码）。故用 logind D-Bus `Manager.Reboot/PowerOff`
     （免密）配 `niri msg action quit`（免密）；不用 `Session.Terminate`（manage 门控、要密码）。
     已验证：logind 会话 `Active=yes`（seat0），`pkcheck --process $$` 对 `login1.reboot/power-off` 返回
     exit 0（已授权），`login1.manage` 返回 auth_admin_keep（需认证）。
   - **根因：reboot/shutdown 之前"执行不了"= `loginctl` 没有 `reboot`/`poweroff` verb（2026-08-25 修）**：
     `loginctl` 帮的是 session/user/seat 管理，电源动作属于 `systemctl`（systemd1）。dispatcher 里写的
     `loginctl reboot` 运行时日志报 `loginctl[pid]: Unknown command verb 'reboot', did you mean 'help'?`，
     service 以 status=1/FAILURE 退出，机器自然不重启。已改为 `busctl --system call … Manager.Reboot b false`
     与 `Manager.PowerOff b false`（签名 `b`=interactive，`false` 免提示）。`loginctl reboot` 根本不会走到提权
     那一步；改完才真正用上 `login1.reboot/power-off` 的 `allow_active=yes` 免密。
   - **dispatch 必须先调度再关窗（2026-08-25 修复）**：最初 `omarchy-niri-system` 是「先 close-all 再同步
     `loginctl`」——一旦 close-all（或父进程/Quickshell 退散）把跑动作的进程杀掉，reboot/shutdown 就到不了
     （用户实测「执行不了」）。已改为**先把动作 detach 调度好，再 close-all**：logout 用
     `nohup … niri msg action quit --skip-confirmation`（保留会话 env；`--skip-confirmation` 去掉 niri 的
     Super+Shift+E 确认框，注销时不再弹确认、直接回 greetd），reboot/shutdown 用 `systemd-run --user --on-active=3s`
     调 logind D-Bus `Manager.Reboot/PowerOff`（`busctl --system call`,免密）。已验证 `systemd-run --user`
     （用户管理器里的进程，`user@1001.service/app.slice/run-*.service`）对 `login1.reboot` 授权
     `pkcheck --process <该进程pid>` return 0（免密仍成立），瞬时定时器机制可用。即使脚本被关窗杀掉，
     动作也会按计划落地。
   - **实测证据（未触发真实重启/关机，未破坏会话）**：`bash -n` 通过；`busctl --system call … CanReboot` 返回
     `s "yes"`、`CanPowerOff` 返回 `s "yes"`（logind 允许）；同结构 dry-run：`systemd-run --user --on-active=2s`
     → busctl `CanReboot`，3 秒后落地返回 `s "yes"`（证明 detach 链端到端可用）。真实 Reboot/PowerOff 仍需用户触发。
   - **排查日志**：`omarchy-niri-system` 会写 `${XDG_RUNTIME_DIR:-/tmp}/omarchy-niri-system.log`
     （记录 `reboot/shutdown scheduled`、`windows closed` 等步骤）；若仍未生效可查该文件与
     `journalctl --user -b` 中 logind 相关条目。
   - **待运行实测**：logout/reboot/shutdown 需在真实会话触发（会结束本会话/重启），留给用户验证。
10. **overview 背景与桌面不一致（需求，2026-09-03 已修）**：niri 总览（`Mod+O` / `Mod+Tab` 触发
    `toggle-overview`）的背景原本是**不透明深色**，与桌面壁纸不一致。
    - **根因**：overview 开启时 `niri msg layers` 只有 `omarchy-background` + `omarchy-bar`，没有其它
      填充层；把 `config.kdl` 的 `layout { background-color "#ff00ff" }` 设成品红并 `load-config-file`
      后 overview 背景仍是深色——说明深色垫层由 niri 合成器自行绘制、压在 layer-shell 壁纸之上，
      **不吃 `background-color`**，无法靠配置复用桌面壁纸。
    - **修复**：改由移植自有插件在 overview 期间自绘背景 —— `shell/plugins/blurwallpaper/`
      （id `omarchy.blurwallpaper`，kind `service`）渲染强模糊壁纸；该图层**常驻映射**（`visible: true`），
      由 niri 只在 overview 内合成，时序因此和窗口动画一致（§8.16）。`effects.kdl` 给该 namespace 配
      `place-within-backdrop true`；`Niri.overviewOpen`（2026-09-19 起由事件流推送，见 §8.15）现仅用于
      打开时重解析壁纸软链。
11. **电池面板 POWER PROFILE 区为空（2026-08-25 已修）**：系统电源后端是 **TLP**（`tlp` + `tlp-pd`
    `1.10.2`），**不是** power-profiles-daemon —— `powerprofilesctl` 不存在，而 Omarchy 的
    `omarchy-powerprofiles-list`/`-set` 硬依赖它，故电池面板的 POWER PROFILE 区读不到任何 profile（空）。
    修复：在 `~/bin/` 放同名适配脚本（PATH 优先于仓库、挺过 `omarchy update`），**优先**用
    `powerprofilesctl`，缺则回退 D-Bus `net.hadess.PowerProfiles`（`/net/hadess/PowerProfiles`，
    `.ActiveProfile` 可写、`.Profiles` 为 `a{sv}`）。实测：
     - list 返回 3 个 profile（performance/balanced/power-saver），`--active-state` 正确标出 active（power-saver）。
     - set 写入经 `busctl set-property` 生效，但 tlp-pd 是**异步**经 detached TLP 应用，立即读会是旧值，
       需稍等再读。当前活跃 profile 会随电源动态变化（见下）。
     - **层级与动态策略（2026-08-30 核对）**：TLP 策略配置是**系统级** `/etc/tlp.conf`（root），
       **无用户级配置**（`~/.config/tlp*` 不存在）。关键项 `TLP_PROFILE_AC=BAL`（插电→balanced）、
       `TLP_PROFILE_BAT=SAV`（电池→power-saver/low-power，`PLATFORM_PROFILE_ON_SAV=low-power`）。
       故当前活跃值**随电源动态切换**（插电=balanced、电池=power-saver），不是固定值。用户级只有
       `~/bin/omarchy-powerprofiles-{list,set}` 适配脚本——它们仅经 `busctl` 读写 D-Bus
       `net.hadess.PowerProfiles`（由 tlp-pd 翻译执行），**不写 `/etc/tlp.conf`、不持久化**，重启后回落到
       `/etc/tlp.conf` 静态策略。
12. **Super+K 键位菜单只剩 2 条（第二次复发，2026-08-25 晚已修）**：同日早些时候修过一次
   （垫片 `cmd_binds` 从解析 Hyprland 改为解析 niri 配置，见 §4）；晚上配置模块化拆分（§5.7）后
   **再次复发**——根因是 `_config_bindings()` 只读 `config.kdl` 本体找内联 `binds { }` 块，
   而键位已整体搬进被 include 的 `binds.kdl` → 解析为空 → 菜单只剩脚本里写死的 2 条
   static_bindings。修复：垫片加 `_niri_config_lines()` 递归展开 `include`（防再拆文件再断）。
   验证：`hyprctl binds` 129 条记录、`omarchy-menu-keybindings --print` 恢复 131 条、
   clients/devices 无回归；备份 `~/bin/hyprctl.bak-20260825-211843`。
13. **Ghostty 磨砂模糊（2026-08-26 已修）**：见 §5.8。niri 侧 `background-effect {xray true; blur true}`
   给 `com.mitchellh.ghostty` frost 壁纸（niri 不实现 KDE blur 协议，故 ghostty 自带
   `background-blur-radius` 在 niri 上无效、且关掉避免双层模糊）。根因坑：niri 默认把焦点环画在
   窗口**背后**的实心矩形，半透明窗口会把它透出来，且**只有聚焦窗口有焦点环** → 只有选中窗口
   "诡异"。`draw-border-with-background false` 让焦点环画在窗口周围解决。ghostty
   `background-opacity = 0.85` 提供半透明载体。

14. **菜单 Apps 列表启动全部失灵（2026-08-27 已修）**：菜单 "Apps" provider 经
   `shell/services/AppLibrary.qml` 的 `launch()` 启动桌面应用，原实现写死
   `uwsm-app -- gtk-launch <id>.desktop`。niri 会话没有 `uwsm-app`（与 `omarchy-launch-tui`
   当初缺 `uwsm-app`/`xdg-terminal-exec` 同一类问题），导致**菜单里所有应用都点不开**——不只是
   Zen，用户用 Zen 试出来的。`launch()` 已改为 `uwsm-app` 存在才用、否则回退 `gtk-launch`：
   `if command -v uwsm-app >/dev/null 2>&1; then uwsm-app -- gtk-launch ...; else gtk-launch ...; fi`。
   `gtk-launch` 在 niri 上可用且按 `.desktop` ID 解析（实测 `gtk-launch zen-browser.desktop`
   成功起 Zen）。**`gtk-launch` 与工具箱无关**：Qt / Electron / GTK / EFL 等任意框架应用都只是跑其
   `.desktop` 的 `Exec=`，niri 看到的是 Wayland surface，框架不影响启动——只要 `.desktop` 合法、
   应用自身能跑 Wayland/X11 即可（个别 Qt 应用若不能自动探测 Wayland，需 `QT_QPA_PLATFORM=wayland`，
   那是应用自身行为，不是菜单启动链的问题）。改动已追加进 `niri-port/niri.patch`
   （reverse-check 通过），重启 Quickshell 生效；已推到 `github.com/jianlongliu/omarchy-on-niri`。
   - **Zen 强制走 Wayland（2026-08-27）**：菜单拉起 Zen 经 `gtk-launch zen-browser.desktop`，
     原 `.desktop` 的 `Exec=zen-browser %u` 无 Wayland 标志，在 niri 上会落到 XWayland
     （实测 XWayland 进程一直在跑）。已在用户级 `~/.local/share/applications/zen-browser.desktop`
     放覆盖版（优先于 `/usr/share/applications/`，且不在仓库内、不会被 `omarchy update` 或 zen 包更新覆盖），
     每个 `Exec` 加 `env MOZ_ENABLE_WAYLAND=1`。实测进程环境含 `MOZ_ENABLE_WAYLAND=1` +
     `WAYLAND_DISPLAY=wayland-1`，niri 看到 App ID `zen-browser`（Wayland 真客户端，非 XWayland 的 `zen`），
     已脱离 XWayland 路径。要彻底关 XWayland 可在 `config.kdl` 加 `xwayland enable false`
     （需确认无其它 X11 应用依赖）。
15. **brightnessctl 授权安装 + 背光权限（2026-08-25）**：媒体键 OSD（§5.3）依赖
    `brightnessctl` 调背光，但该工具**未装**（这是背光键不生效的根因，非权限问题）。
    已用户授权装系统级：`pkexec pacman -S brightnessctl` + 新建
    `/etc/udev/rules.d/90-backlight.rules`（`SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`）+
    `usermod -aG video yvonne` + 对既有 `intel_backlight` 节点手动 `chgrp video`/`chmod 0664`
    （udev `trigger` 只发 `change`、不重挂 group/mode，故手动兜底直到下次冷插拔）。
    验证：`niri msg action spawn -- brightnessctl --class=backlight set +10%` 改变 76→126→恢复；
    无需重登即生效。**注意**：这条打破了 §1 的"不装系统包"约束，属用户明确授权的唯一例外；
    `echo > $brightness` 对 yvonne 仍 EACCES，brightnessctl 走非 setuid 路径。回滚：
    删 udev 规则 + `usermod -G` 挪出 video + 卸 brightnessctl。
16. **GitHub 发布流程（2026-08-25 建立）**：移植差分推到 pub 仓库
    `github.com/jianlongliu/omarchy-on-niri`（PUBLIC，默认分支 `quattro`）。要点：
    - 本地 working clone 在 `/home/yvonne/omarchy-on-niri`（独立的临时构建仓库，
      **不是** LIVE 的 `~/.local/share/omarchy`——后者保留未提交工作树改动，避免破坏
      `git pull --ff-only`）。
    - push 走 **SSH**（`gh auth git-credential` 走 https 会弹密码，不可用）。
    - gh 以 **jianlongliu** 身份操作（hosts/config 已拷进 `~/.config/gh`）；ed25519 密钥 +
      known_hosts 在 `~/.ssh`。
    - 重推流程：`git clone git@github.com:jianlongliu/omarchy-on-niri.git`（分支 `quattro`）→
      改 → `git commit` → `GIT_SSH_COMMAND="ssh -o BatchMode=yes" git push origin quattro`。
    - 仓库结构含 `port-bin/`（含 hyprctl 等 6 个 override）、`niri-config/`+`shell.json`、`hooks/`、
      `install.sh`（非破坏引导，用户明确不要自动化拼装脚本，见 user-environment 记忆）、`docs/`、`README.md`。
    - 非单机即开即用：每台机器要核 monitor 输出名、背光设备、电源后端(TLP/PPD)、niri 版本。

17. **迁移到主账户 jianlongliu 系统级 vs 用户级（2026-08-30 梳理）**：本移植目前在用户
    `yvonne` 下，日后要迁到主账户 `jianlongliu`。按配置层级归类，迁移时对照：
    - **系统级（已在这台机器、跟用户名无关，无需重复做）**：
      - TLP 电源策略 `/etc/tlp.conf`（`TLP_PROFILE_AC/BAT`，见 §8 第 11 条）——跟随 `tlp`+`tlp-pd` 服务。
      - `brightnessctl` 包 + `/etc/udev/rules.d/90-backlight.rules` + `video` 组（见 §8 第 15 条）。
      - niri 本体 `/usr/bin/niri`、greetd/dms-greeter。
    - **用户级（在 yvonne 家目录，迁 jianlongliu 要带过去）**：
      - `~/.config/niri/*.kdl`（6 个模块，含 effects.kdl，见 §5.7）。
      - `~/.config/omarchy/`（仓库 LIVE + `niri-port/` + `extensions/omarchy-menu.jsonc` + `hooks/`）。
      - `~/bin/*` 适配脚本：`hyprctl`、`omarchy-niri-apply-theme`、`omarchy-niri-system`、
        `omarchy-niri-repatch`、`omarchy-powerprofiles-{list,set}`、media-key 相关等。
      - 用户级 `.desktop` 覆盖：`~/.local/share/applications/zen-browser.desktop`（Wayland 强制）。
      - omarchy 仓库设置依赖：`~/.config/gh`（jianlongliu 身份）、`~/.ssh` ed25519 密钥。
    - 注意：`.desktop`、`gh` 身份、`~/.ssh` 等本就以 jianlongliu 为主，迁移到主账户反而更自然；
      需重点核对的是 niri/omarchy 配置与 `~/bin` 脚本是否与具体用户绑死。

18. **弹窗未给浮栏让位（TODO，下次修）**：toast（`shell/plugins/notifications/Service.qml` 的
    `barClearance`）与 `KeyboardPanel` 家族面板（`shell/Ui/KeyboardPanel.qml` 的 `gap`）按固定 bar
    高度算边距、**不计入 `floatGap`**，浮栏（§8.11）启用后这些弹窗的顶边会压住 bar 底缘约 8px。
    首选修法：在这两处各加一个 `barEdgeMargin` 项（`KeyboardPanel.qml` 已在 `niri.patch` 内，
    会让 patch 从 17 个文件涨到 19 个）。零仓库改动的替代：让垫片把 `Style.gapsOut` 报得更大，
    代价是面板间距一起变大。验证：打开托盘面板，量顶边是否 ≥ bar 底缘（物理 y ≈ 80）。

19. **耗电/续航专项（2026-09-19 测过一轮，下次接着做）**：表现为"感觉慢 + 续航差"。已排除的
    不实线索与已确认的疑点记在这里，避免重查。
    - **不实线索**：`/proc/pressure/io` 55–68% 是 **i915 翻页等 vblank**（D 状态扫描点名
      `kworker/*+i915_flip`，30 秒内 104/120 次），不是磁盘——nvme0n1 期间 0 IOPS、0% 忙。空载壳层
      也便宜：quickshell 1.6%、niri 2.0%，CPU/内存 PSI≈0。浮栏磨砂的功耗差**量不出**（见下方纪律）。
    - **底噪**：静态屏（终端切到不可见工作区）8.4–9.5W，背光仅 15%（74/496）、wlan power_save=on、
      GPU RC6 97–98% → 屏幕与 GPU 都不是大头，仍有 2–3W 说不清。
    - **主疑点：深睡 C-state 缺失**。`cpu0/cpuidle` 只有 `POLL/C1_ACPI/C2_ACPI/C3_ACPI`，C6+ 全无；
      `intel_idle` 内建且 `max_cstate=9`，但启动日志只有 ACPI 的 "Monitor-Mwait will be used to enter
      C-1/C-2/C-3 state" → intel_idle 没接上。**2026-09-19 已排除"平台档位压的"**：用户切到
      `balanced/BAT` 后（`cpuinfo_max_freq` 回到 4800000、`no_turbo=0`、platform_profile=balanced）
      深睡依然只有 C1–C3。下次从 BIOS 的 C-States/深层睡眠 + `sudo turbostat --quiet --show
      PkgWatt,Pkg%pc2,Pkg%pc6 --interval 5 --count 3`（pc6 恒 0 即坐实）入手。
    - **次疑点：屏幕链路**。cmdline 强制 `drm.edid_firmware=eDP-1:edid/CSO1411.bin`（256 字节手写
      EDID，DTD1 写的是 3840x2400@60/595MHz，被 i915 标 "dangerous"）+ `i915.enable_psr=1` +
      config.kdl 自定 cvt-r modeline → 可能让 eDP 链路一直不休眠（估 0.5–1.5W）。属用户显示配置，
      动前先问。
    - **小项**：常驻 `zerotier-one` + `mihomo` + `beszel-agent` + 蓝牙（~0.3–0.8W）；Synaptics 指纹
      阅读器 USB `control=on` 未自动挂起（可进 TLP USB allowlist）。
    - **反直觉待测**：省电档（12W cTDP-down，主频顶 1200MHz）让同一交互任务跑 2.5× 时间长，
      **每任务能量可能反而更高**。测法：固定任务（开合菜单 22 次）在 balanced 与 power-saver 下
      各量 ∫功率 dt，比 Wh 而非比频率；切档不需要 root——`net.hadess.PowerProfiles` 的
      `ActiveProfile` 属性可写（tlp-pd 提供），也可 `omarchy-powerprofiles-set battery <profile>`，
      能脚本化成轮内交替的 A/B。
    - **测量纪律（血泪）**：放电功率 90 秒内单调漂移 ~1.4W（两轮分别 +1.29W / −0.50W，符号相反）
      → **<1W 的差不信**，必须轮内交替、多轮取均，且别比跨轮绝对值（同配置两轮 8.95W vs 9.53W）。
      agent 自己的 TUI（ante+ghostty）活跃时 ~40% 核心、400+ 唤醒/秒并把 GPU 拽出 RC6（未隐藏：
      RC6 47%、i915 中断 779/s；隐藏后：98%、~60/s）→ 测量时务必把终端切到不可见工作区、输出写文件
      （niri 不合成未聚焦工作区上的窗口）。`i915` 中断数不是帧数代理；`i915_flip` 的 D 时长会被自己
      脚本里的 `subprocess.run` 阻塞放大，只有中位数可用。

20. **换主题时 `omarchy-theme-set-browser-policy` 因 sudo 要密码失败**（日志成片
    "a password is required"）→ Chromium 系主题色不跟着变；`materal-recolor` 也因此在 2026-09-19
    02:01 失败过一次。下次查上游是否预期 polkit/sudoers 放行，或我们这层该跳过这一步。

### 8.6 A 层：菜单指向 niri 真配置，Hyprland 层降级

Omarchy 有两层配置，只有层1在 niri 上真正生效：
- **层1（与合成器无关，生效）**：`~/.config/omarchy/shell.json`+`shell.toml`、`theme/*` 生成的
  配色/终端/编辑器配置（Omarchy 视觉来源）。
- **层2（Hyprland 耦合，niri 上是死配置）**：`config/hypr/*.lua` + `hyprsunset.conf`，niri 用
  `~/.config/niri/config.kdl`，故层2不驱动任何可见行为。

`omarchy-menu.jsonc` 下列项现指向真实文件（`$HOME/.config/niri/config.kdl`）而非空 `~/.config/hypr/*.lua`：

| 菜单项 | 原→新 action |
|---|---|
| `style.hyprland`（label 改 "Niri"）| `looknfeel.lua` → `config.kdl` |
| `setup.monitors` | `monitors.lua` → `monitor.kdl` |
| `setup.keybindings`（移除 hypr 文件存在守卫）| `bindings.lua` → `binds.kdl` |
| `setup.input`（移除守卫）| `input.lua` → `input.kdl` |
| `setup.config.hyprland`（label 改 "Niri"）| `hyprland.lua` → `config.kdl` |
| `update.config.hyprland`（label 改 "Niri Theme"）| `omarchy-refresh-hyprland` → `omarchy-niri-apply-theme` |
| 三个 `*hyprsunset*` 项 | 加 `"when":"false"` 隐藏（niri 无 hyprsunset）|

- **模块化注意（2026-08-27 修正）**：niri 配置已拆成 `include` 模块化
  （`monitor.kdl` / `binds.kdl` / `input.kdl` / `layout.kdl` / `window-rules.kdl` / `effects.kdl`），
  根 `config.kdl` 只剩 `include`。原 setup 三项曾错误地全指向 `config.kdl`（打开是空壳），
  现已分别指向 `monitor.kdl` / `binds.kdl` / `input.kdl`——通过**双保险**：
  仓库 `default/omarchy/omarchy-menu.jsonc`（进 `niri.patch`）+ 用户级
  `~/.config/omarchy/extensions/omarchy-menu.jsonc` override（仓库外、热更新、挺过 `omarchy update`）。

`bin/omarchy-refresh-hyprland` 加守卫：`XDG_CURRENT_DESKTOP=niri` 时直接 `exit 0`（打印提示并跳过），
不再把整棵死配置树重建进 `~/.config/hypr/`。菜单 JSONC 修改用 string-aware 注释剥离 + 尾逗号容差
校验通过（326 顶层条目）。

- **Override 必须带 label+icon（2026-08-27 修）**：菜单合并走 `MenuModel.js` 的 `mergeMenuSources`，
  每项经 `normalizeItem` 做 `label: value.label || id`——若 override 只写 `action`，label 会 fallback
  成 id（如 `setup.monitors`），且合并时**覆盖**默认项里真实的 label，导致菜单显示成原始 id 而非
  "Monitors"/"Keybindings"。故 `extensions/omarchy-menu.jsonc` 里对默认项做 override 时，必须把
  `label`+`icon` 一起带上（从 `default/omarchy/omarchy-menu.jsonc` 复制）。这 3 个 setup 项已补全，
  实测合并后 label 正确、action 指向模块化文件、图标正常。Trigger 子菜单那 7 个 toast override 目前仍是
  action-only（同隐患，会显示成 `trigger.toggle.*` 之类 id），用户确认"别的都可以"故暂未动。

### 8.7 更新覆盖层：上游更新后自动重放

- `omarchy update` = `git pull --ff-only`（`omarchy-update-dev`，在 `post-update` 钩子**之前**）+ 迁移。
- **仓库外不碰**：`config.kdl` / `shell.json` / `~/bin/hyprctl` 都不在 omarchy 仓库内，`git pull` 动不到。
- **仓库内会撞**：我们改了仓库内 **17 个文件**（`launch-tui`、`launch-editor`、
  `launch-floating-terminal-with-presentation`、`refresh-hyprland`、`theme-set`、`menu.jsonc`、
  `qmldir`、`Background.qml`、`Bar.qml`、`Workspaces.qml`、`Menu.qml`、`KeyboardPanel.qml`、
  `osd/Osd.qml`、`AppLibrary.qml`，以及 2026-08-25 加的 3 个 `omarchy-system-{logout,reboot,shutdown}`）
  ——这 17 个文件正是 `niri.patch` 的内容（`17 个文件 / 32 个 hunk`；2026-09-18 合并上游时为 30，
  2026-09-19 菜单自愈守卫 +2，见 §8.14）。
  上游改到其中任何一个，`git pull --ff-only` 会因本地未提交改动而**失败中止**整个更新——这是需要
  手动合并的情况。
- **不在 patch 里的新增文件**：`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/` 是**未跟踪**
  文件，不会出现在 `git diff` 里，所以重放必须单独 `cp`（见下第 2 步）。
- **工作树里另有 238 条"有意删除"**（2026-09-19）：仓库自带主题删掉 21 个（含 `catppuccin-latte`），
  只留 `catppuccin`——用户只要 `tonal-spot` + `catppuccin`，`themes/` 从 64M 降到 1.2M。
  `omarchy-theme-remove`（§3 提到的官方脚本）**只管用户层主题**，仓库层只能直接删。
  内容没丢：git 对象还在，恢复一条命令 `git checkout -- themes`（或单个 `themes/<slug>`）。
  代价：若上游改动这些主题，`git pull --ff-only` 会因本地删除而中止——按同样办法恢复对应主题后重试。
- **自动重放**：`post-update.d/10-niri-repatch` 在每次更新后跑 `omarchy-niri-repatch`：
  1. 把 `~/.config/omarchy/niri-port/Niri.qml` 拷回 `shell/Commons/`。
  2. 把 `~/.config/omarchy/niri-port/plugins/*` 拷回 `shell/plugins/`（目前只有 `blurwallpaper/`）。
  3. `git apply` `niri.patch`；已应用则 `--reverse --check` 判 no-op（幂等）。
  4. 冲突则**不做任何改动**、退出码 2，提示手动合并（找 Ante）。
  5. 再跑一次 `omarchy-restart-shell`。上游更新会换掉 shell 的 QML，但**运行中的 Quickshell 仍执行旧代码**；
     上游 `omarchy-update-restart` 只问要不要重启电脑（读 `reboot-required`、内核版本），**不会重启壳层**，
     所以这一步必须我们自己做。niri 上可用（脚本经 `~/bin/hyprctl` 垫片 dispatch，实测 pid 会变、
     菜单/bar 正常）。
- **第三种情况：上游改到我们 patch 内文件的"其他区域"（2026-09-19 首次遇到，见 §8.13）**：`--ff-only` 会被
  本地未提交改动挡住（`error: Your local changes to the following files would be overwritten by merge`），
  但其实只需处理**那一个文件**：`git stash push -- <该文件>` → `git merge --ff-only origin/quattro` →
  `git stash pop`（3 方合并；区域不重叠就会打印 `Auto-merging` 并干净合并）→ 再
  `git apply --reverse --check niri.patch` 确认补丁仍精确等于工作区。
  **不要**为了更新去 `git checkout -- .`：我们另有 238 条"有意删除"（主题），那会白恢复 64M。
- 说明：覆盖层脚本只处理"上游没改到我们文件"的更新（此时 FF 成功、重放是 no-op）；
  "上游改到同一函数"才需要我重新翻译合并——这是任何移植都绕不开的兜底。

**覆盖层一致性自检**（改完 patch 后必做，否则幂等判断会失真）：

```bash
cd ~/.local/share/omarchy
git apply --reverse --check ~/.config/omarchy/niri-port/niri.patch && echo "patch 与工作区一致"
```

`--reverse --check` 通过 = patch 精确等于当前工作区改动；只有这种情况幂等/重放逻辑才成立。

### 8.8 视觉磨砂（frosted Quickshell / 状态栏面板毛玻璃）

niri 26.04 的 `background-effect` + Quickshell 的 `ext_background_effect` 形状磨砂，让 Omarchy shell
的卡片呈毛玻璃。设计原则：**绝不让 niri 侧对整面 layer-shell 做全屏模糊**（那会把整个屏幕霜化），
而是每个面板用 `BackgroundEffect.blurRegion` 只磨砂自己的卡片区域。

**仓库内改动（已进 `niri-port/niri.patch`；2026-09-18 合并上游 `d174d4a` 后整份 patch = 17 个文件 /
30 个 hunk，2026-09-19 起 32 个 hunk（菜单自愈守卫，§8.14）；`--reverse --check` 通过）**：
- `shell/plugins/menu/Menu.qml`：加 `import Quickshell.Wayland._BackgroundEffect`，根 `PanelWindow`
  挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`。
- `shell/Ui/KeyboardPanel.qml`：同上，根 `PanelWindow` 挂
  `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`。**所有 bar 弹窗面板**
  （audio/bluetooth/clock/dropbox/monitor/network/power/tailscale/weather + agent 面板）都复用
  `KeyboardPanel`，所以这一处改动统一磨砂了它们全部（一次覆盖 9+ 面板）。
- `shell/plugins/osd/Osd.qml`（2026-08-31 新增）：**OSD 不用 blurRegion，改用"卡片大小 surface"**。
  官方版是全屏透明 `PanelWindow`（`anchors` 四边铺满），niri 的 layer-rule blur 会把它整面霜化
  （表现为"OSD 弹出时全屏变糊"）；且 Quickshell 的 `blurRegion` 在 niri 上 region 几何跟踪异常
  （实测把磨砂区域放大到约 2.6 倍），也不可靠。改为：`PanelWindow` 用
  `anchors { left; right; bottom }` + `margins`（左右按 `Quickshell.screens[0].width` 居中、底部
  `Style.space(67)`）+ `implicitHeight: card.height`，让 layer surface 本身就是卡片大小，
  卡片 `BorderSurface` 保留显式宽高、去掉居中 anchors，背景 `Color.menu.background`（透明度跟随
  `shell.toml [menu] background-alpha 0.7`）。这样 `effects.kdl` 的 blur 天然只磨砂卡片。
  实测（scale 2.0 物理 px）：屏幕主体 0 差异、卡片 556×130 物理（278×65 逻辑）居中底部、磨砂生效。

**仓库外 Layer-1 配置（pull 安全，不在 `niri.patch` 内）**：
- `~/.config/niri/effects.kdl`（被 `config.kdl` `include`）：全局
  `blur { passes 4; offset 3.5; noise 0.03; saturation 1.6 }` + layer-rule：
  - `^omarchy-osd$` / `^omarchy-notifications$` → `background-effect { blur true; xray true }`
    （只磨砂背后壁纸；`omarchy-osd` 因 Osd.qml 已是卡片大小 surface，blur 只盖卡片）。
  - `^omarchy-keyboard-panel$` → `background-effect { xray false }`（**只设 xray，不设 `blur true`**——
    Quickshell 已发卡片形状区域，该区域就是唯一磨砂范围，全屏 surface 不会霜化）。`xray false` =
    磨砂卡片背后的**实时窗口**（真毛玻璃）；`xray true` = 只磨砂壁纸。
  - `^omarchy-blurwallpaper$` → `place-within-backdrop true`（overview 模糊壁纸插件，§8 第 10 条）。
  - `^omarchy-bar$` → `background-effect { xray false }`（**只设 xray**，同 keyboard-panel；用户明确不要 xray）。
    浮栏得**半透明**才有霜面可看：`shell.toml [bar] background-alpha 0.45` 喂 `Color.bar.background`，而浮栏插件
    的 `Bar.qml` 不再把该 alpha 强制成 1（niri 补丁第 5 处，§8.11）。
    **圆角区域由客户端下发**：补丁给 bar 的 `PanelWindow` 挂
    `BackgroundEffect.blurRegion: Region { item: barBackground; radius: root.effectiveCornerRadius }`（第 4 处），
    niri 于是只糊 bar 那块**圆角矩形**——这才是"四角亮晕"的正解（niri 采样合成画面、把 bar 自己的填充糊出圆角，
    Hyprland 的 `ignore_alpha` 无等价物，niri issue #1554 未修）。早先（同日早些时候）只是把该 namespace 从
    layer-rule 里摘掉来回避，代价是 bar 没有霜面。
    **实测**：角上 `(17,17)`/`(20,20)` 与不磨砂时**逐像素相同**（无晕）；栏内 `(25,17,20) → (97,95,109)`
    （真透出背后并被模糊）；blur 开/关平均差 3.68、最大 26，同一状态连拍两次差仅 0.07（可复现）。
    透明度是唯一的手感旋钮：`shell.toml [bar] background-alpha`（0.45 现值；调高更暗更清晰、调低更透更糊）。
- `~/.config/omarchy/shell.toml`：`[bar]` background-alpha 0.45、`[popups]` 0.65（原 0.8，
  只为透出磨砂；越低越糊、越高字越清晰）、`[menu]` 0.7、`[notifications]` 0.85、`[tooltip]` 0.85。
  这些喂给 `Color.*.background`（`Color.qml` 的 `composed(...-alpha...)`）。

**热重载**：niri `blur`/layer-rule 经 `niri msg action load-config-file`（热）；QML 改动需重启
quickshell：`pkill -x quickshell && niri msg action spawn -- quickshell -n -p $OMARCHY_PATH/shell`。
`effects.kdl`/`shell.toml` 是 Layer-1，上游 `git pull` 动不到，天然抗更新。

**注意**：`xray false` 是 niri 实验特性——窗口开/关动画、拖拽平铺窗口时磨砂会短暂消失（已知特性，
非 bug）。要稳定（只磨壁纸）就把 `omarchy-keyboard-panel` 那条 layer-rule 的 `xray` 改 `true`。

**验证**：面板开/关截图，屏幕底部清晰度 on/off ≈ 0.995（一致）→ 确认无全屏霜化；仅卡片区域变化。

---

### 8.9 上游合并基线（`43bfe9b` → `d174d4a`，2026-09-18）

首次把上游 342 个提交并入在线安装。**不跑整包 `omarchy update`**：它携带引导器、网络栈与 `/etc` 级
改动（清单见 §8.9.3），违反 §1。采用的流程是「先 FF、再重放移植、最后按类处置迁移」。

**8.9.1 合并与覆盖层重建**

```bash
cd ~/.local/share/omarchy
git fetch --depth=400 origin quattro        # --depth=50 会挂起，须给长超时
git stash push -u -m "niri-port pre-merge"
git merge --ff-only FETCH_HEAD              # 基线是上游直系祖先，无需真合并
git stash pop                               # 冲突集中在这一步

# 解决冲突后，把工作区改动固化成新的覆盖层
git add <已解决的冲突文件>                    # 必须归位 unmerged，否则 git diff 导出不全
git diff HEAD > ~/.config/omarchy/niri-port/niri.patch
git reset                                   # 还原为「未暂存」，保持 pull 前置状态

# 必做自检：patch 必须精确等于工作区改动，否则幂等判断失真
git apply --reverse --check ~/.config/omarchy/niri-port/niri.patch
```

未跟踪的移植文件（`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/`）与上游新增路径不冲突，
合并后原样存活；但它们**不在 `git diff` 里**，因此 `omarchy-niri-repatch` 必须单独 `cp`（见 §8.7）。

**8.9.2 冲突与处置**

| 文件 | 上游改动 | 移植处置 | 理由 |
|---|---|---|---|
| `bin/omarchy-theme-set` | 背景切换改为三分支快照结构，新增 `BACKGROUND_TRANSITION_SNAPSHOTS` | 采用上游结构；各分支回退到持久文件 `${OLD_BACKGROUND_SNAPSHOT:-$old_background}`，并在 `choose_staged_theme_background` 调用处加 `XDG_CURRENT_DESKTOP != niri` 守卫 | 上游开关只对**视频**壁纸关快照，修不了 niri 竞态：快照约 3s 后被删除，而 QML 仍异步加载该路径 → 黑桌面 |
| `default/omarchy/omarchy-menu.jsonc` | 新增 `setup.security.sudoless-docker` 等条目 | 保留上游新条目；重新应用 niri 侧改动（`setup.config.hyprland` → 指向 `config.kdl`、标签 "Niri"；`hyprsunset` 保持 `"when":"false"`） | 菜单是上游与移植共同维护面，逐项合并而非整文件取舍 |

其余 9 个上游同样改过的移植文件（`Bar.qml`、`Osd.qml`、`Menu.qml`、`Background.qml`、
`KeyboardPanel.qml`、`Workspaces.qml`、`AppLibrary.qml`、`Commons/qmldir`、
`omarchy-launch-floating-terminal-with-presentation`）**自动合并**，无需人工介入。

**8.9.3 迁移分类处置**

手工部署的安装没有迁移历史（`~/.local/state/omarchy/migrations/` 为 0/121），直接 `omarchy-migrate`
会重放全部历史。处置办法：**先把 121 条全部标记为已应用，再只摘下要执行的**。

```bash
cd ~/.local/share/omarchy
export OMARCHY_PATH=$PWD XDG_CURRENT_DESKTOP=niri
STATE=$HOME/.local/state/omarchy/migrations

for f in migrations/*.sh; do touch "$STATE/$(basename "$f")"; done   # 全部标记
while read -r m; do rm -f "$STATE/$m"; done < run-list.txt            # 只摘出批准项

# 逐条执行：单条失败不影响其余（omarchy-migrate 一条失败会中止整批）
while read -r m; do
  if bash -euo pipefail "migrations/$m" >"/tmp/miglogs/$m.log" 2>&1; then
    touch "$STATE/$m"; echo "OK   $m"
  else
    echo "FAIL $m"; tail -1 "/tmp/miglogs/$m.log"
  fi
done < run-list.txt
```

| 类别 | 条数 | 处置 | 理由 |
|---|---|---|---|
| 纯配置类（只改 `$HOME`） | 32 | **执行** | 与系统底层无关 |
| 安装类：Cloudflare CLI `cf` | 1 | **执行** | 用户指定只装 `cf` |
| 需 root / 改系统底层 | 44 | 保留标记，**不执行** | 会顶掉 systemd-boot（`1789325478` 装 `linux-omarchy` 并设为 Limine 首启动项）、重建 initramfs（`1786482992`/`1784917531`/`1786605598`/`1784476564`）、退役 systemd-networkd（`1782002156`）、关 sshd 密码认证（`1788124236`）、删 `/etc/sudoers.d` 与 `/etc/systemd/system` 下退役文件（`1788025225`）、要求本机未配置的 Omarchy 签名仓库（`1787589206`/`1784672586`/`1787399318`/`1786952219`）——均违反 §1 |
| 安装额外 CLI | 12 | 保留标记，**不执行** | 用户只要 `cf`；Basecamp 系与各编码 agent 不用 |
| 交互式提问 | 1（`1786549201`） | 保留标记，**不执行** | 非交互环境会挂起 |
| 本机不适用 | 1（`1785608166`） | 保留标记，**不执行** | 修 `omarchy-sleep-lock.service` 单元；本机无此单元（Omarchy 的 systemd 集成，niri 侧未使用），永远不可能成功 |

执行结果：**33 条实跑，30 条一次通过**；2 条因缺 `mise` 失败（`1787215483`、`1789095456`），装上
`mise` 后重跑通过。最终 `omarchy-migrate --pending` 为空，后续 `omarchy update` 不会重放历史。

**特权通道**：`pkexec` 免密可用；`sudo -n` 不可用（需密码）。`omarchy-pkg-add` 经 `sudo pacman`，
非交互必失败——**需要装包的迁移在本机一律走不通**，只能改用 `pkexec pacman -S`。

**8.9.4 新增系统依赖**

| 包 | 用途 |
|---|---|
| `vi`（+ `ex-vi-compat`） | 上游 `install/omarchy-base.packages` 显式列出的基础包；`omarchy-menu-tmux-keybindings` 等会调用 `vi` |
| `qt6-multimedia` + `qt6-multimedia-ffmpeg` | 视频壁纸：`shell/Ui/BackgroundMedia.qml`、`BackgroundVideo.qml` |
| `mise` | `~/.local/bin` 下 agent wrapper 的执行后端。上游从**自家仓库**装 `mise-bin`；本机未配置该仓库，改取 Arch `extra` |

**8.9.5 合并后配置状态**

| 项 | 状态 |
|---|---|
| `~/.config/omarchy/shell.json` bar 布局 | 被上游默认覆盖：center = `indicators, clock, keyboard-layout, weather, system-update`；right 新增 `agents`。**用户接受该默认并自行重新定制**，故不留兼容层 |
| 第三方 bar 部件 | `charlieras262.omablur`、`ryuhzk.ime` 保留；`local.opencode-go`、`io.github.alexinslc.calendar-agenda` 由**用户自行删除**，勿从备份恢复 |
| `~/.local/bin` agent wrapper（约 20 个） | 迁移 `1784909971`、`1787573629` 把**原本已存在**的 wrapper 重写为新模板；**未新装任何 CLI**。它们是 `install/user/mise.sh` 的默认集，装上 `mise` 后**首次被调用时**才下载（惰性） |
| 备份 `~/.config/omarchy/niri-port/backups/20260918-pre-merge/` | 当日快照（含 `~/.config/{omarchy,niri,tmux,kitty,foot}` 打包），**仅作回滚参考，不是要复原的目标状态** |

---

### 8.10 主题动态取色（tonal-spot / matugen / materal-update）

需求：换壁纸 → 整个 Omarchy 配色（bar / 菜单 / 终端 / 窗口边框）跟着壁纸走。参考对象是
`github.com/jianlongliu/omarchy-like-niri` 里的 `tonal-spot` 主题（matugen 跑 Material 3 的
tonal-spot 方案），**下放**到本机、不是照抄那台机器。全部落在用户层，`omarchy update` 碰不到。

**四件组成**

| 件 | 路径 | 作用 |
|---|---|---|
| 主题 | `~/.config/omarchy/themes/tonal-spot/` | `matugen.toml`（`scheme="tonal-spot"`、`mode="dark"`）+ `colors.toml` + `backgrounds/` + shell/alacritty 模板 |
| 生成器 | `~/bin/materal-update` | 跑 matugen、映射调色板、重套主题 |
| 钩子 | `~/.config/omarchy/hooks/theme-set.d/20-materal` | 换 theme 后重新取色 |
| 单元 | `~/.config/systemd/user/materal-recolor.{path,service}` | 盯壁纸文件，换壁纸自动重取色 |
| 仓库副本 | `port-bin/materal-update`、`hooks/theme-set.d/20-materal` | 随 INSTALL 第 2/5 步安装；那对 systemd 单元只在本机，未随仓库分发 |

- 主题的 `backgrounds/` 是我们用 `magick … -quality 90` 从上游 `backgrounds.default/*.png` 生成的
  `.webp`（上游只发 `.default` 变体，不生成则主题没有可用壁纸）。
- **ANSI 16（含 orange/brown）保持静态**（抄上游 catppuccin），刻意不跟随壁纸——终端可读性优先。
- 用户主题不被 `omarchy-theme-set` 的"来自仓库"检查过滤（`~/.config/omarchy` 不是 git 仓库 → 走
  `cp -r …/*` 分支），所以 `matugen.toml` 能进 staged 目录。

**命令**

```sh
materal-update            # 按当前壁纸取色并重套主题（幂等）
materal-update <slug>     # 指定主题 slug
materal-update --force    # 忽略"已匹配"判断
materal-update --no-apply # 只写 colors.toml，不重套主题
materal-update --print    # 只打印推导出的调色板
```

**matugen M3 → omarchy `colors.toml` 的映射**（从参考主题反推，无官方文档）

| colors.toml 键 | matugen 来源 |
|---|---|
| `accent` | `primary` |
| `selection` | `primary_container` |
| `muted` | `on_surface_variant` |
| `background` | `surface` |
| `dark_background` | `surface_container_lowest`（精确命中） |
| `darker_background` | `surface_container_lowest` × 0.82 |
| `lighter_background` | `surface_container_high` |
| `foreground` / `light_foreground` / `bright_foreground` | `on_surface` |
| `dark_foreground` | `on_surface_variant` |
| `hyprland_inactive_border` | `outline` + `aa` |
| `hyprland_active_border` | `primary→tertiary→primary_container` 45deg 渐变（`shell.toml.tpl` 也吃这个 token 当 shell 的 active-border） |

交叉验证：同一张壁纸下我们算出 `primary #98ccf9`，参考主题里提交的是 `#97ccf8`——差 1–2 个色阶。

**四个必须知道的坑**

1. **systemd 用户单元的 PATH 极简**：`omarchy theme set` 用**裸名**调用兄弟脚本
   （`omarchy-theme-set-templates`、`omarchy-hook`、`omarchy-restart-*`），而移植的 helper 在 `~/bin`。
   PATH 不全时主题"应用成功"，但 staged 目录里只有主题自带的文件——**没有生成的 `shell.toml` /
   `hyprland.lua` / `alacritty.toml`，钩子也不跑**，全程静默。故 `materal-update` 自己拼 PATH
   （omarchy bin + `~/bin` + `~/.local/bin` + 继承值）并设 `OMARCHY_PATH`。
2. **`PathChanged=<符号链接>` 跟随目标**：改写图片会触发，**改链接指向不会**（`/tmp` 隔离实验确认）。
   所以 path 单元要同时盯 `…/current/` 和 `…/current/background` 两条。
3. **`omarchy theme set` 默认把壁纸推进到主题的下一张**，于是"重取色 → 重套主题 → 又换壁纸"永远追不上，
   生成器描述的总是一张旧图。`materal-update` 用 `OMARCHY_THEME_SKIP_BACKGROUND=1` 关掉这个行为。
4. **幂等判据必须是壁纸的 sha256，不能看 mtime**：staging 会重拷主题背景，时间戳每次都变。

**验证（2026-09-19 实跑）**：`omarchy theme bg next` → path 单元触发 → 服务运行 → staged `colors.toml`
与推导一致、`shell.toml` 已生成、`focus-ring` 已更新、state 文件写入、无残留 guard；重复运行输出
"already matches"（no-op）；`omarchy theme set catppuccin` → `omarchy theme set Tonal-Spot` 钩子同样生效。
像素抽查：近黑壁纸下 bar 填充 (16,19,24) vs 壁纸 (18,20,27)、logo 峰值 (226,226,232)（B−R = 6，中性）。

### 8.11 bar 插件层（胶囊工作区 / Arch logo / 浮栏）

三件事都是**用户层插件**，放在 `~/.config/omarchy/plugins/`（仓库外 → `omarchy update` 碰不到，
`niri.patch` 也不必为它们加 hunk）。bar 结构仍由 `~/.config/omarchy/shell.json` 决定。

**1. 胶囊式工作区指示 —— `yvonne.workspaces`**（manifest 记 `omarchy.clonedFrom: omarchy.workspaces`）

- 数据：`Niri.workspaces.values[]`（`id` 是 niri 的 `idx`），占用判定 `toplevels.values.length > 0`。
- 样式：GNOME 式——每个 workspace 一个圆点，**聚焦的点横向拉伸 2.6×**；四级 alpha 全部取自
  `barForeground`（空 0.15 / 有窗 0.62 / 聚焦 0.9 / 悬停 0.85–1.0），所以是**单色**而不是 accent 色。
- 点击：走 `hyprctl` 垫片的 `hl.dsp.focus({ workspace = "N" })`。
- 坑：`implicitHeight: barSize` 必须写，否则该 slot 会顶到 bar 上沿。

**2. Arch logo —— `yvonne.arch-logo`**（普通 bar-widget）

- 左键 `omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'`；右键 `xdg-terminal-exec`。
- SVG 必须是纯 `#ffffff`：`MultiEffect.colorization` 是**按源图亮度相乘**着色，带灰度的 logo 会发暗。
- 菜单面板仍能挂载，是因为 `omarchy.menu` 带 `keepLoaded: true`——按钮不在 bar 上，面板也活着。

**3. 浮动 bar —— 第三方 `charlieras262.floating-bar`**

- 来源 `https://github.com/Charlieras262/omarchy-floating-bar.git`，`omarchy plugin add <url> --yes` 安装。
- **启用方式是 `shell.json` 的 `bar.id = "charlieras262.floating-bar"`**，不是 enable/disable 开关——
  所以 `omarchy plugin list` 里它永远不显示 enabled，别据此判断没生效。
- niri 适配 **6 处**：4 处是 Hyprland 独占调用 → 垫片/niri 等价物；2 处是磨砂相关（`Bar.qml` 不再把
  `Color.bar.background` 的 alpha 强制成 1、给 bar 的 `PanelWindow` 挂圆角 `BackgroundEffect.blurRegion`，
  见 §8.8）。存档在 `~/.config/omarchy/niri-port/plugin-patches/charlieras262.floating-bar.patch`，
  补丁基线是上游 `Bar.qml` HEAD，已用 `patch -p1` 从上游重建并 `cmp` 验证与实机文件逐字节一致
  （旧版留 `.bak-20260919-preblur`）。`omarchy plugin update` 会用上游版本覆盖工作树，覆盖后要重打这个 patch。
  该补丁**只存在实机**（插件本体仍从上游安装），未随移植仓库分发。
- 参数：`floatGap = 8`（逻辑）、`cornerRadius = 10`、`transparent: false`。
- 几何实测（scale 2.0，物理 px）：bar 占 y 16..79、左缘 x = 16（= 8 逻辑 floatGap，bar 高 32 逻辑）；
  平铺窗口停在 728 = 800 − (32 bar + 8 floatGap + 16 niri gaps)——**niri 在自己的独占区之外又加了一次
  gaps，两者不打架**（像素核对过）。
- 配套改动：`~/.config/niri/effects.kdl` 给 `^omarchy-bar$` 配 `background-effect { xray false }`（浮栏磨砂，
  2026-09-19；模糊区域形状由插件下发的圆角 `blurRegion` 决定，原因与实测见 §8.8）。
- 第三方部件：`ryuhzk.ime` **2026-09-19 被 `ronald.input-sources` 取代**（macOS 式输入源徽章，见 §8.17）；
  `charlieras262.omablur` **已于 2026-09-19 从 `shell.json` 的 right 数组摘掉**
  （插件文件仍留在 `~/.config/omarchy/plugins/`，想加回就把它填回 right 数组；备份
  `~/.config/omarchy/niri-port/backups/shell.json.bak-20260919-032126-pre-omablur`）。
  **它在 niri 上是空转**（2026-09-19 核）：滑块读的是垫子写死的 `hyprctl -j getoption decoration:*`
  （`{"int":12,...}`），应用走 `hyprctl eval 'hl.config({...})'`——垫子对 `hl.config` 是**空操作**（exit 0、不改
  任何东西），持久化还写 `~/.config/hypr/looknfeel.lua`（niri 上已被降级的 Layer-2）。niri 的真值在
  `~/.config/niri/window-rules.kdl` 的 `geometry-corner-radius` 与 `effects.kdl` 的 `blur { passes/offset/... }`，
  改它们 + `niri msg action load-config-file` 才生效。
- 已知待修：toast 与 `KeyboardPanel` 家族弹窗没给浮栏让位（§8 第 18 条）。

### 8.12 共享壁纸库（omarchy-wallpaper-aio）

需求：不想"切个主题就回到那几张自带图"，而是**所有主题共用一套自己的壁纸库**。参考仓库
`github.com/jianlongliu/omarchy-wallpaper-aio`（2026-09-19 由私有转公开；我们克隆在
`~/omarchy-wallpaper-aio`）：只有 `setup.sh` + README，**不含图、不取色**，只做接线。

**机制**：换壁纸时 Omarchy 合并两处（`omarchy-theme-set` 的 `choose_staged_theme_background`、
`omarchy-theme-bg-next`，都用 `find -L <用户层> <主题层> -maxdepth 1 -type f` + 扩展名过滤）：

1. `~/.local/state/omarchy/current/theme/backgrounds/` —— 当前主题自带；
2. `~/.config/omarchy/backgrounds/<当前主题名>/` —— 用户层。

把 (2) 建成**软链**指向壁纸库，于是切到任何主题翻到的都是同一个库（`find -L` 跟随软链）；
往库里丢图即自动出现，不必重跑脚本、不必重建主题。

**本机接法**

```sh
~/omarchy-wallpaper-aio/setup.sh /data/Pictures/Wallpapers                    # 遍历 ~/.config/omarchy/themes/*
ln -sfn /data/Pictures/Wallpapers ~/.config/omarchy/backgrounds/catppuccin    # 仓库层主题，脚本不管
```

| 主题 | 所在层 | 接线方式 |
|---|---|---|
| `tonal-spot` | 用户层 `~/.config/omarchy/themes/` | `setup.sh` 自动建 |
| `catppuccin` | 仓库层 `~/.local/share/omarchy/themes/` | 手工 `ln -s`（脚本只认用户层主题，其 README 亦注明） |

- **库**：`/data/Pictures/Wallpapers`（71 张，全 png/jpg，无子目录）。路径**大小写敏感**
  （`Pictures/Wallpapers`，不是 `pictures/wallpaper`）。该目录属 `jianlongliu`、位于共享数据卷
  `/data`，我们只**读**不写，故不触犯 §1。
- **验证**：用上游同款 `find -L` 合并两个来源 → **75 = 71（库）+ 4（主题自带）**，且库与主题自带
  无同名文件（有重名会让轮换里出现重复项）。
- **还原**：`find ~/.config/omarchy/backgrounds -maxdepth 1 -type l -delete`（只删软链，图不动）。
- **与取色链路的关系**：换图 → path 单元触发 → `materal-update` 重取色（§8.10）。注意
  `materal-update` 把 `current/background` 指向的文件**直接**喂给 matugen、不筛扩展名：库里现在全是图
  没问题；若以后放视频（选择器认 `.mp4/.webm/.mkv` 等），换到视频那次 matugen 会失败、服务非零退出、
  配色停在上一次结果——失败路径**不写 guard**（guard 只在成功写盘后落），不会卡住后续运行。

---

### 8.13 上游小更新（`d174d4a` → `8675600`，2026-09-19）

**当前上游基线 = `8675600`**（§8.9 记的是上一次大合并到 `d174d4a`；那份数值仍是那次合并的记录）。

上游又走了 5 个提交（`8675600` Merge PR #12141 + 4 个），内容全是 **php/laravel 开发环境安装**：
改写 `bin/omarchy-install-dev-env`、`bin/omarchy-remove-dev-env`，以及 `default/omarchy/omarchy-menu.jsonc`
里对应的 4 行（判据从 `omarchy-pkg-present php` 改成 `[[ -d $HOME/.local/share/mise/installs/php ]]`，
laravel 从 `~/.config/composer/vendor/bin/laravel` 改成 `~/.local/bin/laravel`）。**三个文件都不含 QML**，
所以这次更新不需要重启壳层。

- **与我们 patch 的重叠**：只有 `default/omarchy/omarchy-menu.jsonc` 一个文件，且是**不同区域**——
  上游动第 277–282 / 343–350 行，我们的 4 个 hunk 在 108 / 123 / 184 / 364 行（菜单 action 指向
  `niri/*.kdl` 与 `omarchy-niri-apply-theme`）。
- **做法**：走 §8.7 的"第三种情况"——只 `git stash push -- default/omarchy/omarchy-menu.jsonc`，
  FF 拉上游，`git stash pop` 由 git `Auto-merging` 干净合并，无冲突。
- **验收**（全部通过）：`git apply --reverse --check niri.patch` ✓（**补丁基线数值当时不变，仍是
  17 文件 / 30 hunk；同日更晚加上菜单自愈守卫后为 32，见 §8.14**）→ `omarchy-niri-repatch` 报 `already applied`（幂等仍成立）→ 该文件相对 `HEAD`
  的差异**恰为 9+/9-**（= 我们 4 个 hunk，不含上游 php 行），相对 `HEAD~5` 恰为 **13+/13-**
  （= 上游 4+4 与我们的 9+9，**零丢失**）→ 上游新判据落地（第 280 / 347 行）、我们的 6 处 niri 指向仍在
  → `omarchy-install-dev-env` / `omarchy-remove-dev-env` 内**无 hypr/uwsm 耦合**（niri 上不会瘸）
  → 壳层进程健在、日志无错、`grim` 截图 bar 在位（栏内 `(46,61,83)` ≠ 栏外 `(90,111,137)`）。
- **附注（别当 bug 修）**：`omarchy-menu.jsonc` 第 370 行有一个**尾随逗号**，严格 JSON 解析会报
  `Illegal trailing comma`——`HEAD` 与 `HEAD~5` 同在 370 行，是上游原有写法，jsonc/QML 解析器容忍它。
- **238 条主题删除未受影响**：上游这 5 个提交没碰 `themes/`，`--ff-only` 因此不会被本地删除挡住；
  更新后 `git status` 仍是 17 M + 238 D + 3 未跟踪（`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/`、
  `shell/test-debug.qml`）。
- **下次更新的预期**：上游一旦改到我们那 17 个文件里的**同一函数**，`omarchy-niri-repatch` 会以退出码 2
  明确报冲突且不动仓库（见 §8.7），那时才需要手工翻译合并。

---

### 8.14 菜单空白（"Nothing here yet"）的成因与自愈（2026-09-19）

**症状**：bar、壁纸、其它部件都正常，但 `Mod+K` / `omarchy-menu toggle root` 打开的菜单只有一行
"Nothing here yet"；`omarchy-menu ping` 仍回 `ok`，重启壳层后立刻恢复。

**实测复现**（把 `default/omarchy/omarchy-menu.jsonc` 截成半截，即 JSON 不合法）：

| 状态 | OCR 读到的菜单 |
| --- | --- |
| 健康 | 6 个根项（Learn / Trigger / Style / Setup / Remove / Help…） |
| 文件截成 20000 字节 | `Nothing here yet` |
| 恢复完整文件 | 6 个根项（**无需重启壳层**） |

**成因链**：菜单模型 = 仓库 `default/omarchy/omarchy-menu.jsonc`（340 项）+ 用户
`~/.config/omarchy/extensions/omarchy-menu.jsonc`（10 项）合并而来。用户那 10 项都是**覆盖项**，其
`parent` 都指向 default 里的条目；一旦 default 解析失败（读到半截/坏内容时 `parseMenuJsonc` 静默返回
`[]`，而 FileView 是 `printErrors: false`），合并结果只剩这 10 个"孤儿"——根菜单 0 个子项，于是渲染成空
卡片。要点：这是**一次性读取失败**，不是配置损坏；文件再变一次（watcher 触发重读）或重启壳层即可恢复。
2026-09-19 那次正是如此：`omarchy update` 的 pull 正在改写该文件时壳层读到半截内容，之后没有新的文件
事件，就一直空着。

**证据**（临时探针 `console.log("DBGMENU …")`）：正常时 `default loaded items=340` → `merged order=341`；
坏掉时只有 `user loaded items=10` → `merged order=11`（合并后 `items` 是字典，没有 `.length`，探针里
`merged items=undefined` 就是这个原因，不是 bug）。

**根治**（已进 `niri.patch`；`Menu.qml` 2 → 4 个 hunk，整份 patch 30 → 32）：

- `Menu.qml` 新增 `menuHasRootChildren()`：模型里存在 `parent === "root"` 的条目即判健康（顶层条目在
  `MenuModel.js` 里默认落到 `"root"`，jsonc 不写 `parent` 字段）。
- `rebuildItemsFromSources()` 末尾：若"根菜单没有子项"且**并非两个源都还没加载**（`default=0 且 user=0`
  只说明 FileView 尚未回调），则 1.2s 后重读两个 jsonc，最多 5 次（`menuSourceRetries` 计数，健康时归零）。
  健康路径最多在启动瞬间空判一次（源加载顺序所致，代价是重读两个小文件），之后不再触发。
- 实测：健康 → 菜单 6 项、日志无 QML 报错；截断 → 菜单空但可见重试（4 次）；恢复 → 菜单自己回来。

**兜底**：真遇到空白菜单，先 `omarchy-restart-shell`（§8.7 第 5 步）；`post-update.d/10-niri-repatch`
现在也会在每次上游更新后重启壳层。

---

### 8.15 overview 模糊壁纸延迟（500ms 轮询 + 每次重解码）（2026-09-19）

**症状**：`Mod+O` / `Mod+Tab` 打开总览时，深色背板先出来，模糊壁纸要"等一下"才补上，观感像掉帧；
关闭时桌面壁纸同样晚一拍。

**测量方法**（`/tmp/ov_lat.py`）：`grim -g "64,495 350x260" -t ppm` 连拍屏幕左下背板区（逻辑坐标 ——
输出 scale 2.0，`grim -g` 吃逻辑像素，写物理坐标会报 "supplied geometry did not intersect"），
判据取**区域亮度均值**：桌面态恒为 ~33，overview 稳定态 ~110，阈值 90。原因是窗口缩略图不在该区，
背板在"模糊壁纸未到位"时是 niri 画的深色垫层（均值 20–40），只有模糊壁纸真的画上去才会变亮。
（早期用"标准差/锐度"当判据都不行：开启动画与壁纸本身的光滑度都会污染，见 §8.15 备注。）

| | 第 1 次 | 第 2 次 | 第 3 次 | 说明 |
| --- | --- | --- | --- | --- |
| 修复前 | 552 ms | 402 ms | 281 ms | 离散 0–500ms = **轮询抖动** |
| 修复后 | 152 ms | 153 ms | 124 ms | 抖动消失 = 事件驱动 |

**成因两条**：

1. `Niri.qml` 每 500ms 轮询 `niri msg -j overview-state`，`Niri.overviewOpen` 最多晚 500ms 翻转，
   `BlurWallpaper.qml` 的图层随之晚映射 → 上表的离散抖动。
2. 该图层关闭时 unmapped，且 `Image { cache: false }`，每次打开都要**重新解码 + 上传**整屏壁纸
   （4K 源图 → 2560×1600）。

**修复**：

- `Niri.qml` 改为**事件流驱动**（细节见 §6）：常驻一个 `niri msg -j event-stream`（`SplitParser` 逐行解析），
  `OverviewOpenedOrClosed` 直接翻转 `overviewOpen`；workspace/window 类事件触发一次去抖 40ms 的全量查询。
  附带收益：空载时不再每 500ms 起 ~6 个 `niri msg` 进程。
- `BlurWallpaper.qml`：`cache: false` → `cache: true`，解码结果留在共享 pixmap cache，重新映射时只做上传。

**A/B：图层要不要常驻映射**（`/tmp/ov_ab_layer.py`，两种状态各一次 14s 采样）：

| 状态 | 打开延迟 | quickshell CPU | niri CPU | 电池功耗 |
| --- | --- | --- | --- | --- |
| 常驻映射（`visible: true`，用 `Image.opacity` 开关） | 118–138 ms | 0.21% | 11.86% | 13.45 W |
| 关闭时不映射（`visible: Niri.overviewOpen`） | 152–163 ms | 0.07% | 9.57% | 13.46 W |

当时的结论是"保守方案"——常驻映射只快 ~40ms，却让 niri 多烧 ~2% 核、功耗无差别，于是让 surface 依旧随
overview 出现/消失。**该结论已被 §8.16 推翻**：延迟判据只量"亮起来要多久"，量不到"背板与窗口动画的先后
顺序反了"；改成常驻映射后两者同步，代价仍是 ~2% 核、功耗无差别。

**备注（判据的坑）**：`标准差` 判据会在开启动画期间从 24 渐升到 64，看起来像"模糊 183–543ms 才到位"，
其实测的是动画结束；用"合成模糊壁纸"做参考图也不可靠（`MultiEffect` 的 blurMax 24–32 + brightness 0.15
与 PIL 的 `GaussianBlur(24)` 不等价，平均差 53–68 分不开）。最终用**亮度均值**这一单调解即可。

### 8.16 overview 背板与窗口动画错位（"壁纸和窗口是反的"）（2026-09-19）

**症状**（用户肉眼）：打开总览时窗口先动、模糊壁纸后到；关闭时壁纸先消失，缩略图周围露出一圈暗带，
窗口再慢慢展开。

**测量方法**（这次要看的是"**先后顺序**"，不是"延迟"）：

- 密集采样用 `grim -g "<逻辑坐标>" -t ppm`：**ppm 比 png 快约 10 倍**（~30ms/帧 vs 200–300ms/帧）。
- overview 打开期间整屏 `grim` 本身要 ~300ms/帧，所以先把 niri 动画整体放慢再研究顺序：
  `~/.config/niri/config.kdl` 的 `animations { slowdown 12.0 }` + `niri msg action load-config-file`
  （**不必重启壳层**），测完恢复注释状态 `// slowdown 3.0`。
- 判据用 **1/4 全屏截图（`grim -s 0.25`）的平均亮度**：桌面 110.4、我们的背板 127.3、niri 原生暗背板压到 ~55。
- 坑：工作区是动态的，`niri msg action focus-workspace 3` 可能指向根本不存在的号；工作区上有窗口时整屏均值
  被窗口内容带偏（曾因此整轮复测作废）。改层前后对比务必同场次采集。

| | 打开 | 关闭 |
| --- | --- | --- |
| 每次开关都 map/unmap（原实现） | 背板 60–220ms 后才出现，且**一帧内 +48/+49**（硬闪） | 切换后 ~25ms 背板即不见，露出 niri 自己的暗背板 → 缩略图周围一圈暗带；均值 55.4 起步，随缩略图展开 3.3s 才回到 110 |
| 图层常驻映射（现在） | 平滑 +4.4 / +6.7 / +1.6 / +0.8 … → 127.3 | 平滑 127.3 / 125.0 / 122.9 / 121.3 / 117.2 / 114.2 … → 110.4 |

正速（未放慢）复测同一区域 350×260：打开 `33 → 56 → 82 → 87 → 89 → 91 → 93`（2–3 帧淡入，不再是单帧 +48），
关闭 `92 → 77 → 45 → 33`（平滑落回桌面，中间不出现暗背板值 43）。

**成因**：图层按开关 map/unmap。niri 只在 overview 期间合成 backdrop，映射那一帧要重新渲染整屏模糊并提交，
所以打开时晚到、而且是整块出现；关闭时图层立刻消失，而 niri 仍在画自己的暗背板并展开缩略图 —— 于是出现
"窗口还在动、壁纸已经走了"的反向观感。

**修复**：`plugins/blurwallpaper/BlurWallpaper.qml` 里 `visible: Niri.overviewOpen` → `visible: true`。
niri 只在 overview 内合成 `place-within-backdrop` 的图层，所以桌面**逐像素不变**（实测平均差 0.00、最大 0），
时序完全交还给 niri 自己的动画；`Image { cache: true }` 与 `brightness: 0.15` 都不必动。

**代价与副作用**：overview 关闭时 niri 多约 2% 单核（见 §8.15 的 A/B 表，功耗无差异）；`Niri.overviewOpen`
现在只用于"每次打开时重新解析壁纸软链"，换主题后仍能跟上（路径没变是空操作）。

---

### 8.17 输入源徽章（`ronald.input-sources`）+ fcitx5 双源前提（2026-09-19）

第三方 bar 部件，`omarchy plugin add https://github.com/ronaldlangeveld/omarchy-input-sources --enable` 安装
（= `~/.config/omarchy/plugins/` 下的 git 克隆）。纯 fcitx5 / `fcitx5-remote` 实现，**不需要 niri 适配**，
所以 `plugin-patches/` 里没有它；已挂在 `shell.json` 的 `layout.right`（`omarchy.tray` 之后），取代 `ryuhzk.ime`。

**为什么"装完了却看不见"**：`Panel.qml` 里 `available: fcitxAvailable && ims.length > 1` —— 只有**一个**
输入源时部件把自己隐藏（IPC `open` 也毫无反应）。本机原来只有 `rime` 一个源，所以徽章一直不出来；
能配的第二个源只有英文键盘（`keyboard-us`）。

**fcitx5 的两个坑（2026-09-19 实测）**：

1. `~/.config/fcitx5/profile` 由 **fcitx5 自己重写**：手加 `keyboard-us` 条目，`fcitx5-remote -r`
   不重读 group、重启后条目还会被内存状态覆盖掉。**改源只能走 D-Bus**：

   ```
   busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
     SetInputMethodGroupInfo "ssa(ss)" "Default" "us" 2 "rime" "" "keyboard-us" ""
   ```

   签名 `ssa(ss)` = 组名、组默认布局、`(名称, 布局)` 条目数组；成功即写回 profile。
   校验/读回用 `busctl --user -j call … FullInputMethodGroupInfo s Default`（第 2 段是默认源、第 5 段是条目）。
2. **`DefaultIM` 抢不过 keyboard 条目**：只要组里有 `keyboard-us`、组默认布局是 `us`，fcitx5 就把默认源钉在
   `keyboard-us` 上——写 profile 的 `DefaultIM=rime`、清空组默认布局、调换条目顺序都不行（重启后照样被覆盖）。
   也就是说"新输入框从英文开始"是 fcitx5 的设计，不是插件的毛病。

**选定方案**（用户 2026-09-19 选择"保留英文源 + 全局共享输入状态"）：`~/.config/fcitx5/config` 里

```
[Behavior]
ShareInputState=All
```

再 `fcitx5-remote -r`。效果：切一次中文后所有输入框都保持中文（接近 macOS），只有 fcitx5 启动后的
第一个上下文是英文。备份：`~/.config/fcitx5/profile.bak-0428`（加源前）、`~/.config/fcitx5/config.bak-0435`
（改共享状态前）。一键回到单源（徽章随之隐藏）：

```
busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
  SetInputMethodGroupInfo "ssa(ss)" "Default" "us" 1 "rime" ""
```

**隐藏自带的键盘布局部件（2026-09-19）**：装好插件后 bar 上有两个"当前输入法/布局"标记——插件徽章，以及 Omarchy
自带的 `omarchy.keyboard-layout`（时钟右边那个 `EN`）。后者只是 xkb 布局指示（数据来自垫片的 `hyprctl -j devices`），
在插件徽章存在时纯属重复，于是把 `{"id":"omarchy.keyboard-layout"}` 从 `~/.config/omarchy/shell.json` 的
`layout.center` 摘掉（`shell.json` 是用户层、热重载、抗 `omarchy update`；**不要**去动 `$OMARCHY_PATH` 里的部件本体）。
A/B 实测：摘掉后 bar 只有逻辑 x 706..742（宽 36）这一块像素变化——正是那个 `EN`，其余逐像素不动；
备份 `~/.config/omarchy/niri-port/backups/shell.json.bak-20260919-043957-pre-keyboard-layout`，想加回来就把
`{"id":"omarchy.keyboard-layout"}` 填回 center 数组。

**徽章把 rime 显示成「拼」（2026-09-19）**：fcitx 给 rime 的 label 是 `ㄓ`（肉眼看像"羊"），于是给插件加了一层本地映射——
`Model.js` 顶部 `var badgeOverrides = { rime: "拼" }`，`badgeText()` 开头按 IM id 查表（id 就是 fcitx D-Bus 里的 `rime`）。
补丁存档 `~/.config/omarchy/niri-port/plugin-patches/ronald.input-sources.patch`（基线 = 插件 git HEAD，`patch -p1 --dry-run` 验证可从 HEAD
干净重放；`omarchy plugin update` 覆盖工作树后要重打）。插件只有一份副本，就在 `~/.config/omarchy/plugins/ronald.input-sources/`。

**验证**：IPC `open` 后 OCR 到 `Rime` / `Show Emoji & Symbols` / `Show Input Source Name` /
`Open Keyboard Settings…`；`omarchy-shell -q ronald.input-sources next` 在 `rime ⇄ keyboard-us` 间来回切
（`fcitx5-remote -n` 核对）；壳层日志无 QML 报错。可用 IPC：`toggle` / `open` / `close` / `next` / `prev`。
若要绑快捷键，`Mod+Space`（Omarchy 菜单）与 `Mod+Alt+Space`（Apps 菜单）已占用（§5.3），需另挑。
fcitx5 自身由 `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 在登录时拉起（非 systemd 用户单元）。

### 8.18 锁屏"不能锁"：PAM 门禁（手工部署漏了安装器步骤）（2026-09-19）

**症状**：`Mod+Ctrl+L`（以及菜单里的锁屏）毫无反应——不黑屏、不出锁屏界面、没有报错弹窗。

**依赖链（实测）**：锁屏要能工作，系统里必须存在 **`/etc/pam.d/omarchy-lock-password`**。
stock 的 `shell/plugins/lock/Service.qml` 用 `FileView { path: "/etc/pam.d/omarchy-lock-password";
onLoadFailed: passwordPamConfigured = false }` 探测它，然后：

- `beginLock()` 首行 `if (!passwordPamConfigured) { logEvent("lock-denied: missing-pam"); return false }`；
- IPC `function lock(): string { if (!root.passwordPamConfigured) return "missing-pam" … }`。

即**故意拒绝锁屏**，不是"静默失败"：会话锁走 `ext-session-lock-v1`，没有 PAM 就没有任何解锁路径，
锁上等于把自己永久关在外面。第三方锁屏插件（`io.github.sirjul1337.lock-explorer`，manifest
`clonedFrom: omarchy.lock` 的替换关系）是**同款门禁**（其 `Service.qml` 2711/2712 行探测、`lock()` 同判据），
所以"换个锁屏实现"治不了，stock 一样锁不了。

**根因**：该文件由 `bin/omarchy-apply-lock` 写入，而它的调用方只有 Omarchy **安装器**
（`install/config/lockscreen-pam.sh`）与 `omarchy-upgrade-to-quattro`。本移植是手工部署
config/bin/shell（§7 开头的"刻意跳过 `install/`"），这两条都没跑过 → 文件从未生成。
**与 niri 无关、与第三方插件无关**：`omarchy-shell lock status` 当时是 `"passwordPam": false`。

**修法**（一次性，需 root；`/etc/` 不受 `omarchy update` 影响）：

```
pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock     # 或 sudo omarchy-apply-lock 后重启壳层
```

写入的是上游原样的 PAM 栈：`pam_faillock(preauth, deny=10 unlock_time=120)` + `pam_systemd_home` +
`pam_unix(try_first_pass nullok)` + `pam_faillock(authfail/authsucc)` + `pam_env` +
`account include system-local-login`（依赖的 `pam_*` 模块系统自带，已逐个核对存在）。
**验证判据**：`omarchy-shell lock status` 的 `"passwordPam"` 由 `false` → `true`，随后按 `Mod+Ctrl+L` 真人实测。

**顺带上游 bug（`omarchy-apply-lock` 的指纹误判）**：脚本用
`fprintd-list "$user" | grep -qi finger` 判断"是否注册过指纹"，而**未注册**时 fprintd-list 的输出是
`User <name> has no finger**s** enrolled for …` —— 同样命中该 `grep`。于是没指纹也会生成
`/etc/pam.d/omarchy-lock-fingerprint`，锁屏会去敲一条永远不成功的指纹路径。本机已 `pkexec rm -f` 删掉
（`lock status` 的 `fingerprint`/`fingerprintConfigured` 均为 `false`）；判据应改成排除 `no … enrolled`
或解析 fprintd 的条目/退出码。

**与 dms-greeter 无关（同时排除）**——两者用**不同的 PAM 服务**，物理上不重叠：

| | 用途 | PAM 服务 | 谁写 |
|---|---|---|---|
| dms-greeter | 登录 | `/etc/pam.d/greetd`（howdy `pam_python.so` + `/usr/local/bin/ir-light` + `system-local-login`） | dms-greeter 自带的 PAM sync；其二进制字符串只提 `/etc/pam.d/greetd`，且"externally managed → skipping DMS greeter PAM sync" |
| 锁屏 | 会话锁 | `/etc/pam.d/omarchy-lock-password` | `omarchy-apply-lock`（安装器/升级） |

- greeter 跑**自己的 niri 实例与配置**（`/etc/greetd/niri/config.kdl`：`DMS_RUN_GREETER=1`、黑底、
  **没有** `spawn-at-startup quickshell`），不加载我们的壳层；`/etc/greetd/config.toml` 是 `jianlongliu`
  的 0600 文件（读不到，也没碰）。
- 时序也对不上：`passwordPam:false` 在**发起锁屏之前**就成立，装插件前即如此。

**迁移/重装注意**：同一台机器上**换账户不需要重跑**（`/etc/pam.d/<服务名>` 是全机共享的，
`pam_unix` 认的是锁屏界面里输入的用户名）；但**换机器或重装必须重跑**——它是安装器步骤，
`install.sh` 现在会检测缺失并打印命令（见 §7 步骤 1b）。

**旁证：`niri --session` 那堆进程不是第二个会话**。`ps` 里成排的 `niri --session`（comm
`Command Spawner`、0 CPU、1 个 pipe fd、子进程 `<defunct>`）是 niri 自己 `spawn` 命令时的派生辅助进程，
与 greeter、与我们的移植都无关。

---

## 9. 验证清单

- [x] `niri validate` 通过。
- [x] QuickShell 启动无报错（"Configuration Loaded"）。
- [x] grim 截图：bar 渲染出 workspaces 1-5、"3"高亮、时钟、EN/安 键盘布局、日历弹窗。
- [x] `omarchy-menu toggle` 开/关根菜单（截图确认，rc=0）。
- [x] hyprctl 垫片查询与 dispatch 均工作。
- [x] `jq` / `satty` / `inotify-tools` 安装（pkexec）。
- [x] `omarchy-capture-region` / `omarchy-capture-screenshot` 无 jq 报错（monitors 补 activeWorkspace 后）。
- [x] `jianlongliu` 未被触碰（mtime 未变）。
- [x] 键位重映射：方向键方案 + `Mod+K`/`Mod+Ctrl+L` 让给 Omarchy（`load-config-file` 重载后）。
- [x] 背景壁纸显示：`qt6-imageformats` + QML/theme-set 修复后，`grim` 见波纹像素。
- [x] A 层：菜单项全部指向 `config.kdl`（不再出空文件），`omarchy-refresh-hyprland` niri no-op。
- [x] C 层：`omarchy-niri-apply-theme` 写入 `#89b4fa`/`#595959aa`，`niri validate` 通过、热重载 OK。**2026-08-30 查出：§5.7 模块化后 `focus-ring` 移入 `layout.kdl`、脚本仍写 `config.kdl` → 静默失效；2026-09-19 已改为"沿 `include` 定位 + 渐变取首色站"并重验（见 §5.6）。**
- [x] 更新覆盖层：`omarchy-niri-repatch` 幂等（已应用判 no-op；stash 还原后能干净重放）。
- [x] `theme-set`/`post-update` 钩子触发正常、非 niri 静默跳过。
- [ ] 截图/剪贴板 CLI 全链路实测（slurp/grim 交互，需桌面环境）。
- [x] **锁屏 PAM 门禁（2026-09-19）**：定位到"锁不了"的真因是手工部署漏了安装器步骤 →
  `/etc/pam.d/omarchy-lock-password` 不存在，`lock()` 直接返回 `missing-pam`（stock 与第三方插件同款门禁）；
  `pkexec omarchy-apply-lock` 补上后 `lock status` 的 `passwordPam` = `true`；顺带删掉被上游 `grep -qi finger`
  误判生成的 `omarchy-lock-fingerprint`，并排除 dms-greeter（它只写 `/etc/pam.d/greetd`）（见 §8.18）。
- [ ] Omarchy 锁屏（`Mod+Ctrl+L`）在 niri 上**真人**实测：锁上 → 输密码解锁（PAM 文件已就位，未按过键）。
- [ ] 真实跑一次 `omarchy update`，确认上游变更时覆盖层自动重放或明确报冲突。**2026-09-19 部分验证**：手动走了等价的 `git merge --ff-only` 路径（§8.13，上游只改到我们 patch 内文件的"其他区域"），重放幂等成立；官方脚本本身仍没跑过（它要 sudo + snapper 快照 + 包升级）。
- [x] **logout/reboot/shutdown** 统一标准化：`~/bin/omarchy-niri-system` 单一入口（logout→niri quit、reboot/shutdown→logind D-Bus `Manager.Reboot/PowerOff`；`loginctl` 无该 verb 是本 bug，已改；`pkcheck` 免密 exit 0 验证）。
- [x] **电源 profile**：`~/bin/omarchy-powerprofiles-list` 返回 3 个 profile、active 标记正确；set 经 TLP D-Bus 生效（异步应用，恢复为 power-saver）。
- [x] **Ghostty 磨砂模糊**：`window-rules.kdl` 给 `com.mitchellh.ghostty` 加 `background-effect {xray true; blur true}` + `draw-border-with-background false`；ghostty `background-opacity = 0.85`、`background-blur-radius = 0`；焦点环穿透"诡异"问题已解（§5.8）。
- [ ] **账户迁移到主账户（§11）**：快照 → 卸 DMS（保留 greeter）→ 原版 niri 默认配置当基座 → 整目录搬运 → 改写 `config.kdl` 三处硬编码路径 → 自检。方案已成文，**尚未执行**（主账户侧需用户本人在场）。
- [ ] 运行实测：注销、关机、重启（会结束会话/重启，交给用户）。
- [x] **overview 背景统一**：`shell/plugins/blurwallpaper/`，图层**常驻映射**、由 niri 只在 overview 内合成（见 §3.1、§6、§8.16）。
- [x] **菜单 override label+icon 修复（2026-08-27）**：`extensions/omarchy-menu.jsonc` 的 3 个 setup 项补全 label+icon，合并后显示 "Monitors"/"Keybindings"/"Input" 且图标正常（不再显示 raw id `setup.monitors` 之类）；根因是 `normalizeItem` 的 `label: value.label || id` 把 action-only override 的 label 退化成 id 并覆盖默认项。
- [x] **视觉磨砂（frosted Quickshell）**：`Menu.qml` + `KeyboardPanel.qml` 挂 `BackgroundEffect.blurRegion`（只磨砂卡片，不全屏）；`effects.kdl` 给 `omarchy-keyboard-panel` 设 `xray false`（实时窗口毛玻璃）；`[popups]` alpha 0.8→0.65。面板开/关屏幕底部清晰度 on/off≈0.995 → 无全屏霜化。
- [x] **浮栏磨砂（2026-09-19）**：`Bar.qml` 保住 `[bar] background-alpha`（不再强制 alpha=1）+ 挂**圆角** `blurRegion`，`effects.kdl` 给 `^omarchy-bar$` 设 `xray false`；实测栏内 `(25,17,20)→(97,95,109)`、四角像素与不磨砂时逐像素相同（无亮晕）、blur 开/关平均差 3.68 且连拍可复现（见 §8.8/§8.11）。
- [x] **媒体键 OSD（2026-08-25）**：`XF86Audio*`/`XF86MicMute`→`omarchy-audio-output-volume`/`omarchy-audio-input-mute`、`XF86MonBrightness*`→`omarchy-brightness-display`，均带 `hotkey-overlay-title`；`omarchy-osd` 已在 niri 渲染确认。
- [x] **brightnessctl 背光**（2026-08-25）：`brightnessctl --class=backlight set +10%` 实测 76→126→恢复；udev 规则 + usergroup 已生效、免重登。
- [x] **上游合并（2026-09-18）**：FF 到 `d174d4a`；2 个冲突已解；覆盖层重建为 17 文件 / 30 hunk，`--reverse --check` 通过、repatch 幂等；shell 在新代码上重启无报错、bar/背景图层正常（见 §8.9）。
- [x] **迁移归零**：121 条全部标记，实跑 33 条（30 通过）；`omarchy-migrate --pending` 为空（见 §8.9.3）。
- [x] **`cf`（Cloudflare CLI）**：`cf --version` → `v0.10.0`（依赖 `mise`）。
- [x] **主题动态取色（2026-09-19）**：`omarchy theme bg next` → path 单元触发 → `materal-update` 重取色并重套主题（staged `colors.toml` 与推导一致、生成了 `shell.toml`、无残留 guard）；重复运行判 "already matches"（幂等）；`omarchy theme set catppuccin` → `omarchy theme set Tonal-Spot` 钩子同样生效（见 §8.10）。
- [x] **C 层回归修复（2026-09-19）**：脚本沿 `include` 找到 `layout.kdl` 的 `focus-ring` 并写入主题色（渐变取首色站），`niri validate` 通过（见 §5.6）。
- [x] **浮栏几何（2026-09-19）**：像素实测 bar 占物理 y 16..79、左缘 x = 16；平铺窗口停在 728 = 800 − (32 bar + 8 floatGap + 16 niri gaps)，niri 独占区与自身 gaps 不打架（见 §8.11）。
- [x] **bar 部件（2026-09-19）**：胶囊工作区（聚焦点拉伸 2.6×、四级 alpha）与 Arch logo 渲染正常，点击经 `hyprctl` 垫片走通（见 §8.11）。
- [x] **主题精简（2026-09-19）**：仓库自带主题删剩 `catppuccin`（含 `catppuccin-latte` 共删 21 个），用户层保留 `tonal-spot`；`omarchy-theme-list` → 只有 Catppuccin / Tonal Spot；覆盖层 `--reverse --check` 仍通过、当前主题与壁纸无断链（见 §8.7）。
- [x] **菜单空白的成因与自愈（2026-09-19）**：截断 `default/omarchy/omarchy-menu.jsonc` 能复现
  "Nothing here yet"（恢复即好）；`Menu.qml` 自愈守卫进 patch（17 文件 / 32 hunk），实测健康 6 项 /
  截断空 / 恢复后不重启也回来；`post-update.d/10-niri-repatch` 末尾加 `omarchy-restart-shell`（见 §8.14）。
- [x] **共享壁纸库（2026-09-19）**：`tonal-spot` 与 `catppuccin` 的 `~/.config/omarchy/backgrounds/<主题>` 均软链到 `/data/Pictures/Wallpapers`；上游同款 `find -L` 合并得 75 张（71 库 + 4 自带）、无重名（见 §8.12）。
- [x] **overview 延迟（2026-09-19）**：`Niri.qml` 改事件流 + `BlurWallpaper.qml` 开 `cache` 后，模糊壁纸到位时间
  由 552/402/281 ms（轮询抖动）降到 152/153/124 ms 且抖动消失；空载只剩 1 个常驻 `niri msg -j event-stream`（父进程
  quickshell），无 QML 报错；胶囊工作区仍随切工作区更新（§8.15；该节的"不常驻映射"结论已被 §8.16 修正）。
- [x] **overview 背板动画同步（2026-09-19）**：`BlurWallpaper.qml` 改 `visible: true` 常驻映射后，背板不再
  单帧硬闪（+48 → 平滑 +4.4/+6.7/…），关闭时不再出现 niri 暗背板的暗圈；桌面逐像素不变（平均差 0.00）；
  代价 ~2% 单核、功耗无差异（§8.16）。
- [x] **输入源徽章（2026-09-19）**：`ronald.input-sources` 挂在 bar 右侧；给 fcitx5 组加上 `keyboard-us` 后
  徽章出现，`omarchy-shell -q ronald.input-sources next` 能在 `rime ⇄ keyboard-us` 间切换（菜单 OCR 确认）；
  组默认源被 keyboard 条目钉死 → 用 `ShareInputState=All` 解决"新输入框变英文"；自带 `omarchy.keyboard-layout`
  （时钟右边的 `EN`）同日从 `layout.center` 摘掉，A/B 只差逻辑 x 706..742 那一块（见 §8.17）；徽章本地映射
  rime → `拼`（`badgeOverrides`，补丁 `plugin-patches/ronald.input-sources.patch`）。

---

## 10. 关键环境信息

- 两个账户**同属用户本人**：`jianlongliu`（uid 1000）是**日用主账户**（当前跑**原生 DMS**：`dms-shell` / `dms-shell-niri` / `dankcalendar-bin` / `greetd-dms-greeter-bin`），`yvonne`（uid 1001, gid 1003, groups `wheel` / `video`）是**专门给本移植做实验**的账户。`/home/yvonne` 是 `drwx------`、`/home/jianlongliu` 是 `drwxr-x---` → 两边户目录互不可读，跨账户操作只能在各自账户内执行（迁移见 §11）。
- niri 26.04 (8ed0da4) 位于 `/usr/bin/niri`。
- 显示管理器：greetd / dms-greeter（DMS 自家 greeter，`/etc/greetd/config.toml` / `niri/dms.kdl` 归主账户所有）。包管理器 paru。
- 电源后端：**TLP**（`tlp` + `tlp-pd` 1.10.2，D-Bus `net.hadess.PowerProfiles`），**无** power-profiles-daemon（`powerprofilesctl` 缺失）。
- 引导：**systemd-boot + Secure Boot，无 Limine**；内核是 stock `linux`（不是上游推的 `linux-omarchy`）。
- 仓库：`core` / `extra` / `multilib` / `archlinuxcn`——**未配置 Omarchy 自家仓库**（所以 `mise-bin`、
  签名强制等迁移在此不适用）。
- 快照：**snapper** 已启用（`root` / `home` / `data` / `opencode` 四个配置，`root` 的 `SUBVOLUME="/"`），pacman 事务前后自动打快照（钩子 `05-snap-pac-pre` / `zz-snap-pac-post`）。
- **特权通道**：`pkexec` 免密可用；`sudo -n` 失败（要密码），`omarchy-pkg-add` 因此非交互不可用。
- `mise` 来自 Arch `extra`（2026-09-09 装），上游用的是自家仓库的 `mise-bin`。
- `XDG_CURRENT_DESKTOP=niri`（移植的 niri 守卫分支据此生效）。
- 读取 `HYPRLAND_INSTANCE_SIGNATURE is unset` 警告仅影响便捷性，QuickShell 在 layer-shell
  下照常渲染。

---

## 11. 账户迁移：实验账户 → 主账户（2026-09-19 方案）

### 11.0 背景与目标

- 两个账户同属一人：`jianlongliu`（uid 1000）是**日用主账户**，`yvonne`（uid 1001）是**专门给本移植做实验**的账户。本节是把移植整体搬进主账户的 runbook。
- 主账户现状：**原生 DMS**（打包的 `dms-shell 1.6.2` + `dms-shell-niri 1.6.2` + `dankcalendar-bin` + `greetd-dms-greeter-bin`，登录界面是 dms-greeter）。
- 目标形态：主账户跑本移植（Omarchy 壳层 + niri），**卸掉 DMS**，niri 配置以**原版默认**为基座（不是从 DMS 那套改）。

### 11.1 先决结论（本机实测）

- **系统层不用重做**：包（`quickshell 0.3.1` / `niri 26.04` / 依赖）、`/etc/pam.d/omarchy-lock-password`（全机共享的锁屏门禁，`omarchy update` 不碰 `/etc`）、udev 背光规则、greetd 都已是机器级。
- **一个会话只能有一个 Quickshell 壳层**：`/usr/lib/systemd/user/dms.service` 是 `Type=dbus` + `BusName=org.freedesktop.Notifications` + `WantedBy=graphical-session.target`，会在**任何** niri 会话自动起并占住通知总线，与移植的 `spawn-sh-at-startup quickshell` 直接抢 → 只能卸，不能并存。
- **卸载级联（`pacman -Rs --print` 实测）**：卸 `dms-shell dms-shell-niri` 只列这两个包；**quickshell 之所以没被当孤儿一起删，是因为 `greetd-dms-greeter-bin` 还依赖它**。若把 greeter 包一并卸掉，`-Rs` 会连 `quickshell` 一起删 → 移植当场崩。要么保留 greeter，要么先 `sudo pacman -D --asexplicit quickshell`。
- **greeter 就是登录界面**：`/etc/greetd/config.toml`（jianlongliu 0600）指向 dms-greeter；卸掉它 = 没有登录界面，只能 TTY 救。备选：已装 `greetd-agreety`（控制台），`greetd-tuigreet` / `greetd-gtkgreet` / `greetd-regreet` 在 extra 里。**本轮不动 greeter**——它与"壳层用哪套"无关，卸它零收益、风险最大。
- **主账户不在 `video` 组**（`video:x:983:greeter,yvonne`）→ 背光写不进去、亮度条失效 → 迁移前 `sudo usermod -aG video jianlongliu`。
- 本机**没有** `hyprland` / `hyprlock` / `uwsm`，也没有 `/usr/bin/hyprctl` → 移植那个 PATH-first 的 `~/bin/hyprctl` 垫片在主账户**不会顶掉任何真东西**；DMS 也不调 `hyprctl`（grep 无命中）。
- **显示分工**（用户定）：分辨率固定 `2560x1600@60`——modeline 写死在 niri 的 `output` 块，唯一来源，不需要开机跑工具；**scale 归 Omarchy bar 的 Monitor 面板**（`niri msg output` 是临时的，所以 output 块里留一个默认值当开机值）。bar 的 Monitor 面板**改不了分辨率**：它发的 `mode` 被垫片故意忽略（见 §5.7 与 §8.8 相关条目）。`vantage`（用户自写的 TUI，`/usr/local/bin`，系统级、无状态、niri 原生）与本迁移无耦合；它的预设自带 scale 1.5，使用时会临时覆盖 bar 设的值。

### 11.2 交付通道（必须先解决）

`/home/yvonne` 是 `drwx------`，**主账户读不到**本仓库与本文档；`/data` 是 `root:data` 且组内只有 jianlongliu，yvonne 也写不进去。所以产物只能走两条路之一：

1. 把 `omarchy-on-niri` 仓库推到远端，主账户 `git clone`；
2. 打包丢到 `/var/tmp`（1777、世界可读、重启留存），主账户就地解包。

### 11.3 主账户侧执行顺序（含回滚点）

1. **快照**（11.4）+ 备份 DMS 家目录配置到 `/data`
2. `sudo usermod -aG video jianlongliu`
3. **卸 DMS**（11.5）
4. **换 niri 基座**：原版默认 + 八类补回（11.6）
5. **搬目录**（11.7）：整份 `~/.local/share/omarchy`、`~/.config/{omarchy,niri}`、`~/.local/state/omarchy`、`~/bin`、systemd 用户单元
6. 改 `config.kdl` 里三处硬编码路径（11.7 末）
7. 重新登录 → 自检（11.8）
8. 稳定后再考虑清理 DMS 残留（11.9）

### 11.4 快照与备份（主账户，需 root）

```bash
sudo snapper -c root create -d "pre-dms-removal"
sudo snapper -c home create -d "pre-dms-removal"
```

- 本机 snapper 有 `root` / `home` / `data` / `opencode` 四个配置；`root` 的 `SUBVOLUME="/"`（含 `/etc`，即锁屏 PAM 文件），`home` 单独一份 → 主账户家目录保得住。
- pacman 钩子已在（`05-snap-pac-pre` / `10-snap-pac-removal` / `zz-snap-pac-post`），装/卸包会自动前后打点；上面两张手打是**保险**（钩子只管受该配置管辖的 pacman 事务）。
- 回滚：`sudo snapper -c root undo <N>` / `-c home undo <N>`。
- 另外把 DMS 的家目录配置单独 tar 一份到 `/data`（`~/.config` 与 `~/.local/share` 里 DMS/Quickshell 相关项）——快照不等于备份，家目录里还有 DMS 的登录态与缓存。

### 11.5 卸载 DMS

```bash
sudo pacman -Rns dms-shell dms-shell-niri dankcalendar-bin
```

- **保留** `greetd-dms-greeter-bin`（见 11.1 的两条理由）。若确实想换成"纯输密码"的登录界面（`agreety` / `tuigreet` / SDDM），按 §11.10 的顺序走：先改 `/etc/greetd/config.toml` 并实测能登，再卸 greeter 包。
- 卸完留下的残留：`/etc/pam.d/dankshell`（DMS 锁屏用的，已无用途，留着无害，想清理再删）、`~/.config/systemd/user/graphical-session.target.wants/dms.service` 之类的 enable 软链（包内 unit 随包消失，软链若在可删）。**`/etc/pam.d/greetd` 别碰**（greeter 还在用，DMS 在里面写过 howdy 的块）。
- 若 `systemctl --user` 里还有 dms 的 failed 状态：`systemctl --user reset-failed`。
- 主账户原有的 `~/.config/niri/`（DMS 那套配置）**不会随包卸载消失**，装移植前先备份再换基座。

### 11.6 niri 基座：原版默认 + 必须刻意补回的部分

原版默认配置在 `/usr/share/doc/niri/default-config.kdl`（本机**没有** `/etc/niri/`）。基座只是骨架，下面每一项都是移植的功能件，缺一条就少一块：

1. `environment` 块（§5.1）——注意 niri 语法是 `KEY "value"`，无 `=`，且**不展开 `$PATH`/`$HOME`**（所以路径要写全）
2. `spawn-sh-at-startup "quickshell ..."`（§5.2）——原版默认启的是 waybar，要换掉
3. Omarchy 绑定集（§5.3 的不冲突子集 + §5.4 的方向键方案）
4. 与 niri 原生键的冲突决策（§5.5：`Mod+Escape` / `Mod+Comma` / `Mod+Ctrl+R` 等）
5. 媒体键 OSD 绑定（`XF86Audio*` / `XF86MonBrightness*` → `omarchy-audio-*` / `omarchy-brightness-display`，带 `hotkey-overlay-title`）
6. 磨砂相关的层规则与 window-rule：bar / 弹窗的 `xray false`（§8.8、§8.11）+ ghostty 结霜（§5.8）
7. 全局圆角 window-rule（§5.7）+ focus-ring 跟随主题取色（§5.6）
8. `output "eDP-1"` 块：写死 `modeline 268.50 2560 2608 2640 2720 1600 1603 1609 1646 "+hsync" "-vsync"` + 默认 `scale 2.0`；**不要写 `mode` 行**（§5.7 的坑）
9. 模块化拆分（`include` 各 `.kdl`）与 `effects.kdl`

照 §5 抄即可，也可以把实验账户的 `~/.config/niri/*.kdl` 整体带过去（除了 `config.kdl` 里属于基座的部分），带过去后必须 `niri validate`。

### 11.7 目录搬运：整份 `cp`，不要"重装"

**推荐整目录搬**：一份克隆搬过去就同时带着 17 个已改文件、**238 条主题删除**、121 条迁移标记和 `.git` 分支状态（`dev @ 8675600`）。

| 项 | 体积 | 说明 |
|---|---|---|
| `~/.local/share/omarchy` | 520M | **必须整搬**（含 `.git`）。重装 + 重放补丁还要手工复现那 238 条删除，`install.sh` 不管这个 |
| `~/.config/omarchy` | 40M | `shell.json` 布局、`shell.toml` 活旋钮、`extensions/omarchy-menu.jsonc`、`plugins/*`、`themes/*`、`hooks/post-update.d/10-niri-repatch`、`niri-port/` 覆盖层与 `plugin-patches/` |
| `~/.local/state/omarchy` | 7.2M | **`migrations/` 里那 121 个标记**：缺了 `omarchy update` 会重放全部迁移（含危险项） |
| `~/.config/niri` | 80K | 移植的模块化配置（基座另按 11.6 处理） |
| `~/bin` | — | 垫片与包装脚本（仓库 `port-bin/` 是同一批；`__pycache__/*.pyc` 是缓存，删掉即可） |
| `~/.config/systemd/user/materal-recolor.{path,service}` | 8K | 主题取色监听（§8.10）；用 `%h` 是便携的，但 `default.target.wants/` 里的绝对软链要重新 `enable` 生成 |
| fcitx5 配置 + `~/.config/gtk-3.0/settings.ini` | — | 双源 + `ShareInputState=All`（§8.17）与 GTK 字号对齐 |
| `~/.config/omarchy/lock-{videos,designs}` | 小 | 锁屏插件（`io.github.sirjul1337.lock-explorer`，§11.10）的**每账户状态**：`lock-videos/` 是指向插件目录的软链（随插件目录一起搬即有效），`lock-designs/` 放自建设计（本机还没有）；所选样式存在 `shell.json` 的插件条目里（本机 `{"design":"split"}`）。插件本体在 `plugins/` 下，随 `~/.config/omarchy` 一起走 |

搬完的**验收数字**（与实验账户逐一对齐）：

```bash
git -C ~/.local/share/omarchy status --short | grep -c '^ D'   # 238
git -C ~/.local/share/omarchy status --short | grep -c '^ M'   # 17
grep -c '^@@' ~/.config/omarchy/niri-port/niri.patch           # 32（17 文件）
ls ~/.local/state/omarchy/migrations | wc -l                   # 121
systemctl --user daemon-reload && systemctl --user enable --now materal-recolor.path
```

**唯一的硬编码路径**：`~/.config/niri/config.kdl` 第 18 / 19 / 32 行写着 `/home/yvonne`（`OMARCHY_PATH`、`PATH`、`spawn-sh-at-startup` 的 `-p` 参数），必须全改成 `/home/jianlongliu`。`~/bin/*` 与两个 systemd 单元用的是 `$HOME` / `%h`，便携。

### 11.8 迁移后自检

```bash
niri validate
omarchy version
omarchy-shell lock status          # passwordPam 应为 true
omarchy-migrate --pending          # 应为空
~/bin/hyprctl -j monitors | jq -r '.[0].scale'
```

外加人工确认：bar 三件套（胶囊工作区 / Arch logo / 浮栏）、输入源徽章 `rime ⇄ keyboard-us`、媒体键 OSD、亮度条（`video` 组生效）、`omarchy theme bg next` 能触发 materal 取色、**真人按一次 `Mod+Ctrl+L` 锁屏并解锁**（§9 里尚未打勾的那条）。

### 11.9 回滚

- 系统层：`sudo snapper -c root undo <N>`；家目录：`sudo snapper -c home undo <N>`
- 只回壳层：重装 `dms-shell dms-shell-niri` 后 `systemctl --user enable --now dms.service`
- 移植侧：`~/.config/omarchy/niri-port/` 内有备份，覆盖层可 `git apply --reverse`

### 11.10 锁屏插件 `io.github.sirjul1337.lock-explorer`（能力边界与搬运）

上游：`github.com/SirJul1337/omarchy-lock-explorer`（MIT，74 commits，v1.7.7 / 2026-09-16，161★）；本机克隆**正好在上游 HEAD**（`d2f586b`），即无待更新。

- **是什么**：给 Omarchy 的**锁屏设计库 + 选择器 + 设计器**（manifest `clonedFrom: omarchy.lock`，装上即顶替 stock 锁屏，卸载/停用即回 stock）。24 套内置设计（Classic 就是 stock），密码框带显示按钮，部分设计显示头像；`Designer.qml` + `Editor.qml` 可自建设计，自定义放 `~/.config/omarchy/lock-designs/`，视频素材放 `lock-videos/`。
- **认证能力**（与 DMS 对等，且**各自独立 PAM 服务**，本机目前只有 `omarchy-lock-password` 存在）：指纹（`omarchy-lock-fingerprint`，有指纹器就自动监听）、facelock（`omarchy-lock-face` + `pam_facelock.so`）、安全钥匙（`omarchy-lock-fido2` + `pam_u2f.so`，由 `extras/setup-fido2.sh` 写入，**唯一需要 root 的一步**）。刻意分开的原因写在它的 README 里：把 `pam_u2f.so` 塞进密码服务会把每次打错的密码都变成钥匙的 PIN 尝试，八次就把钥匙锁死。
- **顺带功能**：DPMS 空白策略（默认锁后 5s 关屏，可选 Never；还有 `keepDisplaysOnWithHdmi` 这种 HDMI 唤醒绕行开关）、解锁动画（fade/zoom/rise + 时长）、多显示器 `setInputMonitor`（其它屏只显示时钟）、12/24 小时制、`extras/install.sh` 加启动器/菜单入口。
- **登录界面（DM）：这个插件当不了** —— 它是会话内的 Quickshell 插件（`ext-session-lock-v1` 要先有会话），DM 在会话之前运行并负责**启动**会话。想要"输密码登录"不需要它，三条路：
  - **零改动**：`dms-greeter`（现已装）本身就是输密码登录界面；卸 DMS **壳层**不必动它（§11.1）。
  - **摆脱 DMS 包、成本最低**：`greetd-agreety` **已装**，把 `/etc/greetd/config.toml`（主账户 sudo，0600）的 `[default_session]` 改成 `command = "agreety --cmd niri-session"`（`user = "greeter"`）→ 纯文本"用户名 + 密码 → 进 niri"。注意顺序：先在 TTY（Ctrl+Alt+F2）留好救急通道 → 改配置 → **登出实测能进** → 再卸 `greetd-dms-greeter-bin`；卸它前先 `pacman -D --asexplicit quickshell`（否则 `-Rs` 会把 quickshell 一起删，§11.1）。
  - **好看/图形化**：`greetd-tuigreet`（extra，带会话选择器）或 SDDM（上游 Omarchy 自带主题 `default/sddm/`）。
- **开机换皮（README 唯一标 experimental 的部分，本机不做）**：官方快路是 systemd-stub 的 initrd addon（`foo.efi.extra.d/*.addon.efi`，不重建 initramfs），但本机走不到——插件把 UKI 名写死成 `omarchy_linux.efi`（`plymouth/apply.sh:24`，本机是 `arch-linux.efi`），且 Secure Boot 只加载签名过的 addon；现实路径是 `plymouth-set-default-theme` + `mkinitcpio -P` 重建 initramfs，等于动启动链，**不建议顺手开**。
- **迁移**：插件本体在 `plugins/` 下（9.4M，随 `~/.config/omarchy` 一起走）；每账户状态 = `shell.json` 的插件条目（本机 `design: "split"`）+ `lock-videos/`（软链）+ `lock-designs/`；`omarchy-lock-fido2` / `omarchy-lock-face` 若要启用需在新账户（同一台机只需一次，`/etc` 全机共享）重跑对应脚本。

### 11.11 登录界面：自研 Quickshell greeter「Split Greeter」（Split 设计，多账户 + 人脸）

§11.10 的三条路里选了"自研"：**直接复用锁屏插件的 Split 设计当 DM**，既不依赖 dms-shell，也不依赖会话内 shell。代码在仓库 `split-greeter/`（本机 `~/omarchy-on-niri/greeter/`，**只在本地提交，未推远端**）。顺带确认：`greetd-dms-greeter-bin` 只依赖 `greetd quickshell qt6-declarative`，**不依赖 dms-shell**，与 DMS 的唯一耦合是 `dms-greeter sync` 把 DMS 主题/壁纸拷进 `/var/cache/dms-greeter`（0750 `greeter:greeter`，普通用户读不到）。

**结构**——greetd 拉起一个只跑本 greeter 的 niri 实例：

```
greetd ─► /usr/local/bin/split-greeter ─► niri -c /etc/greetd/split-greeter/niri.kdl
                                              └─► quickshell -p /etc/greetd/split-greeter
                                                     ├─ designs/Split.qml  （vendored 的锁屏设计，宿主即 lock 对象）
                                                     ├─ Greetd.qml         （登录状态机 + epoch 守卫）
                                                     └─ bridge/greetd-bridge.py ─► $GREETD_SOCK
```

- Quickshell 0.3.1 **没有 `Io.Socket`**（只有 `FileView`/`Process`），所以 greetd 的 unix socket 由 `Process` + `SplitParser` 驱动一个小 python 桥；`create_session`→`start_session` 必须**同一条连接**，故桥是长连接，消息是「4 字节本机序长度 + JSON」。
- 会话在 **greeter 进程树退出之后**才由 greetd 启动：QML 先 `Qt.quit()`（0.3.1 没有 `QuickshellGlobal.quit()`），`niri.kdl` 再 `niri msg action quit --skip-confirmation`。

**人脸是"回车触发"的**：设计里 `LockInput.onAccepted` 只在 `lock.faceConfigured` 为真时才在空输入上回车走人脸，
而 Split/`DesignBase` 把这个默认成 `false`——所以 greeter 必须自己声明：`niri.kdl` 里 `GREETER_FACE "1"`（装机时
`install.sh` 会探测 `/lib/security/howdy/pam.py`，没有就写 `"0"`，免得回车变死键）。**指纹（fido2）不参与**：
fprint 只挂在 `/etc/pam.d/sudo` 与 `polkit-1` 上，greetd 这条栈没有它，设计里的 fido2 分支永远不激活。

**人脸优先 = 直接用 PAM 的顺序，零额外认证代码**。`/etc/pam.d/greetd` 是 `ir-light`(optional) → `howdy`(sufficient) → `system-local-login`，于是：

| 界面 / 用户动作 | 协议动作 | 结果 |
| --- | --- | --- |
| 启动（或空字段回车） | `create_session{username}`，**不带密码** | PAM 先跑 howdy，界面显示 "Look at the camera…"，字段处于 `Checking…` |
| 刷脸命中 | — | PAM 成功 → 直接 `start_session`，**一次按键都不需要** |
| 刷脸未命中 | PAM 自己抛 `auth_message(secret)` | 界面这时才交出密码框，用 `post_auth_message_response` 送回 |
| 扫描中就打了密码 | 在 QML 里排队 | 提示一到自动交付（单连接不允许提前发，也不会开第二个会话） |

**多账户，且"长相"跟着账户**：账户 = `/etc/passwd` 里 uid≥1000，头像 = `/var/lib/AccountsService/icons/<user>`（没有就显示首字母圆牌）。右上角常驻账户按钮开选择器（↑↓ / Enter / Esc，也可鼠标点）。切账户 `epoch += 1`：**旧账户在途的人脸命中会被丢弃、并向 greetd 发 `cancel_session`**——宁可退回登录界面，也不登成错的人。成功登录的账户写 `~/.local/state/split-greeter/last-user`，下次默认选中。**配色与壁纸跟着选中的账户**（启动时 = 上次登录的账户）：`split-greeter-sync` 把每个账户的 `colors.toml` / `shell.toml` / 当前壁纸拷到 `/var/lib/greeter/users/<账户>/`，`shell.qml` 用 `Color.themeOverride` 把面板指过去；字体与间距是机器级，取共享缺省（`/var/lib/greeter`）。目录布局、测试钩子等细节见 `split-greeter/README.md`。

**装与回滚**——切 greetd 的 `[default_session].command` 是唯一能把人锁在门外的一步，脚本**不碰** `/etc/greetd/config.toml`：

1. `sudo ./install.sh`：拷到 `/etc/greetd/split-greeter`（世界可读，greeter 用户要读）+ `/usr/local/bin/split-greeter{,-sync}`；建 `/var/lib/greeter/{users,.config/omarchy,.local/state/split-greeter}`（属 `greeter`）。
2. `sudo split-greeter-sync`：同步**全部真实账户**的配色与壁纸（给共享缺省，没自己主题的账户走软链）。建议挂到已有的更新钩子后面，主题一换登录界面就跟着换。
3. 先开着 TTY（Ctrl+Alt+F2）→ 把 `[default_session]` 改成 `command = "/usr/local/bin/split-greeter"`、`user = "greeter"` → 登出实测 → 起不来就在 TTY 改回原值（dms-greeter 留的备份在 `/etc/greetd/config.toml.backup-*`）。
4. **实测能进之后**，才谈 `sudo pacman -D --asexplicit quickshell` 与卸 `greetd-dms-greeter-bin`（§11.1：不先 asexplict，`-Rns` 会顺手带走 quickshell，本 greeter 和 Omarchy shell 一起瘫）。

**2026-09-19 装机状态（`pkexec` 已执行）**：`/etc/greetd/split-greeter`（root:root，文件世界可读）+ `/usr/local/bin/split-greeter{,-sync}` 已就位；`split-greeter-sync` 已跑过一遍（`yvonne` = `tonal-spot` 主题 + 当前壁纸；`jianlongliu` 因为**还没迁移**、`~/.local/state/omarchy/current` 根本不存在 → 该账户目前软链到共享缺省）。**`/etc/greetd/config.toml` 的改动是用户自己做的**：15:09 他把 `[default_session].command` 切成 `/usr/local/bin/split-greeter`（备份 `/etc/greetd/config.toml.split-greeter-backup`，168B = 旧的 dms 命令），15:15 登出后 tty1 起的就是本 greeter。装机校验实测：greeter 身份下 `/etc/greetd/split-greeter` 下**所有文件可读**、桥可执行、状态目录可写；`niri validate -c /etc/greetd/split-greeter/niri.kdl` 通过；壁纸 sha256 与源文件一致。

**注意**：`greeter` 账户的 passwd home 是 **`/`**（`greeter:x:964:964:...:/:/bin/bash`），所以 `niri.kdl` 里那行 `HOME "/var/lib/greeter"` 是**关键行**，缺了它主题/状态目录全找不到。

**不登出也能验收**（都在会话里跑，用 `bridge/mock-greetd.py` 假装 greetd）：

- `python3 split-greeter/bridge/test-bridge.py` —— **24 项协议断言全过**：错密码、成功、失败后重试、交互式 secret、人脸命中、人脸未命中转密码、未知用户、epoch 回显、cancel、socket 不可用（不崩）。
- `split-greeter/tests/smoke.sh` —— 7 场景**全过**（人脸命中直通 / 人脸未命中回落密码 / 错密码**不产生**会话 / 切账户后登录 /
  **回车触发扫脸**（先断言"没按回车绝不扫脸"再按回车）/ 真按键注入的输密码 / 真按键注入的切账户），断言「greetd 是否收到 `start_session`」+「greeter 是否干净退出」+「无 QML 报错」。（前 4 个用例显式带 `GREETER_AUTOBEGIN=1` 复现旧行为，后 3 个走新的默认路径。）加 `GREETER=/etc/greetd/split-greeter` 就是**验装好的那份**（含它自己 `bridge/` 下的桥）——实测也是 4/4，并真拿到了 `start_session`。
- 视觉证据：Split 正常渲染（左壁纸 + 时钟、右半透明面板、错误态红框、选择器头像/首字母）；**壁纸跟账户**（实测背景均值 `2.5 → 195.5`）；**配色跟账户**（切到测试账户后 `Color.background` 由 `#111318` 变 `#7f0000`，来源 `users/yvonne/theme`）。
- 单跑一次（要截界面时）：`--delay` 调大，再用 `GREETER_SELFTEST_OPEN_PICKER=1` / `GREETER_SELFTEST_PICK=<user>` 驱动；`SelfTest.qml` 只在 `GREETER_SELFTEST_PASSWORD` 非空时经 `Loader` 加载，生产路径不经过它。

**边界**：单输出（只配 `eDP-1`）；指纹 / FIDO2 没有专门 UI，作为 PAM 消息出现；`start_session` 固定 `niri-session`（`GREETER_SESSION` 可改），没有会话选择器；字体/间距不随账户切换；**不动 Plymouth / 启动链**（§11.10 的结论）。vendored 的 `designs/ Commons/ Ui/` 由 `split-greeter/vendor.py` 按组件闭包重拷并重放 4 处补丁（`Color.qml` 的 `themeOverride`、`DesignBase.qml` 的 `loginUser`/`hintOverride`、`Split.qml` 的提示行、`Style.qml` 的 `cornerRadius`），插件或 Omarchy 升级后重跑一次即可。

### 11.12 登录界面：一条卡住的 PAM 对话 = 密码"没反应"（2026-09-19 真机实测与修法）

> **修正（2026-09-19 15:5x）**：本节说的"卡住的 PAM 对话"**真实存在**，超时换 helper 的修法保留；但它不是
> "输密码 + 回车毫无反应"的**主因**——主因是宿主少接了一条设计信号，见 **§11.13**。诊断教训：字段
> `activeFocus/enabled/readOnly` 全正常，也不能说明回车能提交。

**现象**：切到自研 greeter 后**登不进去**——输密码毫无反应、连错误都不报；同机 TTY2 用文本登录能进
`yvonne`（1001，有密码），**`jianlongliu` 的文本登录却失败**（那个账户实际靠 howdy 进）。

**根因**：greeter 一启动就对**默认账户 jianlongliu** 发起不带密码的 `create_session` → PAM 进
`howdy`（sufficient）→ 人脸没命中/相机没就绪时 howdy **永远不返回**；而 **greetd 一条连接上同时只允许
一个会话** → 之后所有请求（包括"切到 yvonne 再输密码"）全排在门外 → 界面既不动也不报错。epoch 守卫只
丢弃过期**事件**，救不了这条被占住的连接。**这不是密码错，所以没有任何失败可显示。**

**修法（`split-greeter/`，已装机）**：给"一次尝试"设期限 `GREETER_ATTEMPT_TIMEOUT_MS`（默认 12s），到点**整条换掉
helper 进程**——断开连接让 greetd 自己取消那个会话——新连接上直接发**带密码的** `create_session`（PAM 里
howdy 仍会先跑，命中就依旧免密码）。两条触发路径：① 扫脸期间一开始输密码 → **立刻**走（实测 ~1s）；
② 什么都不做 → 超时后换掉，界面停在密码框（**不自动重扫**，避免死循环）。切账户同理，不再在同一条连接上
`cancel` 后重试。

**顺带修的两处可观测性**：① `niri.kdl` 里 quickshell 的 stdout/stderr 落 `$HOME/greeter.log`
（= `/var/lib/greeter/greeter.log`，greeter 用户可写、所有账户可读）——之前输出只进 VT 控制台，人一被关在
门外就没法诊断；② **Tab** 打开账户选择器（原来只有右上角小按钮）。

**新增不需要合成器的回归测试**：`split-greeter/tests/state.sh` + `split-greeter/StateTest.qml`（只加载 `Greetd.qml`，
没有 `PanelWindow`，所以 `QT_QPA_PLATFORM=offscreen` 就够）——**6 场景全过**：人脸命中 / 错密码不产生会话 /
**卡住+输密码** / **卡住+看门狗** / 卡住时切账户 / 卡住且无人操作（只恢复、不登录）。每个卡住场景都额外断言
"那次尝试真的被丢掉"（日志出现 `restarting the login helper`）。这是**被锁在门外、图形会话都没了时唯一能跑的
验证**，价值在今天就体现了。`bridge/mock-greetd.py` 相应加了 `--hang-face`（发完 info 就再不回答）并改成
**每连接一线程**（否则新连接会排在旧连接后面——真 greetd 不会这样，夹具不这么改就测不出这个 bug）。

**装机现场与权限现实**：`pkexec` 只在**图形会话**里可用（polkit agent 随会话存在）；纯 TTY 里 pkexec 起不了
文字 agent（`Error opening current controlling terminal (/dev/tty)`），`sudo -n` 也没有时间戳 → **别指望在
TTY 里自动拿到 root**。15:34 重新 `pkexec install.sh` + `pkexec systemctl restart greetd`（与 checkout
逐文件一致，只有测试文件不装），被占住的旧 greeter 随之消失；新版本已在写 `greeter.log`（仅 Split 设计的两条
`hyprctl` 警告：niri 上取不到圆角/gaps，回退 `GREETER_CORNER_RADIUS`，无害）。

**教训**：greeter 里**任何"等 PAM 回答"的路径都必须有期限，且期限到了要换连接**，而不是在同一条连接上重试；
同时 greeter 必须留一份**离线可读的日志**。

### 11.13 密码"按回车没反应"的真正原因：宿主少接了一条设计信号（2026-09-19 二次实测）

**Split 设计的所有权契约**：`DesignBase` 只声明 `property string passwordText` 和
`signal passwordTextEdited(string)`，**从不自己给 `passwordText` 赋值**——所有权在宿主（原插件里是
`LockView` 那样的宿主自己维护并回灌）。`LockInput.onTextChanged` 只发 `passwordTextEdited(text)`，
`LockInput.onAccepted`（回车）读 `lock.passwordText` 决定提交什么。我的 `shell.qml` 当时**没接这条信号**：

- 密码框照常显示圆点（那是 TextInput 自己的文本），但 `design.passwordText` **始终为空串**；
- 回车 → `submitted.length === 0` → 不提交，落到 `else if (lock.faceConfigured) lock.faceRequested()`
  → 表面像"又去扫脸了"，用户看到的就是**按回车毫无反应**；
- 每个账户的框都是空的，所以**换账户也不行**。

**修法（一行）**：`onPasswordTextEdited: text => design.passwordText = text`（另加
`onClearFailureRequested` 清错误提示、`onPasswordRequested` 回焦）。

**同一轮修的第二处：账户选择器**
- 设计自带**焦点回收看门狗**（`DesignBase.qml:213-226`：`inputItem` 一旦没有 `activeFocus` 就抢回去）
  → Tab 打开选择器后，方向键/回车全被设计吞掉，表现就是"选择器开了也切不动账户"。修法：选择器打开期间
  `inputEnabled: !greetd.sessionStarting && !picker.open`（设计提供了这个开关；恢复时它会自己重新聚焦密码框）。
- 行上的 `HoverHandler` 在**弹窗出现**时给鼠标下的那一行发 hover-enter，把光标重置 → 按 ↓ 像没反应，最后
  选中的永远是"鼠标指着的账户"。修法：改成 `MouseArea { hoverEnabled: true; onPositionChanged: ... }`，
  **只在指针真移动时跟随**。

**端到端证据（真实按键注入，不是直接调 API）**：`wtype 'hunter2'` + `wtype -k Return` →
`password field received input` → `password submitted for jianlongliu (7 chars)` → `auth_ok` → `started`
→ mock 收到 `start_session ["niri-session"]`；切账户：`Tab` → `↓↓↓` → `Return` →
`the account picker chose yvonne` → `account switched to yvonne from jianlongliu` → 输密码 → `auth_ok`。

**测试为什么没拦住（核心教训）**：`SelfTest.qml` 之前直接调 `design.submitPassword(pw)`（宿主公开 API）和
`picker.picked(name)`，**恰好跳过了出问题的两段宿主接线**。已改成走**设计自己的路径**：
`design.passwordTextEdited(pw)` + `design.inputItem.accepted()`。另加两个**真实按键**用例（`wtype`）：
`typed-password` / `typed-switch` → `tests/smoke.sh` 现 6 用例、`tests/state.sh` 6 场景，全 `FAILURES: 0`。
**规则：自检要驱动"设计发什么信号"，不要驱动"宿主提供什么函数"。**

**诊断开关**：`GREETER_DEBUG_FOCUS=1` 每秒打印输入框状态（`enabled/readOnly/visible/activeFocus/尺寸`、文本
**长度**、`pickerOpen/pickerFocus`）。今天正是靠它把"字段看着正常但回车无效"定位到宿主接线；只打长度不打内容，
日志里不会出现密码。

**⚠️ 现存副作用（待定）**：greeter 一启动就对默认账户自动发起 howdy 尝试。15:5x 我 `pkill -u greeter` 让
greetd 重拉 greeter 时，新实例的脸扫**命中**了 → greetd 立刻又开了一个 **jianlongliu 的 niri 会话**（VT1）。
**2026-09-19 已改：人脸改成"回车触发"，不再开机就扫（§11.14）。** 启动时**一次认证都不发起**，
`LockInput.onAccepted` 在空输入上回车 = `faceRequested` → 开扫（这是设计原本的语义）；**直接打字就是纯密码**
（`authenticate()` 空闲时会自己开一个带密码的会话）。代价是失去"人脸优先"——走过来的瞬间不再自动登录，
但也因此修掉了"人从镜头前走过就被登进去"以及"自动扫脸掩盖了密码路径到底通不通"。
需要时 `GREETER_AUTOBEGIN=1` 恢复旧行为（只有测试用得上）。

### 11.14 人脸改成"回车触发"（2026-09-19，用户指定）

用户原话：「回车触发面部解锁（指纹识别这台机不是很合适，我分给 sudo 用了）」。所以：

- **默认不再开机扫脸**。`shell.qml` 给 `Greetd` 传 `autoBegin: (Quickshell.env("GREETER_AUTOBEGIN") || "") === "1"`——
  缺省不发起任何认证；**空输入上回车**才扫（设计的 `LockInput.onAccepted` 本来就把空提交当"要人脸"）。
  `Greetd.qml` 自己的 `autoBegin` 默认仍是 `true`，所以 `tests/state.sh`（直接驱动 `Greetd.qml`）不用改。
- **踩到的坑：`faceConfigured` 不声明，回车就是死键。** 设计里回车走不走人脸看 `lock.faceConfigured`，
  而 Split/`DesignBase` 默认 `false`，宿主不声明就永远是 `false`——症状与"回车没反应"一模一样，但成因完全不同
  （§11.13 是密码文本没接上，这里是分支条件不成立）。现在 `niri.kdl` 写 `GREETER_FACE "1"`，
  `install.sh` 探测 `/lib/security/howdy/pam.py`，没有就改成 `"0"`（免得在一台没装如何的机器上留个死键）。
- **不回退"人脸优先"的收益**：①人从镜头前路过不会被登进去；②自动扫脸其实**掩盖了密码路径到底通不通**
  （修那个 bug 时它一直把症状伪装成"人脸失败"）。代价：要抬手按一下回车。
- **指纹不参与**：fprint 只挂在 `/etc/pam.d/sudo` 与 `/etc/pam.d/polkit-1` 上（用户自己分的），
  greetd 这条 PAM 栈里没有它，设计里的 fido2 分支永不激活——不写任何代码，保持不变即可。
- 提示文案：空闲时显示 `Press Enter for face unlock, or just type your password`（`hintOverride`，
  仅当 PAM 没给更具体的 hint 时）。`tests/smoke.sh` 现在 7 个场景，新增的 `enter-triggers-face`
  先断言"没按回车绝不开扫"再按回车断言确实开扫并拿到 `start_session`。

### 11.15 迁移执行清单（照着做；2026-09-19 核过机器事实）

**这份文档在哪**（主账户怎么拿到）：公开仓库
<https://github.com/jianlongliu/omarchy-on-niri/blob/quattro/docs/omarchy-on-niri-port.md>（`git clone` 或浏览器都行，主账户可读）；
§11 的纯摘录在 `/var/tmp/omarchy-migrate-to-main-account.md`（重启会被清，别当唯一副本）。
本机的 `~/Documents/omarchy-on-niri.md` 是 0600，**主账户读不到**，不要指望它。

**0. 前置**
- 全程要 root 或 `sudo`：`/home/yvonne` 是 0600，主账户自己读不到源。
- 快照（本机 btrfs + snapper，已有配置 `root`=/(含 /etc)、`home`=/home、`data`、`opencode`）：
  ```bash
  sudo snapper -c root create -d "pre-migration"
  sudo snapper -c home create -d "pre-migration"
  snapper -c root list | tail -3      # 记下编号，回滚用得到
  ```
  回滚：`sudo snapper -c root undo <N>` + `sudo snapper -c home undo <N>`，然后重启。
- 工具确认：`command -v niri quickshell greetd fcitx5 howdy snapper` 应全有输出。

**1. 顺序**：严格按 §11.3 的执行顺序（快照 → 卸 DMS → 原版 niri 默认配置当基座 → 整目录搬运 → 改硬编码 → 自检），别跳步。
卸 DMS 时记得 §11.5 那条：先 `sudo pacman -D --asexplicit quickshell`，否则 `-Rns` 会连 quickshell 一起删掉（登录界面就没了）。

**2. 必须带走的东西**（不只是点文件）
- `~/bin/` 里自写的：`hyprctl`（niri 的 shim，**必需**；`.bak-*` 可丢）、`materal-update`、`omarchy-niri-apply-theme`、
  `omarchy-niri-repatch`、`omarchy-niri-system`、`omarchy-powerprofiles-{list,set}`、`vantage`（分辨率 TUI，若在别处也一并带）。
- `~/.config/omarchy/`：`themes/`（含 tonal-spot 等自定义）、`plugins/`、`shell.json`、hooks。
- `~/.config/systemd/user/materal-recolor.{path,service}` → 搬完 `systemctl --user daemon-reload && systemctl --user enable --now materal-recolor.path`。
- `~/.local/share/omarchy`（shell 本体 + bin + 主题，git 检出，带 `.git` 一起）。
- 壁纸库 `/data/Pictures/Wallpapers`（所有主题都软链到这里，**路径大小写敏感**）。
- 七个插件：`charlieras262.floating-bar`、`io.github.sirjul1337.lock-explorer`、`jrmmhm.pocket`、`meviusisback.ai-subs`、
  `ronald.input-sources`、`yvonne.arch-logo`、`yvonne.workspaces`。其中 floating-bar 在 niri 上有补丁（`niri-port/plugin-patches/`）。
- `~/.config/niri/` 整目录（含 `config.kdl`、`binds.kdl`、`niri-port/`）。

**3. 硬编码 `/home/yvonne`：只需改 2 个文件**
- `~/.config/niri/config.kdl` 三行：`OMARCHY_PATH`、`PATH` 的第一段、`spawn-sh-at-startup "quickshell -n -p …"`。
- `~/.config/remmina/remmina.pref`（可选，RDP 客户端的默认目录）。
- **实测口径**：整个 `~/.config/` 里真正含这个路径的**配置文件只有上面两个**；另外约 60 个命中全在浏览器/LevelDB 里，属噪音，别去 sed。
- 自查：`grep -rn '/home/yvonne' ~/.config --include='*.kdl' --include='*.json' --include='*.toml' --include='*.conf' --include='*.ini'`

**4. 属主**：整目录搬运是 root 做的，搬完必须归位，否则新会话一堆怪毛病：
`sudo chown -R jianlongliu:jianlongliu /home/jianlongliu`（或只对搬进来的子目录逐个 chown，别撒到别处）。

**5. 登录界面（Split Greeter）与锁屏门禁**
- 装机：`sudo ~/omarchy-on-niri/split-greeter/install.sh`（→ `/etc/greetd/split-greeter`、`/usr/local/bin/split-greeter{, -sync}`），
  greetd `config.toml` 的 `command` 指到 `/usr/local/bin/split-greeter`。
- **PAM 门禁别漏**：`pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock`——漏了就是"锁屏点不动 / `lock()` 返回 `missing-pam`"（§11.12）。
- `sudo usermod -aG video jianlongliu`（howdy/摄像头要用）。
- 人脸现状：**jianlongliu 已有人脸模型，yvonne 没有**（howdy 对 yvonne 报 `No face model known`）→ 迁到主账户后"回车＝人脸"开箱可用。

**6. 自检清单**（每条都要有可观察结果，别凭感觉）
- 重启 → 登录界面是 Split；可切账户；**空输入回车＝扫脸**；直接打字＝密码；输错有报错。
- `Mod+Ctrl+L` 锁屏 → 输密码能解开（插件设计 = `design: "split"`）。
- bar：floating-bar 浮栏在位；左 `yvonne.arch-logo` + `yvonne.workspaces`；右 `ronald.input-sources` 徽章；Monitor 面板能改缩放。
- 主题取色（`materal-recolor`）、壁纸、字体 12px、fcitx5 输入源（单源会自动隐藏）。
- 显示：固定 2560x1600@60（分辨率用 `vantage`，缩放走 bar 的 Monitor 面板）。
- `niri msg action do-screen-transition` 之类基础 IPC、以及 `Super+Alt+L`（swaylock）/`Mod+Ctrl+L`（omarchy 锁）两条路都不冲突。

**7. 回滚**：`snapper` undo（第 0 步）+ 配置文件级回退见 §11.9；greetd 有 `config.toml.omarchy-greeter-backup` 备份。

**8. 还没做的事**（免得你翻不到以为漏了）
- 自研锁屏 `split-lock/`：桥 `LockView.qml` 已跑通（§11.16，8 项契约测试三轮稳定），**尚未换装**；换装前先补 niri shim 并留退路。
- niri 的 `hyprctl` shim 缺 `dpmsStatus` / `solitaryBlockedBy` → stock 锁屏的"锁住自救"会永远误判成已解锁，做锁屏前补。
- 浮栏弹窗避让（toast/托盘面板压栏 8px）。

### §11.16 自研锁屏 `split-lock/`：桥已跑通（2026-09-19）

**结论：`LockView.qml` 就是全部适配层，已验证；尚未换装到活会话。**

stock 的锁 Service 用**文件名**实例化 `LockView { ... }`（`reference/Service.qml` 约 304-323 行），而 Split / `DesignBase` 的属性和信号与 stock 视图**同名同形**（`submitPassword` / `clearFailureRequested`）——所以把自己的包装命名为 `LockView.qml` 本身就是适配，不需要重构，也不需要第二个视图。

**离线契约测试**：`cd split-lock && ./tests/state.sh` —— 8 项、三轮稳定、全程 offscreen（不碰活会话、不锁屏）。它拼一个一次性 qs 工程（`Commons`/`Ui` 软链 + 平铺的 `.qml`），跑一个照抄 Service 绑定的 mock host，双向断言：视图能实例化、host→view 推送、view→host 的 `passwordTextEdited` / `submitPassword` / 失败回传 / 清除，以及 `clearFailureRequested` 能出去。qs 日志留在 `/tmp/split-lock-state.log`。

**两个踩过的坑（都已写进代码注释）**：

1. **目录导入不可靠**：视图里写 `import "designs"` 时，只要它是被当作"类型"加载的（而不是配置的根文件），`Split` 就解析失败。改成把设计文件**平铺**到 `LockView.qml` 同级 —— 同目录类型隐式解析 —— 这类失败整片消失。
2. **offscreen 下不能出现 `PanelWindow`**：layer-shell 窗口需要真实后端，mock host 用它就报 `No PanelWindow backend loaded`；换成 `Rectangle` 容器后干净通过（被测的是属性/信号接线，与父容器是谁无关）。

**`displaysBlank` / `powerSaverActive` 为什么可以不管**：Service 会传这两个（`Service.qml:34-48` 定义，与 `backgroundVersion` 一起在 310 附近传入视图），而 `DesignBase` 没有对应属性，不声明 Quickshell 会直接拒绝创建视图。stock 视图只为**一件事**用它们——暂停壁纸播放（`reference/LockView.qml:94`）；本设计的 `Wallpaper` 是静态 `Image`（`Wallpaper.qml:22`），**没有动画可暂停**。真正有用的是 `loadBackground` / `backgroundVersion`（缓存击穿的 `fileUrl`），设计里已经尊重（`Wallpaper.qml:25`）。

**还没做（换装前必须）**：① niri 的 `hyprctl` shim 补 `dpmsStatus` / `solitaryBlockedBy`，否则 stock 锁屏的"锁住自救"会永远误判成已解锁；② 先留好退路再让插件上位；③ 锁屏/解锁/打错密码由**用户自己**按一次，不主动锁他的屏。
