# Omarchy on niri — 移植方案与运维文档

> 目的：把 DHH 的 Omarchy v4（原本 Arch + Hyprland + QuickShell）移植到 niri
> 滚动平铺 Wayland 合成器上，运行在主账户（原实验账户已回迁），并保持 niri 原生体验。
> 本文档是"上下文丢失也能重建"的持久记录。最后更新：2026-09-19（文档合并：`~/Documents` 母本与
> 仓库 `docs/omarchy-on-niri-port.md` 归并为一，两份逐字节一致；补回仓库版缺的 §5.7/§5.8、媒体键 OSD、
> `binds` 递归展开、发布流程等块，并补入仓库版今天的 §8.9 上游合并基线与 §9/§10 新条目；新增
> §8.10 主题动态取色、§8.11 bar 插件层；修正 §5.6 C 层回归（已修）、§8.8 浮栏模糊规则变更）。
> 2026-09-20 追加 §8 第 25–30 条（选择器异步解码、按键静默拒载、不透明 app 磨砂、bar 内联设置、gaps 16→8、
> 菜单卡片底色），并同步 §3.2/§3.3/§5.3/§9 的计数与几何数字。
> 2026-09-20 深夜**分卷**：锁屏与登录整节抽出为 `docs/lock.md`（本卷对应位置留同名编号指针），
> 另新增 `docs/local-overrides.md` 记本机全部改动落点与回退方式。
> 2026-09-20 深夜**模块化拆分（第二刀）**：原 §8「已知缺口、待办与专题记录」是 1232 行的编号流水账
> （32 条编号条目 + 14 个 `§8.x` 子节），现按模块拆成独立卷。**编号一个字都没改** —— `§8 第 N 条`、
> `§8.x`、`§11.x` 都是原号，原处只留指针与映射表，仓库里既有的引用继续解析得到。
> 2026-09-20 深夜**文档归一**：取消「母本 + 仓库镜像」双写 —— `docs/` 就是唯一正本，
> `~/Documents/omarchy-niri-*.md` 改成了指向它的软链（2026-09-21 那九个软链、连同守它们的
> `scripts/check-doc-links.sh` 一并删掉：正本在 `docs/`，不需要入口层）。

---

## 0. 文档地图（模块）

> **本文 = 当前事实**：硬性约束、架构、文件清单、niri 配置当前值、部署步骤、验证清单、环境信息。
> **各模块卷 = 专题记录**：当时怎么发现的、试过什么、为什么这么定、坑在哪。改动发生在哪一卷，
> 就去哪一卷查；两边都有指针，不用猜。

| 卷 | 文件（正本） | 管什么 |
|---|---|---|
| 主文档（本文） | `docs/omarchy-on-niri-port.md` | 当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境 |
| 视觉调整 | `docs/visual.md` | 磨砂全栈、字号与 DPI、边框环、菜单底色、gaps、overview、主题取色、壁纸库、缩放、bar 内联排布 |
| 功能调整 | `docs/behavior.md` | 按键与去重、system 动作、电源与背光、screensaver、输入源、菜单行为、选择器性能与预热、耗电专项 |
| 插件 | `docs/plugins.md` | bar 插件层、逐插件魔改与运维（含原 §8.11） |
| 垫片 | `docs/shims.md` | `hyprctl`（原 §4）、`uwsm-app`、`omarchy-update`、`display-text-size`、`picker-warmup` 等 PATH-first 覆盖脚本 |
| 上游跟进 | `docs/upstream.md` | 覆盖层重放、合并基线、上游小更新、发布流程 |
| 账户迁移 | `docs/migration.md` | 实验账户 → 主账户的完整方案与执行清单（原 §11） |
| 锁屏 / 登录 | `docs/lock.md` | 锁面、greeter、人脸、greetd wedge |
| 本机改动总账 | `docs/local-overrides.md` | 这台机器相对仓库**多出/改过**的一切与回退方式 |

文档只有一份，就在仓库里（上表第三列），没有第二处副本；`~/Documents` 下曾有的那九个软链
（2026-09-20 文档归一的产物）与守它们的 `scripts/check-doc-links.sh` 于 2026-09-21 一并删掉。

---

## 1. 硬性约束（不可违背）

