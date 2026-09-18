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
  → 用 `Niri.qml` 单例轮询 `niri msg -j workspaces|windows` 提供等效数据。

参考的中间层模式：DankMaterialShell (DMS, AvengeMedia) —— Go daemon + unix socket JSON 协议，
原生支持 niri。本方案选用的是更轻量的"hyprctl 垫片"而非 DMS daemon，因为 Omarchy 的
hyprctl 调用面有界、可直接映射。

---

## 3. 文件清单（改动/新建/备份）

### 3.1 新建的核心交付物

| 路径 | 作用 |
|---|---|
| `~/bin/hyprctl` (624 行, +x) | hyprctl 垫片：Omarchy 的 `hyprctl` 调用 → `niri msg`，纯 stdlib，不依赖 jq；`cmd_binds` 支持 `include` 递归展开（config.kdl 模块化后键位仍可见，见 §4） |
| `~/.local/share/omarchy/shell/Commons/Niri.qml` (153 行) | QuickShell 单例，轮询 niri，暴露 `workspaces/focusedWorkspace/focusedMonitor` + `overviewOpen` |
| `~/.local/share/omarchy/shell/plugins/blurwallpaper/` (`BlurWallpaper.qml` + `manifest.json`) | 移植自有 QuickShell 插件（id `omarchy.blurwallpaper`，kind `service`）：overview 期间渲染强模糊壁纸（§8 第 10 条） |
| `~/bin/omarchy-niri-apply-theme` (Python, +x) | 把当前 Omarchy theme 的边框色写进 niri 的 `focus-ring`（C 层换色）；**沿 `include` 定位**含 `focus-ring` 的模块、支持渐变取首个色站（§5.6） |
| `~/bin/materal-update` (Python, +x) | **主题动态取色生成器**：读当前壁纸 → matugen 出 M3 配色 → 映射成 omarchy `colors.toml` → 重套主题（§8.10） |
| `~/.config/omarchy/themes/tonal-spot/` | 用户级主题（`matugen.toml` + 自生成 `backgrounds/` + 静态 ANSI 16 色），`omarchy theme set Tonal-Spot` 选用（§8.10） |
| `~/.config/omarchy/hooks/theme-set.d/20-materal` | 换 theme 时重新取色（与 `10-niri-border` 并列，§8.10） |
| `~/.config/systemd/user/materal-recolor.{path,service}` | 盯 `current/` 与 `current/background` 的 path/service 单元：换壁纸即自动重取色（§8.10） |
| `~/.config/omarchy/plugins/yvonne.arch-logo/`、`~/.config/omarchy/plugins/yvonne.workspaces/` | 用户级 bar 部件（仓库外、抗 `omarchy update`）：Arch logo、胶囊式工作区指示（§8.11） |
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
| `~/.config/niri/effects.kdl` | 2026-09-19 移除 `^omarchy-bar$` 的 blur layer-rule（浮栏后被糊出光晕，§8.8）|
| `~/.config/omarchy/shell.json` | bar：`id` = `charlieras262.floating-bar`、`floatGap` 8、`cornerRadius` 10；`layout.left` = `yvonne.arch-logo` + `yvonne.workspaces`（§8.11）|
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

核心逻辑：每 500ms 轮询 `niri msg -j workspaces` 和 `niri msg -j windows`，
组装出一个仿 `Hyprland.workspaces` 的模型，供 Bar 的 Workspaces.qml / Bar.qml 使用。

- `root.workspaces.values[]` 每项含：`niriId, id, name, output, active, focused,
  toplevels.values[]`（`toplevels.values.length` 由 windows 按 workspace_id 计数得出）。
- `root.focusedWorkspace` = 当前聚焦 workspace。
- `root.focusedMonitor` = `{ "name": 聚焦 workspace 的 output }`。
- `root.overviewOpen`（bool）：另跑 `niri msg -j overview-state` 取 `is_open`，供 overview
  模糊壁纸插件（`shell/plugins/blurwallpaper/`）判断何时该显示。
- 写成 `property Process x: Process { id: x; ... }` 形式（匹配 Omarchy Style.qml 惯例），
  并给 StdioCollector 加 `waitForEnd: true`，否则编译报
  "Cannot assign to non-existent default property"。

> 注意：只读数据才走这里。真正执行合成器动作靠 `hyprctl` 垫片。Hyprland 原生模块中
> 用来发信号的 `HyprlandFocusGrab`（target: Hyprland）等其他 import 会继续解析为
> QuickShell 的内建模块，但 run（轮询）只喂给 Niri.qml。

---

## 7. 部署步骤（全新环境重现用）

> Omarchy v4 的 `install/` 是**全系统安装器**（udev/snapper/firewall/pacman），
> 出于约束**刻意跳过**，只部署 config/bin/shell 到 home。

