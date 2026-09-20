# Omarchy on niri

> **English → [README.md](README.md)**

把 [basecamp/omarchy](https://github.com/basecamp/omarchy)（`quattro` / `4.0.0.alpha`）从 Hyprland 移植到
[niri](https://github.com/YaLTeR/niri) Wayland 合成器上。

本仓库包含移植后的 Omarchy 源码，以及让它能在 niri 上跑起来的"胶水"。它**不是独立的安装器**——假设你已经有一个
Arch + niri 登录会话、并且**已经装好 Omarchy**（或者你会先装 Omarchy）。它给你的是：

- 打了 QML/Niri 移植的 Omarchy 源码（`shell/Commons/Niri.qml`、打了 patch 的
  `Bar.qml` / `Workspaces.qml` / `Background.qml`）。
- `port-bin/` — 放进 `PATH` 最前面的覆盖脚本，把跟 Hyprland 耦合的部分翻译到 niri
  （其中 `hyprctl` 垫片是最关键的一个；另有 `uwsm-app`、`omarchy-update`、
  `omarchy-picker-warmup`、`omarchy-display-text-size`）。
- `default/systemd/user/` — 随移植分发的用户单元（选择器预热）。
- `niri-port/` — 幂等的覆盖层 patch（`niri.patch` + `Niri.qml`），能在 `omarchy update` 之后存续。
- `niri-config/` — niri 侧的接线（要合并进 `config.kdl` 的 `omarchy.kdl.template`，外加一份 `shell.json` 示例）。
- `hooks/` — Omarchy update/theme 钩子，负责重放移植覆盖层。
- `install.sh` — 可选的一套便捷包装脚本。**不是推荐的路径**：手动步骤在 `docs/INSTALL.zh.md`，应按它逐条来做。
- `docs/INSTALL.zh.md` — 手动执行安装流程（依赖、文件放位、配置合并、覆盖层、背光）。
- `docs/omarchy-on-niri-port.md` — **主文档**（当前事实：硬性约束、架构、文件清单、niri 配置、
  部署、验证清单、环境信息）+ 模块映射表（**中文**）。
- `docs/visual.md` — 视觉调整卷：磨砂全栈、字号与 DPI、边框环、菜单底色、gaps、overview、
  主题取色、壁纸库、显示器缩放。
- `docs/behavior.md` — 功能调整卷：按键与去重、system 动作、电源与背光、screensaver、输入源、
  菜单行为、选择器性能与预热、耗电专项。
- `docs/plugins.md` — 插件卷：bar 插件层总览、逐插件魔改与运维。
- `docs/shims.md` — 垫片卷：`hyprctl`、`uwsm-app`、`omarchy-update`、`display-text-size`、
  `picker-warmup` 等 PATH-first 覆盖脚本。
- `docs/upstream.md` — 上游跟进卷：覆盖层重放、合并基线、上游小更新、发布流程。
- `docs/migration.md` — 账户迁移卷：实验账户 → 主账户的方案与执行清单（2026-09-19）。
- `docs/local-overrides.md` — 本机改动总账：相对仓库多出/改过的一切与回退方式。
- `docs/lock.md` — 锁屏与登录专卷：Split Greeter、`split-lock`、PAM 门禁、howdy 与头像，
  以及 greetd 只有一格 `configuring` 的陷阱。

各卷**沿用原章节编号**（`§8 第 N 条`、`§8.x`、`§11.x`），主文档里有「原编号 → 卷」的映射表；
文档只有一份正本，就在 `docs/` 里；`~/Documents/omarchy-niri-*.md` 是指向它的软链，
`scripts/check-doc-links.sh` 守这一点。

## 仓库结构

```
omarchy-on-niri/
├── shell/        <- 移植后的 Omarchy Quickshell 源码（层1）
├── bin/          <- Omarchy 自己的脚本（上游原样，未改）
├── port-bin/     <- 移植胶水：hyprctl 垫片 + uwsm-app 垫片 + omarchy-update/picker-warmup/display-text-size 垫片
│                     + niri 的 system/power/theme/repatch 脚本
│                     install.sh 会把这些拷进 ~/bin（PATH 最前、挺过 `omarchy update`）
├── niri-port/    <- 覆盖层：niri.patch + Niri.qml（每次更新后重放）
│                     + plugin-patches/（第三方 bar 插件的本地魔改补丁，只能手工重放）
├── niri-config/  <- omarchy.kdl.template（合并进 ~/.config/niri/config.kdl）
│                     + shell.json 示例（Omarchy 配置层1）
├── hooks/        <- post-update.d/10-niri-repatch, theme-set.d/10-niri-border
├── install.sh    <- 可选便捷包装脚本（推荐按 docs/INSTALL.zh.md 手动来）
├── docs/INSTALL.zh.md   <- 手动执行安装流程
├── docs/omarchy-on-niri-port.md <- 主文档（当前事实 + 模块映射表，中文）
├── docs/{visual,behavior,plugins,shims,upstream,migration,lock,local-overrides}.md <- 各模块卷（中文）
├── scripts/             <- check-doc-links.sh（`~/Documents` 那九个软链必须仍指向 `docs/`）
└── README.md / README.zh.md
```

## 依赖 / 前置条件

在目标 Arch 机器上装下面这些。以下全部已在移植机上实测使用（2026-03 / Arch rolling、systemd 261、niri 26.04）；
请在你自己机器上确认包的可得性。

### 必需 —— 外壳引擎
| 包 | 原因 |
|---|---|
| `niri` | 合成器本身。本移植目标是 niri（26.x）。 |
| `quickshell` | 渲染 Omarchy bar/菜单/OSD 的 layer-shell QML 引擎。Omarchy 的 shell 基于 Quickshell。用仓库包或 AUR 装。 |
| `git`, `base-devel` | 克隆/编译/安装 Omarchy（以及本移植）。 |

### 必需 —— Omarchy 运行时依赖
| 包 | 原因 |
|---|---|
| `jq` | 大量 `omarchy-*` 脚本和 `hyprctl` 垫片解析 JSON 用。 |
| `qt6-imageformats` | **关键。**让 Qt Quick 能解码 Omarchy 的 `.webp` 壁纸。没有它会得到一片黑壁纸。 |
| `inotify-tools` | 提供 `inotifywait`，由 Omarchy 插件监视器使用（`~/.config/omarchy/plugins`）。 |
| `wl-clipboard` | 提供 `wl-copy` / `wl-paste`，剪贴板管理器插件用。 |
| `brightnessctl` | 亮度媒体键 / OSD 的背光控制。 |

### 必需 —— 音频/媒体
| 包 | 原因 |
|---|---|
| `pipewire` + `wireplumber`（以及 `pipewire-pulse`） | 音频后端；`wpctl` 驱动音量 OSD。 |
| `playerctl` | 媒体传输键（播放/暂停/上一曲/下一曲）。 |
| `ghostty` | 默认终端（`Mod+Return` / `Mod+T`）。 |

### 电源后端（二选一）
| 包 | 原因 |
|---|---|
| `power-profiles-daemon` | 提供 `powerprofilesctl`。`port-bin/omarchy-powerprofiles-*` 优先用这个。 |
| **或** `tlp` + `tlp-pd` | 移植机用 TLP（无 `powerprofilesctl`）。垫片回退到 TLP 的 `net.hadess.PowerProfiles` D-Bus 接口。 |

### 可选
| 包 | 原因 |
|---|---|
| `satty` | 截图标注。 |
| `swappy` | 另一个截图编辑器。 |
| `grim` / `slurp` | niri 截图 / 区域捕获（niri 自带，但某些捕获助手会调这些）。 |

### 非包前置条件
- `/sys/class/backlight/` 下要有一个**背光设备**（如 `intel_backlight`）。`brightnessctl` 需要 `video` 组 /
  一条匹配的 udev 规则才能在无 root 时写入：
  - `/etc/udev/rules.d/90-backlight.rules`：`SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`
  - `usermod -aG video <user>`
- 一个 **logind 会话**，polkit 的 `org.freedesktop.login1.reboot` / `power-off` 设为 `allow_active=yes`
  （Arch 上 systemd 默认如此），这样电源开关才能免密切换。

## 安装

手动、逐条执行的步骤在 **`docs/INSTALL.zh.md`**（依赖、`~/bin` 胶水、config.kdl 合并、覆盖层、背光、每机检查）。
这是受支持的路径。

另外有个可选的 `install.sh` 引导脚本，会放下同样的文件，但它**不会**改写已存在的 `config.kdl`，也不会自动装包或
修背光权限——要稳妥请按 `docs/INSTALL.zh.md` 走。

简版：

```sh
git clone https://github.com/jianlongliu/omarchy-on-niri
cd omarchy-on-niri
# 先装 README "Requirements" 里的包，然后执行：
./install.sh            # 可选；或按 docs/INSTALL.zh.md 逐步来
```

然后注销再登录——`spawn-sh-at-startup` 会拉起 QuickShell 外壳。

## 每机调整（必须检查）

这些是硬件/OS 相关的，**无法可靠地自动检测**：

1. **显示器输出名** — 移植在几处用到 `eDP-1`；跑 `niri msg outputs` 后相应调整。
2. **背光设备** — 移植机上为 `intel_backlight`；查 `/sys/class/backlight/*` 确认你的。
3. **电源后端** — TLP 还是 power-profiles-daemon，会改变 `omarchy-powerprofiles-*` 报告的内容。
4. **niri 版本** — 在 26.04 上测试过；不同版本的键位/总览行为可能有差异。
5. **锁屏认证** — `/etc/pam.d/omarchy-lock-password` 来自 Omarchy 安装器，而本手动路径跳过了安装器。
   缺它时锁屏**完全锁不上**（`omarchy-shell lock status` → `"passwordPam":false`）；跑一次
   `pkexec ~/.local/share/omarchy/bin/omarchy-apply-lock`（INSTALL 第 8 步）。

总览的垫底无需调整：那一层由 niri 自己绘制，移植自带的 `blurwallpaper` 插件会在总览打开时铺一张强模糊壁纸（见移植笔记）。

## 为什么它不是"一键保证"

本移植复用 Omarchy 自己的安装，只是通过 `hyprctl` 垫片和 `Niri.qml` Quickshell 模型把 Hyprland 换成 niri。
由于 Omarchy 脚本约 50 次调用 `hyprctl`，垫片必须在 `PATH` 上外壳才能工作。`~/.local/share/omarchy` 里的文件是在
工作树里打 patch 并**保持未提交**，这样 `niri.patch` 覆盖层才能在每次 `omarchy update` 后重放——**不要**在
`~/.local/share/omarchy` 里面提交，否则快进更新会断。

完整的决策日志见 `docs/omarchy-on-niri-port.md`（中文）。