1. ~~**不破坏隔壁主账户（uid 1000）**，用户仍在使用。~~ —— **迁移前（实验账户时代）的约束，2026-09-19 起自然失效**：
   移植现在**就是** uid 1000 的会话本身，`/home/<dev-user>/` 一律等于 `~`。原文留档：
   - 所有改动只落在 `/home/<dev-user>/`（`~/.config`, `~/.local`, `~/bin`）。
   - 不写 `~`，不运行影响全系统的安装。
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
| `~/bin/omarchy-niri-apply-theme` (Python, +x) | 把当前 Omarchy theme 的边框色写进 niri 的环（C 层换色）；**沿 `include` 定位**含 `focus-ring` 的模块；色源是菜单同款 token，三色渐变拆成 `focus-ring`+`border` **两带**（角度 +90，§5.6） |
| `~/bin/materal-update` (Python, +x) | **主题动态取色生成器**：读当前壁纸 → matugen 出 M3 配色 → 映射成 omarchy `colors.toml` → 重套主题（§8.10；仓库副本 `port-bin/materal-update`） |
| `~/.config/omarchy/themes/tonal-spot/` | 用户级主题（`matugen.toml` + 自生成 `backgrounds/` + 静态 ANSI 16 色），`omarchy theme set Tonal-Spot` 选用（§8.10） |
| `~/.config/omarchy/hooks/theme-set.d/20-materal` | 换 theme 时重新取色（与 `10-niri-border` 并列，§8.10；仓库副本 `hooks/theme-set.d/20-materal`） |
| `~/.config/systemd/user/materal-recolor.{path,service}` | 盯 `current/` 与 `current/background` 的 path/service 单元：换壁纸即自动重取色（§8.10；仓库副本 `local-config/systemd/user/`） |
| `~/.config/ghostty/config` | **磨砂五处里的 ghostty 那一处**：`background-blur-radius = 0`（niri 不实现 KDE blur 协议，叠起来是双层模糊）+ `background-opacity = 0.85` + `window-decoration = false`；配色跟上 Omarchy 主题（`config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"`，§8.10；仓库副本 `local-config/ghostty/config`）|
| `/usr/local/bin/ir-light` | 点亮内置 IR 灯，供 howdy 在暗光下人脸识别；`/etc/pam.d/{omarchy-lock-face,greetd}` 用 `pam_exec.so` 调它（`optional`，坏了不锁人）。**硬件专属**（写死 `/dev/video2` + UVC unit 13/selector 14），仓库副本 `split-lock/ir-light` |
| `~/.config/omarchy/plugins/jianlongliu.arch-logo/`、`~/.config/omarchy/plugins/jianlongliu.workspaces/` | 用户级 bar 部件（仓库外、抗 `omarchy update`）：Arch logo、胶囊式工作区指示（§8.11；前者是自研、无 `clonedFrom`，源码副本 `plugins/jianlongliu.arch-logo/`；后者 = 上游克隆 + `plugin-patches/jianlongliu.workspaces.patch`） |
| `~/.config/omarchy/plugins/ronald.input-sources/` | 第三方 bar 部件：fcitx5 输入源徽章/切换菜单（`omarchy plugin add … --enable` 装的 git 克隆；仓库外、抗更新，§8.17） |
| `~/.config/omarchy/backgrounds/{tonal-spot,catppuccin}` | 共享壁纸库软链 → `/data/Pictures/Wallpapers`（所有主题翻同一套图，§8.12） |
| `~/omarchy-wallpaper-aio/` | 参考仓库 `jianlongliu/omarchy-wallpaper-aio` 的克隆：只含 `setup.sh`（把主题背景目录软链到壁纸库，§8.12） |
| `~/bin/omarchy-niri-system` (+x) | **统一系统动作入口**：logout→`niri msg action quit --skip-confirmation`、reboot→logind D-Bus `Manager.Reboot`、shutdown→logind D-Bus `Manager.PowerOff`（均免密），统一 OSD+关窗+分发 |
| `~/bin/uwsm-app` (+x) | **uwsm-app 垫片**：把 Omarchy `bin/` 里 ~30 处 `uwsm-app -- <cmd>` 调用一次救活（niri 会话没有 uwsm，原本全部静默死在 `setsid: failed to execute uwsm-app`）；丢掉 uwsm-app 自身选项后**原样 `exec "$@"`**——**故意不加 `setsid`**（2026-09-20，v1.1：会让 `systemd-run` 的 unit 秒退并清 cgroup，见 §8 第 22 条）；不做 systemd scope 记账（§8 第 22 条；仓库副本 `port-bin/uwsm-app`，离线回归测试 `port-bin/tests/test-uwsm-app-shim.sh`，13 项含 systemd-run 那条）|
| `~/bin/omarchy-niri-repatch` (+x) | 上游更新后重放 niri 移植覆盖层（patch + `Niri.qml` + `plugins/*`）|
| `~/bin/omarchy-powerprofiles-list` + `~/bin/omarchy-powerprofiles-set` (+x) | **TLP 感知**的电源 profile 脚本（见 §8 第 11 条）：优先 `powerprofilesctl`，缺则回退 D-Bus `net.hadess.PowerProfiles` |
| `~/bin/omarchy-update` (+x) | 手装（dev-link）机的 update 垫片 = `sudo pacman -Syu`：上游流程会卡在 `omarchy-update-keyring`（没配 Omarchy 仓库）、再用 yay，中途却已跑无人值守 `pacman -Syu --noconfirm`。拦得住菜单/bar 的裸调 `omarchy-update`，拦不住 CLI 的 `omarchy update`（dispatcher 走绝对路径）。仓库 `port-bin/omarchy-update` |
| `~/bin/omarchy-picker-warmup` (+x) + `~/.config/systemd/user/omarchy-picker-warmup.service` | 登录后 45s 延迟预热主题/背景选择器（读缩略图进页缓存；`Nice=19`/IO idle；`toggles/picker-warmup-off` 即关，§8 第 25 条）。仓库 `port-bin/omarchy-picker-warmup` + `default/systemd/user/omarchy-picker-warmup.service`（`%h` 模板） |
| `~/bin/omarchy-display-text-size` (+x) | bar 的 Display 面板 TEXT SIZE 滑块垫片：官方脚本只管 shell `[font]`/GTK factor/终端 pt，这个补 GTK dconf+settings.ini、Qt(qt6ct)、fcitx5、XSETTINGS 各层（§8.19）。仓库 `port-bin/omarchy-display-text-size` |
| `~/.config/omarchy/hooks/theme-set.d/10-niri-border` | 换 style 时自动 `omarchy-niri-apply-theme`（只写不重载，保护 SCALE）|
| `~/.config/omarchy/hooks/post-update.d/10-niri-repatch` | `omarchy update` 后自动重放覆盖层 |
| `~/.config/omarchy/niri-port/`（`niri.patch` + `Niri.qml` + `plugins/` + `plugin-patches/` + `backups/`）| 移植覆盖层产物（仓库外，重放用）。**当前：`niri.patch` 22 文件 / 48 hunk**，`--reverse --check` 通过、repatch 幂等，md5 `6138cc1bece9a94312572d8685c845a4`（2026-09-21 晚重导出核，与仓库 `niri-port/niri.patch` 一致）；本次重导出是把活体先改、补丁没跟上的两处（`Background.qml` 的 `paintedOnce`、`shell.qml` 的 `pushBootReveal()` 增补）补进补丁 —— 补上之前 repatch 判 exit 2，安全网是断的；本机在用的浮动 bar 的改动在 `niri-port/plugin-patches/charlieras262.floating-bar.patch`（无自动重放器）|
| `~/.ante/projects/-home-<user>/memory/`（`omarchy-niri-migration.md` 等） | 项目记忆（旧实验账户侧那份已废弃） |

### 3.2 修改

