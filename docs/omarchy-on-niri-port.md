# Omarchy on niri — 移植方案与运维文档

> 目的：把 DHH 的 Omarchy v4（原本 Arch + Hyprland + QuickShell）移植到 niri
> 滚动平铺 Wayland 合成器上，运行在 `yvonne` 账户，并保持 niri 原生体验。
> 本文档是"上下文丢失也能重建"的持久记录。最后更新：2026-08-27（同步 override label+icon 修复、修正 Apps 项已推）。

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
| `~/bin/hyprctl` (453 行, +x) | hyprctl 垫片：Omarchy 的 `hyprctl` 调用 → `niri msg`，纯 stdlib，不依赖 jq |
| `~/.local/share/omarchy/shell/Commons/Niri.qml` (130 行) | QuickShell 单例，轮询 niri，暴露 `workspaces/focusedWorkspace/focusedMonitor` |
| `~/bin/omarchy-niri-apply-theme` (Python, +x) | 把当前 Omarchy theme 的边框色写进 `config.kdl` 的 `focus-ring`（C 层换色） |
| `~/bin/omarchy-niri-system` (+x) | **统一系统动作入口**：logout→`niri msg action quit --skip-confirmation`、reboot→logind D-Bus `Manager.Reboot`、shutdown→logind D-Bus `Manager.PowerOff`（均免密），统一 OSD+关窗+分发 |
| `~/bin/omarchy-niri-repatch` (+x) | 上游更新后重放 niri 移植覆盖层（patch + Niri.qml + qmldir）|
| `~/bin/omarchy-powerprofiles-list` + `~/bin/omarchy-powerprofiles-set` (+x) | **TLP 感知**的电源 profile 脚本（见 §8.11）：优先 `powerprofilesctl`，缺则回退 D-Bus `net.hadess.PowerProfiles` |
| `~/.config/omarchy/hooks/theme-set.d/10-niri-border` | 换 style 时自动 `omarchy-niri-apply-theme`（只写不重载，保护 SCALE）|
| `~/.config/omarchy/hooks/post-update.d/10-niri-repatch` | `omarchy update` 后自动重放覆盖层 |
| `~/.config/omarchy/niri-port/niri.patch` + `Niri.qml` | 移植覆盖层产物（仓库外，重放用）|
| `~/.ante/projects/-home-yvonne/memory/project-omarchy-niri.md` | 项目记忆 |

### 3.2 修改

| 路径 | 改动 |
|---|---|
| `~/.local/share/omarchy/shell/Commons/qmldir` | 加一行 `singleton Niri 1.0 Niri.qml` |
| `~/.local/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml` | 去掉 `import Quickshell.Hyprland`；`Hyprland.workspaces`→`Niri.workspaces`、`Hyprland.focusedWorkspace`→`Niri.focusedWorkspace` |
| `~/.local/share/omarchy/shell/plugins/bar/Bar.qml` | 去掉 import；`Hyprland.focusedMonitor`→`Niri.focusedMonitor` |
| `~/.local/share/omarchy/shell/plugins/menu/Menu.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`（只磨砂菜单卡片，不全屏）|
| `~/.local/share/omarchy/shell/Ui/KeyboardPanel.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`（覆盖所有 bar 弹窗面板，见 §8.8）|
| `~/.local/share/omarchy/shell/plugins/background/Background.qml` | `readlinkProc` 回调强制即时切换背景（见 §8.1b）|
| `~/.local/share/omarchy/bin/omarchy-launch-tui` | 加 uid 终端回退（ghostty），因 niri 无 `uwsm-app`/`xdg-terminal-exec` |
| `~/.local/share/omarchy/bin/omarchy-theme-set` | `set_theme_background` 传实际背景文件而非过渡快照 |
| `~/.local/share/omarchy/bin/omarchy-refresh-hyprland` | **niri 感知**：`XDG_CURRENT_DESKTOP=niri` 时整脚本变 no-op（不再重建 `~/.config/hypr`）|
| `~/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc` | **菜单指向 niri 真配置**（见 §8.6）|
| `~/.config/niri/config.kdl` | 见 §5；`focus-ring` 颜色现**由主题驱动**（见 §5.6）|