1. 克隆仓库（branch `quattro`，4.0.0.alpha）到 `~/.local/share/omarchy`：
   ```sh
   git clone -b quattro --depth 1 https://github.com/basecamp/omarchy ~/.local/share/omarchy
   ```
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
      （id `omarchy.blurwallpaper`，kind `service`）渲染强模糊壁纸，开关由 `Niri.overviewOpen`
      （轮询 `niri msg -j overview-state` 的 `is_open`）驱动；`effects.kdl` 给该 namespace 配
      `place-within-backdrop true`。
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
  ——这 17 个文件正是 `niri.patch` 的内容（`17 个文件 / 30 个 hunk`，2026-09-18 合并上游后数值）。
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
30 个 hunk，`--reverse --check` 通过）**：
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
  - **`^omarchy-bar$` 于 2026-09-19 移除**（浮栏插件 §8.11 启用后）：niri 的 layer blur 会把 bar
    **自己的填充一起采样**（与 Hyprland 的 `ignore_alpha` 无 niri 等价物，niri issue #1554 未修），
    于是 bar 的四角被糊出一圈光晕、圆角看起来是"方的"——问题不在圆角配置，在模糊。浮栏本身不透明
    （`shell.json` 里 `transparent: false`），这层 backdrop blur 本来也看不见，删掉零损失。
    代价：将来若把 bar 改回半透明，得先把该 namespace 加回这里，否则没有霜面。
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
- niri 适配 4 处（Hyprland 独占调用 → 垫片/niri 等价物），存档在
  `~/.config/omarchy/niri-port/plugin-patches/charlieras262.floating-bar.patch`；`omarchy plugin update`
  会用上游版本覆盖工作树，覆盖后要重打这个 patch。
- 参数：`floatGap = 8`（逻辑）、`cornerRadius = 10`、`transparent: false`。
- 几何实测（scale 2.0，物理 px）：bar 占 y 16..79、左缘 x = 16（= 8 逻辑 floatGap，bar 高 32 逻辑）；
  平铺窗口停在 728 = 800 − (32 bar + 8 floatGap + 16 niri gaps)——**niri 在自己的独占区之外又加了一次
  gaps，两者不打架**（像素核对过）。
- 配套改动：`~/.config/niri/effects.kdl` 去掉 `^omarchy-bar$` 的 blur layer-rule（原因见 §8.8）。
- 保留的第三方部件：`charlieras262.omablur`（圆角/模糊调节）、`ryuhzk.ime`。
- 已知待修：toast 与 `KeyboardPanel` 家族弹窗没给浮栏让位（§8 第 18 条）。

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
- [ ] Omarchy 锁屏（`Mod+Ctrl+L`）在 niri 上实测。
- [ ] 真实跑一次 `omarchy update`，确认上游变更时覆盖层自动重放或明确报冲突。
- [x] **logout/reboot/shutdown** 统一标准化：`~/bin/omarchy-niri-system` 单一入口（logout→niri quit、reboot/shutdown→logind D-Bus `Manager.Reboot/PowerOff`；`loginctl` 无该 verb 是本 bug，已改；`pkcheck` 免密 exit 0 验证）。
- [x] **电源 profile**：`~/bin/omarchy-powerprofiles-list` 返回 3 个 profile、active 标记正确；set 经 TLP D-Bus 生效（异步应用，恢复为 power-saver）。
- [x] **Ghostty 磨砂模糊**：`window-rules.kdl` 给 `com.mitchellh.ghostty` 加 `background-effect {xray true; blur true}` + `draw-border-with-background false`；ghostty `background-opacity = 0.85`、`background-blur-radius = 0`；焦点环穿透"诡异"问题已解（§5.8）。
- [ ] 运行实测：注销、关机、重启（会结束会话/重启，交给用户）。
- [x] **overview 背景统一**：`shell/plugins/blurwallpaper/` + `Niri.overviewOpen` 驱动（见 §3.1、§6、§8 第 10 条）。
- [x] **菜单 override label+icon 修复（2026-08-27）**：`extensions/omarchy-menu.jsonc` 的 3 个 setup 项补全 label+icon，合并后显示 "Monitors"/"Keybindings"/"Input" 且图标正常（不再显示 raw id `setup.monitors` 之类）；根因是 `normalizeItem` 的 `label: value.label || id` 把 action-only override 的 label 退化成 id 并覆盖默认项。
- [x] **视觉磨砂（frosted Quickshell）**：`Menu.qml` + `KeyboardPanel.qml` 挂 `BackgroundEffect.blurRegion`（只磨砂卡片，不全屏）；`effects.kdl` 给 `omarchy-keyboard-panel` 设 `xray false`（实时窗口毛玻璃）；`[popups]` alpha 0.8→0.65。面板开/关屏幕底部清晰度 on/off≈0.995 → 无全屏霜化。
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

---

## 10. 关键环境信息

- 用户 `yvonne`（uid 1001, gid 1003, groups wheel）；隔壁 `jianlongliu` uid 1000。
- niri 26.04 (8ed0da4) 位于 `/usr/bin/niri`。
- 显示管理器：greetd / dms-greeter。包管理器 paru。
- 电源后端：**TLP**（`tlp` + `tlp-pd` 1.10.2，D-Bus `net.hadess.PowerProfiles`），**无** power-profiles-daemon（`powerprofilesctl` 缺失）。
- 引导：**systemd-boot + Secure Boot，无 Limine**；内核是 stock `linux`（不是上游推的 `linux-omarchy`）。
- 仓库：`core` / `extra` / `multilib` / `archlinuxcn`——**未配置 Omarchy 自家仓库**（所以 `mise-bin`、
  签名强制等迁移在此不适用）。
- 快照：**snapper** 已启用（root 配置），pacman 事务前后自动打快照。
- **特权通道**：`pkexec` 免密可用；`sudo -n` 失败（要密码），`omarchy-pkg-add` 因此非交互不可用。
- `mise` 来自 Arch `extra`（2026-09-09 装），上游用的是自家仓库的 `mise-bin`。
- `XDG_CURRENT_DESKTOP=niri`（移植的 niri 守卫分支据此生效）。
- 读取 `HYPRLAND_INSTANCE_SIGNATURE is unset` 警告仅影响便捷性，QuickShell 在 layer-shell
  下照常渲染。