| 路径 | 改动 |
|---|---|
| `~/.local/share/omarchy/shell/Commons/qmldir` | 加一行 `singleton Niri 1.0 Niri.qml` |
| `~/.local/share/omarchy/shell/Commons/Style.qml` | `applyShellValues()` 的 `[bar]` 分支原来只认 `scale-with-font` + 两个 size 键、**其余键静默丢弃**；扩成 `Style.bar` 全部整型 token，于是 `[bar] icon-font = 12` 这类调法能从 `shell.toml` 热改（见 §8 第 31 条） |
| `~/.local/share/omarchy/shell/shell.qml` | 标记读取：真登录时（`$XDG_RUNTIME_DIR/omarchy-boot-splash`，由 `split-greeter/session.sh` 落、读完即 `rm`）把 `bootRevealArmed` 置真，`omarchy-restart-shell` 不重放（§8 第 33 条） |
| `~/.local/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml` | 去掉 `import Quickshell.Hyprland`；`Hyprland.workspaces`→`Niri.workspaces`、`Hyprland.focusedWorkspace`→`Niri.focusedWorkspace` |
| `~/.local/share/omarchy/shell/plugins/menu/Menu.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`（只磨砂菜单卡片，不全屏，见 §8.8）|
| `~/.local/share/omarchy/shell/Ui/KeyboardPanel.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`（覆盖所有 bar 弹窗面板，见 §8.8）|
| `~/.local/share/omarchy/shell/plugins/bar/Bar.qml` | 去掉 import；`Hyprland.focusedMonitor`→`Niri.focusedMonitor`；**boot reveal**：`bootRevealArmed` → `bootReveal` 归 0 → `BarPanel` 用 `margins` 把 bar surface 停屏外（alpha/opacity 一起 0），1500ms 后 900ms `OutCubic` 滑入（§8 第 33 条） |
| `~/.local/share/omarchy/shell/plugins/osd/Osd.qml` | OSD 改"卡片大小 surface" + 磨砂（§8.8） |
| `~/.local/share/omarchy/shell/plugins/notifications/Service.qml` | 加 `import Quickshell.Wayland._BackgroundEffect`；吐司根 `PanelWindow` 挂 `BackgroundEffect.blurRegion: Region { item: popupColumn; radius: service.cornerRadius }`。**注意它与 OSD 相反：吐司 surface 必须保持全屏**（免得增删吐司时缩放着形），所以那条 namespace 不能再给 `blur true`（§8 第 32 条 / §8.8）|
| `~/.local/share/omarchy/shell/services/AppLibrary.qml` | 加 `command -v uwsm-app` 回退（niri 无 uwsm-app，§8 第 14 条） |
| `~/.local/share/omarchy/shell/plugins/background/Background.qml` | `readlinkProc` 回调强制即时切换背景（见 §8 第 1 条 b）|
| `~/.local/share/omarchy/shell/plugins/image-picker/ImagePicker.qml` | 切片 `Image` 改 `asynchronous: true`（首帧不再同步解码 33 张缩略图，§8 第 25 条）|
| `~/.local/share/omarchy/shell/plugins/panels/power/Panel.qml` | 电量部件的 `text` 由 `"50% 🔋"` 改成 `"🔋 50%"`（数字落到 bar 最右，§8 第 28 条）|
| `~/.local/share/omarchy/bin/omarchy-launch-tui` | 加 uid 终端回退（ghostty），因 niri 无 `uwsm-app`/`xdg-terminal-exec`；2026-09-19 起垫片在位时走 `uwsm-app` 分支（§8 第 22 条）|
| `~/.local/share/omarchy/bin/omarchy-launch-editor` | 同上：`uwsm-app` 存在才用、否则直接 `setsid $editor` 启动（niri 无 uwsm）；2026-09-19 起垫片在位时走 `uwsm-app` 分支（§8 第 22 条）|
| `~/.local/share/omarchy/bin/omarchy-launch-floating-terminal-with-presentation` | 同上：`uwsm-app`+`xdg-terminal-exec` 缺时遍历 `ghostty/kitty/alacritty/foot` 起演示终端；2026-09-19 起垫片在位时走 `uwsm-app` 分支（§8 第 22 条）|
| `~/.local/share/omarchy/bin/omarchy-theme-set` | 背景走持久文件而非过渡快照（niri 黑桌面竞态，见 §8.9） |
| `~/.local/share/omarchy/bin/omarchy-system-{logout,reboot,shutdown}` | 转调 `~/bin/omarchy-niri-system`（niri quit / logind D-Bus，§8 第 9 条） |
| `~/.local/share/omarchy/bin/omarchy-refresh-hyprland` | **niri 感知**：`XDG_CURRENT_DESKTOP=niri` 时整脚本变 no-op（不再重建 `~/.config/hypr`）|
| `~/.local/share/omarchy/default/omarchy/omarchy-menu.jsonc` | **菜单指向 niri 真配置**（见 §8.6）；2026-09-19 给 `install.package` / `install.aur` / `remove.package` 加 `xdg-terminal-exec` 回退（§8 第 21 条）|
| `~/.config/niri/config.kdl` | 编排器：`environment`/`spawn`/`animations`/`screenshot-path` + 6 个 `include`（§5.7）；`focus-ring` 在 `layout.kdl`，颜色由主题驱动（§5.6）|
| `~/.config/niri/{input,monitor,layout,window-rules,effects,binds}.kdl` | 模块化拆分出的子配置（§5.7）：输入/显示器/布局/窗口规则(含圆角)/磨砂(effects)/按键 |
| `~/.config/niri/effects.kdl` | 2026-09-19 给 `^omarchy-bar$` 配 `background-effect { xray false }`（浮栏磨砂；圆角模糊区域由插件端下发，§8.8）|
| `~/.config/omarchy/shell.json` | bar：`id` = `charlieras262.floating-bar`、`floatGap` 8、`cornerRadius` 10；`layout.left` = `jianlongliu.arch-logo` + `jianlongliu.workspaces`；`layout.right` 2026-09-19 摘掉空转的 `charlieras262.omablur`、并由 `ronald.input-sources` 取代 `ryuhzk.ime`；`layout.center` 同日摘掉 `omarchy.keyboard-layout`（与插件徽章重复，§8.11、§8.17）；2026-09-20 `layout.right` 的 `omarchy.power` 加 `"showPercentage": true`、`layout.center` 摘掉 `omarchy.system-update`（§8 第 28 条）|
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
>
> 2026-09-20 新留的三个（本轮 bar / gaps / 菜单底色，就地放同目录）：`~/.config/omarchy/shell.json.bak-20260920-bar`、
> `~/.config/omarchy/shell.toml.bak-20260920-menu`、`~/.config/niri/layout.kdl.bak-20260920-gaps`（§8 第 28–30 条）；
> 电量数字置右那轮另有两个：`~/.local/share/omarchy/shell/plugins/panels/power/Panel.qml.bak-20260920-pctorder`、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260920-pctorder`。
>
> 2026-09-20 下半场（bar 字号统一，§8 第 31 条）新留四个：`~/.local/share/omarchy/shell/Commons/Style.qml.bak-20260920-bartoken`、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260920-bartoken`、`~/.config/omarchy/shell.toml.bak-20260920-iconfont`、
> `~/.config/omarchy/shell.json.bak-20260920-bardisplay`（后者是恢复 ai-subs `barDisplay` 前的快照）。
>
> 2026-09-20 晚间（吐司"一有通知整屏变糊"，§8 第 32 条）新留三个：
> `~/.local/share/omarchy/shell/plugins/notifications/Service.qml.bak-20260920-notifblur`、
> `~/.config/niri/effects.kdl.bak-20260920-blurnotif`、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260920-notifblur`。
>
> 2026-09-21（交接过渡，`docs/visual.md` 第 33 条 / `docs/lock.md` §11.26）新留几个：
> `~/.local/share/omarchy/shell/shell.qml.bak-20260921-bootcurtain`（= 上游 HEAD 版，单文件回退用）、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260921-bootcurtain`（= 21 文件/38 hunk 那版）、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260921-bootcurtain2`（= 22 文件/40 hunk 的黑幕版）、
> `~/.config/omarchy/niri-port/niri.patch.bak-20260921-bootreveal`（= 22 文件/45 hunk 的"内置 bar 滑入"版；当前版在其上加了宿主推送，并把真正生效的浮动 bar 挪进插件补丁）。
> `~/.config/omarchy/niri-port/niri.patch.bak-20260921-192644`（= 22 文件/46 hunk 版；活体已经改出 `paintedOnce` / `pushBootReveal()` 增补而补丁没跟上，repatch 一度 exit 2，当晚重导出为 48 hunk 版）。

---

## 4. hyprctl 垫片（`~/bin/hyprctl`）

> **已拆入垫片卷**：正文（子命令映射表、`cmd_binds` 的 `include` 递归展开、Hyprland-only 字段的
> 占位处理）在 `docs/shims.md` 的 **§4**（编号保留）。

## 5. niri 配置（`~/.config/niri/config.kdl`）

### 5.1 environment 块（注意语法：`KEY "value"`，无 `=`，无 `$PATH` 展开）

```kdl
environment {
    OMARCHY_PATH "/home/<dev-user>/.local/share/omarchy"
    PATH "/home/<dev-user>/bin:/home/<dev-user>/.local/share/omarchy/bin:/home/<dev-user>/.local/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/usr/sbin:/bin:/sbin"
}
```

niri 语法要点：**不能写 `=`，不能写 `$PATH`**（不会展开），必须写全字面 PATH。

### 5.2 启动 QuickShell（替换 niri 自带的 waybar）

```kdl
spawn-sh-at-startup "quickshell -n -p /home/<dev-user>/.local/share/omarchy/shell"
```

### 5.3 Omarchy 绑定（不冲突子集）

**2026-09-19/20 已按「每功能只留一个键」去重**（用户要求；被合并的旧键在 `binds.kdl` 里就地注释成
`// dropped: …` 保留，要恢复取消注释即可；原委见 §8 第 24 条）：