### 3.3 备份（重要，可回滚）

| 备份 | 对应 |
|---|---|
| `~/.config/niri/config.kdl.bak-20260824-185918` | 最原始 niri 配置（未加 environment/spawn/binds） |
| `~/.config/niri/config.kdl.bak-port-20260824-193206` | 加了 environment 后、改 spawn/binds 前 |

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
```

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
- `Mod+Escape`（keyboard-shortcuts-inhibit / 快捷键抑制）
- `Mod+comma` / `Mod+Period`（consume / expel-column）
- `Mod+Ctrl+R`（reset-window-height）
- `Mod+Tab`（Omarchy 为 Next workspace，现让给 niri overview —— 用户指定）

### 5.6 窗口边框色跟随 Omarchy 主题（A+C 的 C 层）

Omarchy 的 look'n'feel（`looknfeel.lua`）默认把 gaps/rounding/动画/layout 全注释掉走 Hyprland
默认值，style 真正落到合成器上的只有**窗口边框色**：生成的 `theme/hyprland.lua` 里
`active_border_color` / `inactive_border_color`（catppuccin 为 `#89b4fa` / `rgba(595959aa)`）。

niri 上这个颜色由 `config.kdl` 的 `focus-ring` 块决定。`omarchy-niri-apply-theme`（Python）读当前
`theme/hyprland.lua`，把 `active-color`/`inactive-color` 就地写进 `focus-ring`（Hyprland 的
`rgba(rrggbbaa)` 归一化成 niri 的 `#rrggbbaa`），并备份
`config.kdl.bak-niri-theme`。默认只写不重载：重载会重置 niri 的运行时覆盖
（如 SCALE 按钮改的 scale/mode），所以换色在下次 `load-config-file`/重启时生效。

```sh
~/bin/omarchy-niri-apply-theme        # 只写 config.kdl
~/bin/omarchy-niri-apply-theme --reload  # 写 + niri msg action load-config-file
```

换 style 时由 `theme-set.d/10-niri-border` 钩子自动触发（只写，不重载）。

---

## 6. Niri.qml（QuickShell 数据单例）

核心逻辑：每 500ms 轮询 `niri msg -j workspaces` 和 `niri msg -j windows`，
组装出一个仿 `Hyprland.workspaces` 的模型，供 Bar 的 Workspaces.qml / Bar.qml 使用。

- `root.workspaces.values[]` 每项含：`niriId, id, name, output, active, focused,
  toplevels.values[]`（`toplevels.values.length` 由 windows 按 workspace_id 计数得出）。
- `root.focusedWorkspace` = 当前聚焦 workspace。
- `root.focusedMonitor` = `{ "name": 聚焦 workspace 的 output }`。
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
4. patch `Bar.qml` / `Workspaces.qml`（见 §3.2）。
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

---

## 8. 已知缺口与待办

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
   `Mod+K`=keybindings、`Mod+Ctrl+L`=锁屏 让给 Omarchy。`Mod+Ctrl+R`/`Mod+comma`/`Mod+Escape`
   仍被 niri 占用，待后续让出。
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
10. **overview 壁纸与桌面统一（需求，2026-08-25 实测收窄）**：niri 总览（`Mod+O` / `Mod+Tab` 触发
    `toggle-overview`）的背景是**不透明深色**，不与桌面一致。桌面壁纸由 `shell/plugins/background/Background.qml`
    的 layer-shell（`Background` 层，namespace `omarchy-background`）绘制；本回合实测：
    - overview 开启时 `niri msg layers` 只有 `omarchy-background` + `omarchy-bar`，**没有**其它深色填充层，
      即那层深色背景是 niri overview 自己合成上去的。
    - 把 `config.kdl` 的 `layout { background-color "#ff00ff" }` 设成品红并 `load-config-file` 后，
      overview 背景**仍是深色不变**，证明 overview 的背景**不是** `background-color` 驱动。
    - 结论：overview 深色垫层由 niri 合成器绘制、压在 layer-shell 壁纸之上，且不吃 `background-color`。
      要复用桌面壁纸需要另想办法（如让壁纸元素在 overview 时上浮/换层级），待定。