```kdl
Mod+D             hotkey-overlay-title="Apps menu"    { spawn-sh "omarchy-menu toggle apps"; }
Mod+Space         hotkey-overlay-title="Omarchy Menu" { spawn-sh "omarchy-menu toggle"; }
Mod+Return        hotkey-overlay-title="Terminal"     { spawn-sh "omarchy-launch-terminal"; }
Mod+L             hotkey-overlay-title="Lock screen"  { spawn-sh "omarchy-system-lock"; }
Mod+E             hotkey-overlay-title="Files"        { spawn "nautilus"; }
Mod+Z             hotkey-overlay-title="Browser"      { spawn-sh "omarchy-launch-browser"; }
Mod+Y             hotkey-overlay-title="Yazi"         { spawn-sh "omarchy-launch-terminal --app-id=org.omarchy.float-tui yazi"; }
Ctrl+Shift+Escape hotkey-overlay-title="btop"         { spawn-sh "omarchy-launch-terminal --app-id=org.omarchy.float-tui btop"; }
Mod+K             hotkey-overlay-title="Keybindings"  { spawn-sh "omarchy-menu-keybindings"; }
Mod+Ctrl+V       hotkey-overlay-title="Clipboard"    { spawn-sh "omarchy-shell shell toggle omarchy.clipboard"; }
Mod+Ctrl+E       hotkey-overlay-title="Emojis"       { spawn-sh "omarchy-shell shell toggle omarchy.emojis"; }
Mod+Ctrl+A       hotkey-overlay-title="Audio"        { spawn-sh "omarchy-shell shell toggle omarchy.audio"; }
Mod+Ctrl+B       hotkey-overlay-title="Bluetooth"    { spawn-sh "omarchy-shell shell toggle omarchy.bluetooth"; }
Mod+Ctrl+D       hotkey-overlay-title="Display"      { spawn-sh "omarchy-shell shell toggle omarchy.monitor"; }
Mod+Ctrl+W       hotkey-overlay-title="Network"      { spawn-sh "omarchy-shell shell toggle omarchy.network"; }
Mod+Ctrl+P       hotkey-overlay-title="Power"        { spawn-sh "omarchy-shell shell toggle omarchy.power"; }
Mod+Ctrl+Alt+D   hotkey-overlay-title="Calendar"     { spawn-sh "omarchy-shell shell toggle omarchy.clock"; }
Mod+Q            repeat=false                        { close-window; }
Alt+F4                                               { close-window; }
Mod+Shift+E                                          { quit; }
Print            { spawn-sh "omarchy-capture-screenshot"; }
Ctrl+Alt+Delete  hotkey-overlay-title="System menu"  { spawn-sh "omarchy-menu toggle system"; }
Mod+Shift+Escape allow-inhibiting=false              { toggle-keyboard-shortcuts-inhibit; }
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
`omarchy-niri-apply-theme`（Python）**沿主题生成链路取色**，不自己拍颜色：

- 色源是 `theme/shell.toml` 的 `[hyprland] active-border-foreground` —— **omarchy menu 卡片那圈用的
  就是它**（`[menu] border = "hyprland.active-border-foreground"`），由 matugen 出的
  `primary → tertiary → primary_container` 45°（`colors.toml` 的 `hyprland_active_border`）经
  `omarchy-theme-set-templates` 渲染而来；主题没生成 shell.toml 时回落到 `theme/hyprland.lua` 的 Lua table。
- 写进 `layout.kdl` 的是**两带**（因为 niri 26.04 **每个渐变色只吃两停**，`colors="#a" "#b" "#c"`
  列表被 `niri validate` 拒，见 §5.6 末尾）：
  - `focus-ring`（画在窗口**外侧**）：`active-color`（首色站，兼作 fallback）+ `active-gradient
    from=<首> to=<中> angle=<主题角度+90>` —— 渐变的前半段；
  - `border`（画在窗口**内侧**）：`on` + `active-color`（中间站）+ `active-gradient from=<中>
    to=<末> angle=<主题角度+90>` + `inactive-*` 全透明 —— 渐变的后半段。
  两带在中间站接头，合起来才是主题那条三色渐变；主题边框退回平色/两停时脚本自动改回单带
  （`focus-ring` 一条渐变 + `border off`）。写前备份 `.bak-niri-theme`。
- 脚本只管颜色和 `border` 的 on/off，**不动宽度**（当前两处各 `width 2`）。`border` 的色带画在
  tile **内部**，所以要占内容 2 逻辑像素：`niri msg --json windows` 里 `window_size` 612×724
  对 `tile_size` 616×728、`window_offset_in_tile` `[2,2]`；未聚焦窗的 border 透明，看起来仍是原先的无框。
- 默认只写不重载：重载会重置 niri 的运行时覆盖（如 SCALE 按钮改的 scale/mode），所以换色在下次
  `load-config-file`/重启时生效。

```sh
~/bin/omarchy-niri-apply-theme              # 只写（两带，默认）
~/bin/omarchy-niri-apply-theme --reload     # 写 + niri msg action load-config-file
~/bin/omarchy-niri-apply-theme --single-band  # 单带对比版：环=首→末、border off（丢掉中间站）
```

换 style 时由 `theme-set.d/10-niri-border` 钩子自动触发（只写，不重载）。

> ✅ **回归已修（2026-09-19）**：模块化拆分（§5.7）把 `focus-ring` 块搬进 `layout.kdl`，而脚本的写入
> 目标一直硬编码 `config.kdl`（`NIRI_CFG`），于是**每次换主题都静默失败**（`no focus-ring block found
> in config.kdl`，退出码 1），窗口边框色自拆分以来一直停在旧值，`theme-set` 才以为"已应用"。
> 修法（不再写死文件名，将来再挪模块也不会断）：
> - **沿 `include` 指令递归**找含 `focus-ring` 的模块（脚本自己走 include 树，与垫片 `cmd_binds`
>   同一思路），找到即写。
> - **支持渐变**：`hyprland.lua` 里 `active_border_color` 可能是 Lua **table**
>   （`{ colors = { "rgba(...)", ... }, angle = 45 }`）而非字符串。第一版只取**首个色站**（纯色环），
>   2026-09-19 晚起改为写 `active-gradient`，见下一条。
> 验证：`omarchy theme set Tonal-Spot` 后 `layout.kdl` 的 `focus-ring` 变成该主题的
> `active_border_color`（见 §9）。脚本在 `~/bin/`，不在 omarchy 仓库内，故不进 `niri.patch`。

> ✅ **环改成与菜单同一条渐变（2026-09-19 晚）**：原先只写首色站，环是纯粉、和菜单那圈对不上。
> 现在色源换成菜单同款 token（`theme/shell.toml [hyprland] active-border-foreground`，同样是 matugen
> 那条 `primary→tertiary→primary_container` 45°）。
>
> ⚠️ **角度必须 +90**：壳层 `shell/Commons/BorderGeometry.js` 从 **+x 轴向下**量角度（45° = 右下），
> niri 走 CSS `linear-gradient` 约定（0 = 上、顺时针），所以主题的 45° 要写成 `angle=135`。
> 写成 45 时环的粉端跑到了左下（和菜单镜像），这是"颜色不一样"最扎眼的一处；改 135 后粉端回到左上。
>
> **三色靠两带还原**：niri 每带只吃两停，于是 `focus-ring` 拿走渐变前半段（首→中）、`border`
> 拿后半段（中→末），两带在中间站接头。像素验证（`niri msg windows` 定位聚焦窗、逐点取色）：
> - 环的外带在 s=0.05 处 (254,177,204) vs 菜单卡片同位置 (254,176,203)，**ΔRGB 合计 2**；
> - 内带跟的是菜单后半段：s=0.55→0.95 差值 36/28/35/20/29（合计，满分 765）；
> - 单带（`--single-band`）对菜单的均值差 ≈47、两带"各管半程"最好时 ≈32 —— 两带更贴菜单的暖段，
>   单带则在整体平均上略稳，所以留了开关给肉眼镜选。
> - 代价：`border` 占内容 2 逻辑像素（见上），未聚焦窗的 border 透明故外观不变。
>
> **没做到的事（诚实记录）**：菜单那条渐变在 t=0.5 有拐点，而 niri 的每一带都是**直线**插值，
> 所以单带或多带都无法逐像素复刻拐点：环的中间色调会比菜单略冷/略暗一点。实测菜单自身曲线也比
> `0/0.5/1` 均匀停靠的模型"跑得快"（s=0.45 处已是 (214,159,136)，模型给 (242,185,156)），故别拿
> 均匀三停模型当验收基准，要比就比**同一张图里的像素**。`niri validate` 通过，二次运行输出
> "already up to date"（幂等），主题退平色时 `border` 自动关掉、`active-gradient` 行删除。

### 5.7 模块化拆分 + 显示/字体/圆角（2026-08-25 调校）

`config.kdl` 已拆成 Omarchy 式模块化：主文件只做编排，大块配置各自 `include`。

**文件结构（`~/.config/niri/`）**

| 文件 | 内容 |
|---|---|
| `config.kdl` | 编排器：`environment` / `spawn` / `animations` / `screenshot-path` + 6 个 `include` |
| `input.kdl` | 输入设备（键盘 / 触摸板 / 鼠标 / trackpoint） |
| `monitor.kdl` | `output "eDP-1"`：分辨率 / modeline / scale |
| `layout.kdl` | gaps / focus-ring / border / shadow / struts；`focus-ring` 与 `border` 里的 `active-color` / `active-gradient`（以及 `border` 的 on/off）是**脚本生成值**（首次运行 `omarchy-niri-apply-theme` 自动插入，§5.6） |
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
- 参考邻居主账户的 `~/Projects/vantage/README.md`（pkexec 可读；2026-09-21 项目统一收进 `~/Projects/`）：vantage `res`
  三档为 **原生 4K/2.25、均衡 2560×1600/1.5、省电 1920×1200/1.25**。本机最终用
  「均衡模式 + scale 2.0」。

**字体（12px ≡ 9pt，2026-09-20 全桌面对齐，见 §8.19）**

- **唯一基准** = bar 上 Display 面板的 `TEXT SIZE`：`~/.config/omarchy/shell.toml` 的 `[font] base-size = 12`（px）。
- **换算锚点**（官方 `omarchy-display-text-size` 自己写明）：**12px ≡ 9pt @96dpi ≡ GTK text-scaling-factor 1.0 ≡ 终端 9pt**。
  所以除 shell 外的每一层都用 **9pt**，而不是 12pt —— Pango 按 96dpi 折算，`12pt = 16px`，比 bar 大 33%，
  这正是"应用字看着比 bar 大"的根因。
- **各层落点**（基准 12px 时都是 9pt）：GTK 侧 `SF Pro 9` —— dconf `font-name`/`monospace-font-name`、
  `gtk-3.0/4.0 settings.ini`、XSETTINGS `Gtk/FontName`（**固定基准，滑块调大时靠 factor 放大、不改这个 pt**）；
  Qt `SF Pro,9` / `SFMono Nerd Font,9`、fcitx5 `SF Pro Text 9`、GTK2 `.gtkrc-2.0`、终端（这几层**写目标 pt**）。
  GTK4 应用（如 Nautilus）只读 gtk-4.0，两处都要设。改 GTK 那个 pt 会把 factor 的量化基准一起带偏（§8.19）。
- **连动**：`~/bin/omarchy-display-text-size` 垫片让 bar 的 TEXT SIZE 滑块一次驱动上面全部层（§8.19）。

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

（这条对**不透明的客户端**同样成立：它们只能靠 niri 侧的 `opacity` 压 alpha，见 §8 第 27 条。）

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
    - 导出覆盖层：**必须限路径**，别裸跑 `git diff`（工作区里有 238 条主题删除等非移植改动）——
      `git diff -- $(grep '^diff --git' ~/.config/omarchy/niri-port/niri.patch | sed 's|.* b/||') <新增的仓库内文件>
      > ~/.config/omarchy/niri-port/niri.patch`；另 `cp shell/Commons/Niri.qml ~/.config/omarchy/niri-port/`。
    - 写 `~/bin/omarchy-niri-repatch`，建
      `~/.config/omarchy/hooks/post-update.d/10-niri-repatch`。
    - 每次 `omarchy update` 之后钩子自动重放；若冲突（上游改了同一函数）则手动合并（找 Ante）。
11. bar 部件与主题取色（**用户级，抗更新**）：
    - 拷 `~/.config/omarchy/plugins/{jianlongliu.arch-logo,jianlongliu.workspaces}/`；装第三方浮栏
      `omarchy plugin add https://github.com/Charlieras262/omarchy-floating-bar.git --yes`，
      再按 `niri-port/plugin-patches/charlieras262.floating-bar.patch` 打 niri 适配（见 §8.11）。
    - 拷 `~/bin/materal-update`、主题 `~/.config/omarchy/themes/tonal-spot/`、钩子
      `hooks/theme-set.d/20-materal`、单元 `~/.config/systemd/user/materal-recolor.{path,service}`
      （`systemctl --user enable --now materal-recolor.path`，见 §8.10）。
12. 共享壁纸库（可选，见 §8.12）：`~/omarchy-wallpaper-aio/setup.sh <壁纸库目录>`，再为**仓库层**主题
    手工补 `ln -s`；库目录要先存在（脚本不建目录、不含图）。

---

## 8. 专题记录（已按模块拆分）

> 原来这里是 1232 行的编号流水账（32 条编号条目 + 14 个 `§8.x` 子节），2026-09-20 按模块拆成独立卷。
> **编号未改**：下表左列就是原号，正文在对应卷里；此处只留这张表。

| 原编号 | 主题 | 现所在 |
|---|---|---|
| `§8 第 1 条` | CLI 依赖已装 | `docs/visual.md` |
| `§8 第 1b 条` | 壁纸/背景已修 | `docs/visual.md` |
| `§8 第 2 条` | hyprctl 垫片本轮修复 | `docs/shims.md` |
| `§8 第 3 条` | 快捷键重映射已按用户方案落地 | `docs/behavior.md` |
| `§8 第 4 条` | 显示器缩放 SCALE 生效 | `docs/visual.md` |
| `§8 第 5 条` | hyprctl schema 精度 | `docs/shims.md` |
| `§8 第 6 条` | 锁屏 | `docs/lock.md` |
| `§8 第 7 条` | TUI 编辑器启动已修 | `docs/shims.md` |
| `§8 第 8 条` | A+C 落地 / 更新覆盖层 | `docs/upstream.md` |
| `§8 第 9 条` | system 开关已修并统一标准化 | `docs/behavior.md` |
| `§8 第 10 条` | overview 背景与桌面不一致 | `docs/visual.md` |
| `§8 第 11 条` | 电池面板 POWER PROFILE 区为空 | `docs/behavior.md` |
| `§8 第 12 条` | Super+K 键位菜单只剩 2 条 | `docs/behavior.md` |
| `§8 第 13 条` | Ghostty 磨砂模糊 | `docs/visual.md` |
| `§8 第 14 条` | 菜单 Apps 列表启动全部失灵 | `docs/behavior.md` |
| `§8 第 15 条` | brightnessctl 授权安装 + 背光权限 | `docs/behavior.md` |
| `§8 第 16 条` | GitHub 发布流程 | `docs/upstream.md` |
| `§8 第 17 条` | 迁移到主账户系统级 vs 用户级 | `docs/migration.md` |
| `§8 第 18 条` | 弹窗未给浮栏让位 | `docs/visual.md` |
| `§8 第 19 条` | 耗电/续航专项 | `docs/behavior.md` |
| `§8 第 20 条` | 换主题时 omarchy-theme-set-browser-pol… | `docs/behavior.md` |
| `§8 第 21 条` | Install > Package / AUR 点了没反应、也不报错 | `docs/behavior.md` |
| `§8 第 22 条` | 应用启动类调用统一到一个 uwsm-app 垫片 | `docs/shims.md` |
| `§8 第 23 条` | screensaver 关掉并屏蔽 | `docs/behavior.md` |
| `§8 第 24 条` | 按键表去重 + 应用启动键统一走 Omarchy 包装器 | `docs/behavior.md` |
| `§8 第 25 条` | 桌面双击弹窗慢 | `docs/behavior.md` |
| `§8 第 26 条` | 按键里不能写开窗属性 | `docs/behavior.md` |
| `§8 第 27 条` | 不透明 app 的磨砂 | `docs/visual.md` |
| `§8 第 28 条` | bar 的内联部件设置 | `docs/visual.md` |
| `§8 第 29 条` | 窗口缝隙 16 → 8 | `docs/visual.md` |
| `§8 第 30 条` | 菜单卡片"过于黑" | `docs/visual.md` |
| `§8 第 31 条` | [bar] 段只认 3 个键 → 让 shell.toml 能覆盖全… | `docs/visual.md` |
| `§8 第 32 条` | 吐司"一来通知整屏变糊" | `docs/visual.md` |
| `§8 第 33 条` | 交接过渡的桌面侧（壁纸铺底 + bar 从顶边滑下来） | `docs/visual.md`（登录侧全案见 `docs/lock.md` §11.26） |
| `§8.6` | A 层 | `docs/behavior.md` |
| `§8.7` | 更新覆盖层 | `docs/upstream.md` |
| `§8.8` | 视觉磨砂 | `docs/visual.md` |
| `§8.9` | 上游合并基线 | `docs/upstream.md` |
| `§8.10` | 主题动态取色 | `docs/visual.md` |
| `§8.11` | bar 插件层 | `docs/plugins.md` |
| `§8.12` | 共享壁纸库 | `docs/visual.md` |
| `§8.13` | 上游小更新 | `docs/upstream.md` |
| `§8.14` | 菜单空白 | `docs/behavior.md` |
| `§8.15` | overview 模糊壁纸延迟 | `docs/visual.md` |
| `§8.16` | overview 背板与窗口动画错位 | `docs/visual.md` |
| `§8.17` | 输入源徽章 | `docs/behavior.md` |
| `§8.18` | 锁屏"不能锁" | `docs/lock.md` |
| `§8.19` | 全桌面字号 / DPI 一致性 | `docs/visual.md` |