11. **电池面板 POWER PROFILE 区为空（2026-08-25 已修）**：系统电源后端是 **TLP**（`tlp` + `tlp-pd`
    `1.10.2`），**不是** power-profiles-daemon —— `powerprofilesctl` 不存在，而 Omarchy 的
    `omarchy-powerprofiles-list`/`-set` 硬依赖它，故电池面板的 POWER PROFILE 区读不到任何 profile（空）。
    修复：在 `~/bin/` 放同名适配脚本（PATH 优先于仓库、挺过 `omarchy update`），**优先**用
    `powerprofilesctl`，缺则回退 D-Bus `net.hadess.PowerProfiles`（`/net/hadess/PowerProfiles`，
    `.ActiveProfile` 可写、`.Profiles` 为 `a{sv}`）。实测：
    - list 返回 3 个 profile（performance/balanced/power-saver），`--active-state` 正确标出 active（power-saver）。
    - set 写入经 `busctl set-property` 生效，但 tlp-pd 是**异步**经 detached TLP 应用，立即读会是旧值，
      需稍等再读。当前活跃 profile 已恢复为 power-saver。

12. **菜单 Apps 列表启动全部失灵（2026-08-27 已修）**：菜单 "Apps" provider 经
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
  现已分别指向 `monitor.kdl` / `binds.kdl` / `input.kdl`——仓库 `omarchy-menu.jsonc`（进 `niri.patch`）
  + 用户级 `~/.config/omarchy/extensions/omarchy-menu.jsonc` override 双保险。

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
- **仓库内会撞**：我们改了仓库内 14 个文件（launch-tui、refresh-hyprland、theme-set、menu.jsonc、qmldir、
  Background.qml、Bar.qml、Workspaces.qml、Menu.qml、KeyboardPanel.qml、AppLibrary.qml，以及
  2026-08-25 加的 3 个 `omarchy-system-{logout,reboot,shutdown}`）+ 新增 `Niri.qml`。上游改到其中任何一个，
  `git pull --ff-only` 会因本地未提交改动而**失败中止**整个更新——这是需要手动合并的情况。
- **自动重放**：`post-update.d/10-niri-repatch` 在每次更新后跑 `omarchy-niri-repatch`：
  1. 把 `~/.config/omarchy/niri-port/Niri.qml` 拷回 `shell/Commons/`。
  2. `git apply` `niri.patch`；已应用则 `--reverse --check` 判 no-op（幂等）。
  3. 冲突则**不做任何改动**、退出码 2，提示手动合并（找 Ante）。
- 说明：覆盖层脚本只处理"上游没改到我们文件"的更新（此时 FF 成功、重放是 no-op）；
  "上游改到同一函数"才需要我重新翻译合并——这是任何移植都绕不开的兜底。

### 8.8 视觉磨砂（frosted Quickshell / 状态栏面板毛玻璃）

niri 26.04 的 `background-effect` + Quickshell 的 `ext_background_effect` 形状磨砂，让 Omarchy shell
的卡片呈毛玻璃。设计原则：**绝不让 niri 侧对整面 layer-shell 做全屏模糊**（那会把整个屏幕霜化），
而是每个面板用 `BackgroundEffect.blurRegion` 只磨砂自己的卡片区域。