### 未决项速查（还没做的）

| 未决 | 原编号 | 正文 / 现状 |
|---|---|---|
| 弹窗（toast）没给浮栏让位 | `§8 第 18 条` | `docs/visual.md` |
| 耗电 / 续航专项（测过一轮，从 BIOS C-States 接着查） | `§8 第 19 条` | `docs/behavior.md` |
| `omarchy-theme-set-browser-policy` 那步为何失败（查上游是否该放行） | `§8 第 20 条` | `docs/behavior.md` |
| `Mod+O` 与 `Mod+Tab` 都绑 `toggle-overview`，用户未表态，暂留两个 | `§8 第 24 条` | `docs/behavior.md` |
| 面板拖拽 / 键盘导航的端到端复现（`wtype` 送不进面板） | `§8.11` | `docs/plugins.md` |
| `hyprctl` schema 精度：个别 Hyprland-only 字段仍给占位值 | `§8 第 5 条` | `docs/shims.md` |

其余条目都是**已落地**的记录（怎么坏的、怎么修的、怎么回退），迁到各卷后仍按原编号可查。

## 9. 验证清单

- [x] `niri validate` 通过。
- [x] QuickShell 启动无报错（"Configuration Loaded"）。
- [x] grim 截图：bar 渲染出 workspaces 1-5、"3"高亮、时钟、EN/安 键盘布局、日历弹窗。
- [x] `omarchy-menu toggle` 开/关根菜单（截图确认，rc=0）。
- [x] hyprctl 垫片查询与 dispatch 均工作。
- [x] `jq` / `satty` / `inotify-tools` 安装（pkexec）。
- [x] `omarchy-capture-region` / `omarchy-capture-screenshot` 无 jq 报错（monitors 补 activeWorkspace 后）。
- [x] 主账户未被触碰（mtime 未变）。
- [x] 键位重映射：方向键方案 + `Mod+K`/`Mod+Ctrl+L` 让给 Omarchy（`load-config-file` 重载后）。
- [x] 背景壁纸显示：`qt6-imageformats` + QML/theme-set 修复后，`grim` 见波纹像素。
- [x] A 层：菜单项全部指向 `config.kdl`（不再出空文件），`omarchy-refresh-hyprland` niri no-op。
- [x] C 层：`omarchy-niri-apply-theme` 写入 `#89b4fa`/`#595959aa`，`niri validate` 通过、热重载 OK。**2026-08-30 查出：§5.7 模块化后 `focus-ring` 移入 `layout.kdl`、脚本仍写 `config.kdl` → 静默失效；2026-09-19 已改为"沿 `include` 定位 + 渐变取首色站"并重验，当晚再升级为"菜单同款 token + 三色拆两带 + 角度 +90"（见 §5.6）。**
- [x] 更新覆盖层：`omarchy-niri-repatch` 幂等（已应用判 no-op；stash 还原后能干净重放）。
- [x] `theme-set`/`post-update` 钩子触发正常、非 niri 静默跳过。
- [ ] 截图/剪贴板 CLI 全链路实测（slurp/grim 交互，需桌面环境）。
- [x] **锁屏 PAM 门禁（2026-09-19）**：定位到"锁不了"的真因是手工部署漏了安装器步骤 →
  `/etc/pam.d/omarchy-lock-password` 不存在，`lock()` 直接返回 `missing-pam`（stock 与第三方插件同款门禁）；
  `pkexec omarchy-apply-lock` 补上后 `lock status` 的 `passwordPam` = `true`；顺带删掉被上游 `grep -qi finger`
  误判生成的 `omarchy-lock-fingerprint`，并排除 dms-greeter（它只写 `/etc/pam.d/greetd`）（见 §8.18）。
- [x] Omarchy 锁屏（`Mod+Ctrl+L`）在 niri 上**真人**实测（2026-09-19）：按下即锁、输密码即解锁；且此时锁屏已经换成自研 `jianlongliu.split-lock`（§11.18–§11.20），日志 `lock-requested → screen-stabilizing → secure=true → unlocked`。
- [ ] **锁屏与登录界面的账户切换统一用头像**（2026-09-19 用户提出）：
  - 登录界面 `split-greeter`：账户选择器以**头像为主体**（一行头像、选中高亮），用户名降为次要信息；头像沿用 `/var/lib/AccountsService/icons/<user>`，缺省首字母圆牌。
  - 锁屏 `split-lock`：现在是单账户（只解当前会话）。要支持"切到别的账户"，除了头像选择器，还得把会话交回 greetd —— 锁的 PAM 服务 `/etc/pam.d/omarchy-lock-password` 只认当前登录用户，跨账户必然要重走一次登录会话。
  - 两处共用一个头像组件；配色/壁纸跟着选中账户走的那套逻辑（greeter 已实现）复用。
- [ ] 真实跑一次 `omarchy update`，确认上游变更时覆盖层自动重放或明确报冲突。**2026-09-19 部分验证**：手动走了等价的 `git merge --ff-only` 路径（§8.13，上游只改到我们 patch 内文件的"其他区域"），重放幂等成立；官方脚本本身仍没跑过（它要 sudo + snapper 快照 + 包升级）。
- [x] **全桌面字号 / DPI 一致性（2026-09-20）**：`~/bin/omarchy-display-text-size` 垫片逐档往返 `12/14/16/20/9/12` 实测 —— shell `base-size` 与终端 pt 同步、Qt/fcitx5 走目标 pt、GTK 侧恒 9pt 由 `text-scaling-factor` 承接（14px 档第一版曾把 GTK 算成 17px，已修）。bar 进程 PATH 解析裸命令命中 `~/bin` 垫片；`fc-match monospace` = SFMono Nerd Font、`xrdb -query` = 96。XWayland 只剩 xrdb 96 一处 DPI 来源（见 §8.19）。真人拖动待用户核对 shim 日志。
- [x] **logout/reboot/shutdown** 统一标准化：`~/bin/omarchy-niri-system` 单一入口（logout→niri quit、reboot/shutdown→logind D-Bus `Manager.Reboot/PowerOff`；`loginctl` 无该 verb 是本 bug，已改；`pkcheck` 免密 exit 0 验证）。
- [x] **电源 profile**：`~/bin/omarchy-powerprofiles-list` 返回 3 个 profile、active 标记正确；set 经 TLP D-Bus 生效（异步应用，恢复为 power-saver）。
- [x] **Ghostty 磨砂模糊**：`window-rules.kdl` 给 `com.mitchellh.ghostty` 加 `background-effect {xray true; blur true}` + `draw-border-with-background false`；ghostty `background-opacity = 0.85`、`background-blur-radius = 0`；焦点环穿透"诡异"问题已解（§5.8）。
- [x] **账户迁移到主账户（§11）**：快照 → 卸 DMS（保留 greeter）→ 原版 niri 默认配置当基座 → 整目录搬运 → 改写 `config.kdl` 三处硬编码路径 → 自检。**2026-09-19 已执行**（真人锁屏/解锁那一项见 §11.20；现状核对 2026-09-21：`dms-shell` / `dms-shell-niri` / `dankcalendar` 已不在包列表，`/etc/greetd/config.toml` 指向自研 `split-greeter`）。
- [ ] 运行实测：注销、关机、重启（会结束会话/重启，交给用户）。
- [x] **overview 背景统一**：`shell/plugins/blurwallpaper/`，图层**常驻映射**、由 niri 只在 overview 内合成（见 §3.1、§6、§8.16）。
- [x] **菜单 override label+icon 修复（2026-08-27）**：`extensions/omarchy-menu.jsonc` 的 3 个 setup 项补全 label+icon，合并后显示 "Monitors"/"Keybindings"/"Input" 且图标正常（不再显示 raw id `setup.monitors` 之类）；根因是 `normalizeItem` 的 `label: value.label || id` 把 action-only override 的 label 退化成 id 并覆盖默认项。
- [x] **screensaver 禁用 + 屏蔽（2026-09-20，用户要求）**：官方 flag `~/.local/state/omarchy/toggles/screensaver-off`（`omarchy-launch-screensaver` 实测 exit 1、无窗口）+ 用户 override 6 条 `when:"false"` 盖住仅有的 `force` 入口；`idle.screensaver`（150s）超时值**未动**。同时修掉该文件 5 处超长 `\u` 转义（§8 第 23 条）。
- [x] **按键去重 + 应用启动键（2026-09-19/20）**：`niri validate` 通过、生效行无重复键；`Mod+Return` / `Mod+Y` / `Ctrl+Shift+Esc`（终端类）、`Mod+E`（nautilus）、`Mod+Z`（浏览器）实测均开出窗口；过程中顶出并修掉垫片 v1.0 的 `setsid` 坑（§8 第 22、24 条）。
- [ ] **等你肉眼确认**：开一次菜单看 System 里 Screensaver 是否已消失（`when:"false"` 的效果只能看渲染；文件本身已按 `stripJsonc` + `JSON.parse` 校验通过）。
- [x] **视觉磨砂（frosted Quickshell）**：`Menu.qml` + `KeyboardPanel.qml` 挂 `BackgroundEffect.blurRegion`（只磨砂卡片，不全屏）；`effects.kdl` 给 `omarchy-keyboard-panel` 设 `xray false`（实时窗口毛玻璃）；`[popups]` alpha 0.8→0.65。面板开/关屏幕底部清晰度 on/off≈0.995 → 无全屏霜化。
- [x] **浮栏磨砂（2026-09-19）**：`Bar.qml` 保住 `[bar] background-alpha`（不再强制 alpha=1）+ 挂**圆角** `blurRegion`，`effects.kdl` 给 `^omarchy-bar$` 设 `xray false`；实测栏内 `(25,17,20)→(97,95,109)`、四角像素与不磨砂时逐像素相同（无亮晕）、blur 开/关平均差 3.68 且连拍可复现（见 §8.8/§8.11）。
- [x] **媒体键 OSD（2026-08-25）**：`XF86Audio*`/`XF86MicMute`→`omarchy-audio-output-volume`/`omarchy-audio-input-mute`、`XF86MonBrightness*`→`omarchy-brightness-display`，均带 `hotkey-overlay-title`；`omarchy-osd` 已在 niri 渲染确认。
- [x] **brightnessctl 背光**（2026-08-25）：`brightnessctl --class=backlight set +10%` 实测 76→126→恢复；udev 规则 + usergroup 已生效、免重登。
- [x] **上游合并（2026-09-18）**：FF 到 `d174d4a`；2 个冲突已解；覆盖层重建为 17 文件 / 30 hunk，`--reverse --check` 通过、repatch 幂等；shell 在新代码上重启无报错、bar/背景图层正常（见 §8.9）。
- [x] **迁移归零**：121 条全部标记，实跑 33 条（30 通过）；`omarchy-migrate --pending` 为空（见 §8.9.3）。
- [x] **`cf`（Cloudflare CLI）**：`cf --version` → `v0.10.0`（依赖 `mise`）。
- [x] **主题动态取色（2026-09-19）**：`omarchy theme bg next` → path 单元触发 → `materal-update` 重取色并重套主题（staged `colors.toml` 与推导一致、生成了 `shell.toml`、无残留 guard）；重复运行判 "already matches"（幂等）；`omarchy theme set catppuccin` → `omarchy theme set Tonal-Spot` 钩子同样生效（见 §8.10）。
- [x] **C 层回归修复（2026-09-19）**：脚本沿 `include` 找到 `layout.kdl` 的 `focus-ring` 并写入主题色（当时渐变取首色站），`niri validate` 通过（见 §5.6）。**晚些时候连升两级**：色源换成菜单同款 `active-border-foreground`；再把三色渐变拆成 `focus-ring`+`border` 两带并修掉角度约定（+90）——菜单卡片与窗口环逐点比对，外带 ΔRGB 合计 2，内带跟后半段（§5.6）。
- [x] **窗口边框 = 菜单那圈（2026-09-19 晚）**：环的两带均由主题 token 生成（`--single-band` 保留单带对比版）；代价是 `border` 占内容 2 逻辑像素（`window_size` 612×724 vs `tile_size` 616×728），未聚焦窗透明不受影响（见 §5.6）。
- [x] **浮栏几何（2026-09-19）**：像素实测 bar 占物理 y 16..79、左缘 x = 16；平铺窗口停在 728 = 800 − (32 bar + 8 floatGap + 16 niri gaps)——**这是当时的 gaps**，2026-09-20 改成 8 后为 744（见下条），niri 独占区与自身 gaps 不打架（见 §8.11）。
- [x] **bar 部件（2026-09-19）**：胶囊工作区（聚焦点拉伸 2.6×、四级 alpha）与 Arch logo 渲染正常，点击经 `hyprctl` 垫片走通（见 §8.11）。
- [x] **bar 电量百分比 + 去掉中间更新部件（2026-09-20）**：`omarchy.power` 加 `showPercentage: true`、`layout.center` 摘掉 `omarchy.system-update`；bar 条内笔画像素最右端 684 → 939（多出数字）、中间带 1371 → 1213（部件消失 + 居中组位移）；shell.json 热监听、免重启（见 §8 第 28 条）。**同日再改 `panels/power/Panel.qml`** 把 `text` 换成 `图标 + 数字%` 让数字落在最右（上游默认是数字在左）：字形高度指纹确认 h23 的图标块 x 2493..2515 → 2431..2454；`niri.patch` 因此 18 文件/34 hunk → **19 文件/35 hunk**（`--reverse --check` 通过、repatch 幂等）。
- [x] **窗口缝隙 16 → 8（2026-09-20）**：`~/.config/niri/layout.kdl` 的 `gaps`；实测窗口上缘物理 112 → 96、右缘 +16、整屏 22.6% 像素重排，`tile_size` 616×728 → 628×744、`window_size` 612×724 → 624×740（本机 `tile_pos_in_workspace_view` 仍为 null，验收看像素边缘，见 §8 第 29 条）。
- [x] **菜单卡片不再近黑（2026-09-20，2026-09-21 改法换代）**：9-20 先在 `~/.config/omarchy/shell.toml` 覆盖 `[menu] background = "#2a2a22"`（当时绿调主题的 `lighter_background`）→ 卡片中位色 (45,38,38) → (60,53,54)，该文件热生效；代价是**写了字面值后不再随主题变**。9-21 用户又报"omarchy menu 咋又变黑了"，复查确认覆盖链没坏（临时改成 `#ff00ff`，整块卡片变洋红），是 `#2a2a22` 本身仍暗（亮度 42）+ 主题已在 03:33 换成冷调 `tonal-spot`，于是**删掉底色键、只留 `background-alpha 0.45`**（与 `[bar]` 同档），底色重新走主题的 `[menu] background`（matugen 出的 `colors.toml` `background`）→ 卡片中位色 (59,53,62) → (64,62,68)。⚠ `[menu]` 是共享 token，剪贴板 / emoji / 提醒 / OSD 会一并变透（OSD 有 `^omarchy-osd$` 磨砂规则撑着，实测可读）；`menu.scrim-alpha` 仍是"整屏变暗"的旋钮（见 §8 第 30 条）。
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
- [x] **桌面双击选择器弹窗速度（2026-09-20）**：切片 `Image` 改异步解码后，壁纸选择器首帧 550ms → 250ms，
  且不再卡住 bar（原先是同线程同步解码 33 张缩略图）；主题选择器 ~250ms 已在下限；`niri.patch` 20 文件 /
  36 hunk、`--reverse --check` 通过、`omarchy-niri-repatch` 幂等（见 §8 第 25、28、31 条）。
  **同日二次定位**（用户「不是切换，是打开那个 picker」）：脚本段全程 21ms、面板进合成器 121ms 冷/18ms 热、
  可见首帧 scrim ≈220~280ms / 整卡 ≈240~400ms → 余下的"等会"只在**冷态**（页缓存 + 首帧管线/纹理分配），
  已加登录后 45s 延迟预热单元 `omarchy-picker-warmup`（`Nice=19`/IO idle/可 toggle；45.16s 后执行、
  三段 113/98/10ms、`Result=success`）。**热态无感是预期**——预热不画那一帧（见 §8 第 25 条）。