**仓库内改动（已进 `niri-port/niri.patch`，现共 14 个文件 / 23 个 hunk）**：
- `shell/plugins/menu/Menu.qml`：加 `import Quickshell.Wayland._BackgroundEffect`，根 `PanelWindow`
  挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`。
- `shell/Ui/KeyboardPanel.qml`：同上，根 `PanelWindow` 挂
  `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`。**所有 bar 弹窗面板**
  （audio/bluetooth/clock/dropbox/monitor/network/power/tailscale/weather + agent 面板）都复用
  `KeyboardPanel`，所以这一处改动统一磨砂了它们全部（一次覆盖 9+ 面板）。

**仓库外 Layer-1 配置（pull 安全，不在 `niri.patch` 内）**：
- `~/.config/niri/effects.kdl`（被 `config.kdl` `include`）：全局
  `blur { passes 4; offset 3.5; noise 0.03; saturation 1.6 }` + 两条 layer-rule：
  - `^omarchy-bar$` / `^omarchy-osd$` / `^omarchy-notifications$` → `background-effect { blur true; xray true }`
    （bar 保留独占区，只磨砂背后壁纸，稳定）。
  - `^omarchy-keyboard-panel$` → `background-effect { xray false }`（**只设 xray，不设 `blur true`**——
    Quickshell 已发卡片形状区域，该区域就是唯一磨砂范围，全屏 surface 不会霜化）。`xray false` =
    磨砂卡片背后的**实时窗口**（真毛玻璃）；`xray true` = 只磨砂壁纸。
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
- [x] C 层：`omarchy-niri-apply-theme` 写入 `#89b4fa`/`#595959aa`，`niri validate` 通过、热重载 OK。
- [x] 更新覆盖层：`omarchy-niri-repatch` 幂等（已应用判 no-op；stash 还原后能干净重放）。
- [x] `theme-set`/`post-update` 钩子触发正常、非 niri 静默跳过。
- [ ] 截图/剪贴板 CLI 全链路实测（slurp/grim 交互，需桌面环境）。
- [ ] Omarchy 锁屏（`Mod+Ctrl+L`）在 niri 上实测。
- [ ] 真实跑一次 `omarchy update`，确认上游变更时覆盖层自动重放或明确报冲突。
- [x] **logout/reboot/shutdown** 统一标准化：`~/bin/omarchy-niri-system` 单一入口（logout→niri quit、reboot/shutdown→logind D-Bus `Manager.Reboot/PowerOff`；`loginctl` 无该 verb 是本 bug，已改；`pkcheck` 免密 exit 0 验证）。
- [x] **电源 profile**：`~/bin/omarchy-powerprofiles-list` 返回 3 个 profile、active 标记正确；set 经 TLP D-Bus 生效（异步应用，恢复为 power-saver）。
- [ ] 运行实测：注销、关机、重启（会结束会话/重启，交给用户）。
- [ ] **overview 壁纸与桌面统一**。
- [x] **菜单 override label+icon 修复（2026-08-27）**：`extensions/omarchy-menu.jsonc` 的 3 个 setup 项补全 label+icon，合并后显示 "Monitors"/"Keybindings"/"Input" 且图标正常（不再显示 raw id `setup.monitors` 之类）；根因是 `normalizeItem` 的 `label: value.label || id` 把 action-only override 的 label 退化成 id 并覆盖默认项。
- [x] **视觉磨砂（frosted Quickshell）**：`Menu.qml` + `KeyboardPanel.qml` 挂 `BackgroundEffect.blurRegion`（只磨砂卡片，不全屏）；`effects.kdl` 给 `omarchy-keyboard-panel` 设 `xray false`（实时窗口毛玻璃）；`[popups]` alpha 0.8→0.65。面板开/关屏幕底部清晰度 on/off≈0.995 → 无全屏霜化。niri.patch 现 13 hunk，覆盖层重放幂等。

---

## 10. 关键环境信息

- 用户 `yvonne`（uid 1001, gid 1003, groups wheel）；隔壁 `jianlongliu` uid 1000。
- niri 26.04 (8ed0da4) 位于 `/usr/bin/niri`。
- 显示管理器：greetd / dms-greeter。包管理器 paru。
- 电源后端：**TLP**（`tlp` + `tlp-pd` 1.10.2，D-Bus `net.hadess.PowerProfiles`），**无** power-profiles-daemon（`powerprofilesctl` 缺失）。
- `sudo` 需密码（非交互不可用）。
- 读取 `HYPRLAND_INSTANCE_SIGNATURE is unset` 警告仅影响便捷性，QuickShell 在 layer-shell
  下照常渲染。