- [x] **浮动 app 窗口（2026-09-20）**：nautilus 与 yazi 改由 `window-rules.kdl` 的 `open-floating` 浮动（bind 里写
  `open-floating` 是无效语法，会让**整份配置**被静默丢弃、继续跑旧配置）；yazi 与 btop 经共用的 `--app-id=org.omarchy.float-tui` 与普通终端分开；三者（含 nautilus）实测 `is_floating=true`，
  窗口 764×528（见 §8 第 26 条）。
- [x] **微信磨砂（2026-09-20）**：XWayland 客户端自己画不透明底，光有 `blur` 规则看不见 —— 加 `opacity 0.85` 让 niri 压
  alpha 后才出效果；实测不透明→半透明窗口区域 `mean 225.3→213.5`、79.9% 像素变化 >8，blur on/off `平均|Δ|=4.82`
  （见 §8 第 27 条）。
- [x] **全 bar 字号统一到 12（2026-09-20）**：ai-subs 胶囊的 bar 文字 `caption`(10) → `body`(12)（5 处，用户先要 13 再
  改 12）；`Style.qml` 的 `[bar]` 分支补全整型 token 白名单后，`shell.toml` 的 `[bar] icon-font = 12` 生效 ——
  内置部件数字/图标 19–20/21–24 → 17–19/19–22，与时钟、ai-subs 同档；`niri.patch` 19 文件/35 hunk →
  **20 文件 / 36 hunk**（`--reverse --check` 通过、repatch 幂等）；顺带修回被切走的 ai-subs `barDisplay`，
  并记下 `qs -p … ipc call … refresh` 这条立刻取数的路子（见 §8 第 31 条 + `docs/plugins.md` §5.1）。

---

## 10. 关键环境信息

- 两个账户**同属用户本人**。**移植现在就跑在主账户（uid 1000）上** —— 2026-09-19/20 按 §11 从实验账户迁回，本文档里 `$DEV_HOME`、`/home/<dev-user>` 这类写法是迁移前的历史记号，迁移后一律等于 `~`。实验账户（uid 1001 `yvonne`）还在，但已不参与本移植（其户目录仍是 0700，读不到）。迁移后 `dms-shell` / `dms-shell-niri` / `dankcalendar` **已不在包列表**，`/etc/greetd/config.toml` 的 `default_session` 指向自研 `/usr/local/bin/split-greeter`（`greetd-dms-greeter-bin` 包仍在，只是不再当登录会话）。
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

> **已拆入迁移卷**：正文（§11.0–§11.9 方案与小结、§11.15 执行清单，以及 §11.10–§11.14、
> §11.16–§11.25 的指针）在 `docs/migration.md`。
> 其中锁屏/登录相关的 §11.10–§11.14、§11.16–§11.25 正文在 `docs/lock.md`。
