# 本机改动总账（Omarchy on niri）

> 文档只有一份：本文件（`docs/local-overrides.md`）。
> 目的：一眼看出**这台机器上相对上游 omarchy 到底动了什么、落在哪一层、怎么回退**，以及
> **哪些东西只在机器上、仓库里没有**（= 换机不可复现的缺口）。
> 最后核对：2026-09-20 深夜（仓库 `quattro`，覆盖层 21 文件 / 38 hunk）。

---

## 0. 先记住三条分层规则

1. **`~/bin` 在 `$OMARCHY_PATH/bin` 之前**（quickshell 的 PATH 顺序）→ 同名垫片永远赢。
   `omarchy-update`、`uwsm-app`、`hyprctl` 全靠这条生效。
   例外：CLI 的 `omarchy update` 走绝对路径 `$OMARCHY_BIN_DIR/omarchy-update`，垫片拦不住（菜单/bar 拦得住）。
2. **热生效面**：`~/.config/omarchy/shell.json`、`shell.toml` 是热监听（存盘即生效）。
   **仓库内 QML / 插件 QML 改完必须 `omarchy-restart-shell`**，没有热重载。
3. **`niri-port/niri.patch` 是对 omarchy 仓库的覆盖层补丁**，不是 compositor 补丁。
   本机 niri 26.04 是官方包，`blur` / `blurRegion` / `background-effect` 原生支持，无需打补丁。
   重生成 patch **必须限路径**（见 §7）。

---

## 0.1 备份存放约定（2026-09-21 起）

**所有"改前留一份"的备份集中在一个独立目录：`~/.local/state/backups/`，目录结构镜像 `$HOME`。**

```
原文件                                备份
~/.config/niri/layout.kdl             →  ~/.local/state/backups/.config/niri/layout.kdl.bak-<后缀>
~/.config/omarchy/shell.json          →  ~/.local/state/backups/.config/omarchy/shell.json.bak-<后缀>
~/bin/hyprctl                         →  ~/.local/state/backups/bin/hyprctl.bak-<后缀>
~/.local/share/omarchy/shell/shell.qml → ~/.local/state/backups/.local/share/omarchy/shell/shell.qml.bak-<后缀>
```

- **备份文件名 = 原文件名 + `.bak-<后缀>`**（不再加前导点 —— 它已经不在 `ls` 视野里了）。
- **回退一律一条命令**：`cp <备份> <原位置>`，例如
  `cp ~/.local/state/backups/.config/niri/layout.kdl.bak-20260921-bgcolor ~/.config/niri/layout.kdl`。
- **找备份不用翻目录**：`find ~/.local/state/backups -name 'layout.kdl.bak-*'` —— 文档里凡写
  `xxx.bak-<后缀>` / `.bak-<后缀>`（省了主文件名的简写）的，都按这条到备份根里找。
- 为什么不是"就地隐藏"（2026-09-21 上半场的做法）：藏起来仍然散在 20 多个目录里，`find ~/.config -name '*bak*'`
  照样一地；用户当面定的最终方案是"**独立目录 + 镜像树**"（原话："备份到独立目录去"）。
- **造备份的代码也得照这条写**：`port-bin/omarchy-niri-apply-theme` 原先写可见的
  `layout.kdl.bak-niri-theme`，而它**每次换主题都会跑** —— 现在走 `backup_path()` 写进备份根
  （有沙盒测试：临时 `$HOME` 副本 + 制造颜色差异 → 断言备份只落在
  `<假 HOME>/.local/state/backups/.config/niri/layout.kdl.bak-niri-theme`、内容为改动前原文、config 目录零残留）。
- **迁移记录**：77 个（`~/.config` + `~/bin`）+ 4 个（上游 checkout `~/.local/share/omarchy`）+ 1 个 dconf dump
  = 82 个文件搬进备份根，**只搬不改内容**（搬前/搬后 `md5sum` 多重集逐个相同）。旧的整包备份目录
  `~/.config/omarchy/backups/`（插件改名时的整个插件目录快照）也一并搬进 `~/.local/state/backups/.config/omarchy/backups/`；
  备份根现共 97 文件 / 1.1 M。
- **`~/.local/state/` 不会被清缓存**（`~/.cache` 才会），适合放要留着的回退副本。
- **上游自己的备份逻辑不归本移植管**：`omarchy-refresh-config` 写 `<file>.bak.<epoch>`（可见、就地），
  `omarchy-plugin-remove` 写 `.<id>.bak.<ts>`。装第三方配置里那批（opencode / DankMaterialShell / gtk / qt6ct /
  fastfetch / xsettingsd / environment.d / fcitx5）都按本条收进备份根了。
- 本条只管**备份**。清 `ls` 时顺手挖出的两个"旧版本脚本"与一个"旧时代配置存档"（不是备份）
  加点隐藏、**没有删**，清单与来历见 §8 第 13 条。

---

## 1. 仓库内（随 git 走：`~/Projects/omarchy-on-niri`）

| 路径 | 内容 | 生效方式 |
|---|---|---|
| `shell/` | 移植后的 Omarchy Quickshell 源码（层 1） | `install.sh` 把覆盖层 `git apply` 进 `$OMARCHY_PATH`（幂等），或手工 `~/bin/omarchy-niri-repatch` |
| `port-bin/*`（12 个） | `hyprctl`、`uwsm-app`、`materal-update`、`omarchy-update`、`omarchy-niri-system`、`omarchy-niri-apply-theme`、`omarchy-niri-repatch`、`omarchy-picker-warmup`、`omarchy-display-text-size`、`omarchy-powerprofiles-{list,set}`、`omarchy-sleep-lock-start` | `install.sh` 拷进 `~/bin`（PATH-first） |
| `niri-port/niri.patch` + `Niri.qml` + `plugins/blurwallpaper` | 覆盖层，挺过 `omarchy update` | `~/bin/omarchy-niri-repatch`（幂等） |
| `niri-port/plugin-patches/` | 4 个第三方插件的本地魔改补丁（+ README 说明怎么生成/怎么重放） | 手工 `git apply`（无自动重放器） |
| `scripts/kdl-sync.sh`、`scripts/local-files-sync.sh` | 机器 ↔ 仓库的对账：前者比 `niri-config/local/*.kdl`（家目录占位符），后者比 `local-config/` + `plugins/` + `split-lock/ir-light`（逐字节） | 各自直接跑；不在本机则 `skip` |
| `local-config/` | **本机 `~/.config` 覆盖层**（上游默认树 `config/` 之外那几份）：`ghostty/config`（含 `background-blur-radius = 0` 这条磨砂必需改动；配色走 Omarchy 主题的 `config-file`，不带私有主题文件）、`systemd/user/materal-recolor.{path,service}` | 拷到 `~/.config/` 对应路径（见该目录 README）；`materal-recolor.path` 还要 `systemctl --user enable --now` |
| `plugins/jianlongliu.arch-logo/` | 自研 bar 插件的源码（`BarWidget.qml` + `arch-logo.svg` + `manifest.json`；无 `clonedFrom`，不是上游克隆） | 拷到 `~/.config/omarchy/plugins/jianlongliu.arch-logo/` |
| `split-lock/ir-light` | PAM 人脸栈点名的 IR 补光脚本（`pam_exec.so /usr/local/bin/ir-light`）的仓库副本 | `install -m 0755 split-lock/ir-light /usr/local/bin/ir-light`；**硬件专属，见 §5** |
| `niri-config/local/*.kdl`（7 份） | **本机在用的 niri 配置**（`config` + `input/monitor/layout/window-rules/effects/binds` 的模块化拆分） | 拷到 `~/.config/niri/`、把 `/home/<user>` 换成自己家目录、按自己显示器改 `monitor.kdl`，然后 `niri validate`；说明见 `niri-config/README.md` |
| `niri-config/omarchy.kdl.template` + `shell.json` 示例 | niri 侧接线 | `install.sh` 会渲染成 `~/.config/niri/omarchy.kdl` 并拷 `shell.json`（**仅当不存在**）；**本机没走这条** —— 用的是模块化拆分，`config.kdl` 直接 include `{input,monitor,layout,window-rules,effects,binds}.kdl`，`omarchy.kdl` 不存在 |
| `hooks/post-update.d/10-niri-repatch`、`hooks/theme-set.d/{10-niri-border,20-materal}` | 更新后重放覆盖层；换主题写边框渐变 | Omarchy 钩子机制自动调 |
| `split-greeter/`、`split-lock/` | 自研登录器与锁屏，各带 `install.sh` + `tests/` | `sudo ./install.sh`（split-greeter 不碰 `config.toml`，最后一步手工） |
| `default/omarchy/omarchy-menu.jsonc` | `install.package`/`install.aur`/`remove.package` 的 `xdg-terminal-exec` 回退 | 随仓库/覆盖层 |
| `docs/` | `INSTALL{,.zh}.md` + **主文档 `omarchy-on-niri-port.md`（当前事实 + 映射表）** + 模块卷 `visual/behavior/plugins/shims/upstream/migration/lock/local-overrides`（编号沿用原号），**正本就在 `docs/`** | 直接改 `docs/`，无第二副本 |

- 覆盖层实际内容：**22 文件 / 48 hunk**（`--reverse --check` 通过、repatch 幂等）；
  **md5 `6138cc1bece9a94312572d8685c845a4`**，与 `~/.config/omarchy/niri-port/niri.patch` 一致（2026-09-21 晚重导出核；
  比 2026-09-20 那版多 `shell/shell.qml` 的 boot reveal 标记 + `pushBootReveal()` 推送、以及 `shell/plugins/bar/Bar.qml` 的滑入，见 §9 / `docs/visual.md` 第 33 条；
  比 2026-09-21 01:29 那版（46 hunk）多 `Background.qml` 的 `paintedOnce` 与 `shell.qml` 的推送增补 —— 那两处活体先改、补丁没跟上，曾让 repatch 判 exit 2）。
- **在用的 bar 是第三方插件，不在 `niri.patch` 里**：`~/.config/omarchy/shell.json` 的 `bar.id = charlieras262.floating-bar`，
  它的 boot reveal 走 `niri-port/plugin-patches/charlieras262.floating-bar.patch`（md5 `0d36c626a9992de5a457e3f2880bc99a`，7 hunk，2026-09-21 核；含加载期底部 `Thinking…` 卡片——卡片照 OSD 关机吐司的尺寸/字体做，表面是**卡片大小 + 借用 `omarchy-osd` 那条霜化规则**，收卡时机等宿主推的"壁纸已画"而不是固定时长），
  该补丁**没有自动重放器**，插件被更新覆盖后要手工 `git apply`。

---

## 2. `~/bin` 垫片（本机 PATH 层，22 项含备份）

| 名字 | 说明 | 仓库里有? |
|---|---|---|
| `hyprctl` | Hyprland 兼容层（脚本改了 `monitors`/`eval` 等才在 niri 上跑得动） | ✅ `port-bin/` |
| `uwsm-app` | 吃掉 `uwsm-app -- <cmd>`（niri 没有 uwsm）。**里面绝不能有 `setsid`**（见垫片卷 `docs/shims.md` §8 第 22 条） | ✅ |
| `materal-update` | 取色/重上色 | ✅ |
| `omarchy-niri-system` | logout/reboot/shutdown 统一入口（logind D-Bus，免密） | ✅ |
| `omarchy-niri-apply-theme` | 按主题 token 写 niri 的边框渐变（两带方案） | ✅ |
| `omarchy-niri-repatch` | 重放覆盖层（幂等） | ✅ |
| `omarchy-powerprofiles-{list,set}` | 电源档位 | ✅ |
| `omarchy-update` | 垫片 → `sudo pacman -Syu`；手装机跑不通上游 update 流程 | ✅ `port-bin/`（2026-09-20 收进） |
| `omarchy-picker-warmup` | 配合用户单元延迟预热选择器缩略图 | ✅ `port-bin/`（2026-09-20 收进） |
| `omarchy-display-text-size` | bar 的 Display 面板字号滑块驱动全桌面（CLI 路径绕过它） | ✅ `port-bin/`（2026-09-20 收进） |
| `wechat`、`clipboard-sync.sh`、`clipboard-handler.sh` | 移植之前的老自建，保留 | ❌（与本移植无关） |

- 上表 11 项与仓库 `port-bin/` 的对账（2026-09-20 `md5sum` 逐个核过）：**10 项逐字节一致**；
  唯一例外是 `omarchy-update` —— 仓库版只把注释改成了通用措辞（"这类机器"而不是"本机"），
  **代码体逐行相同**（`diff <(grep -v '^#' ~/bin/omarchy-update) <(grep -v '^#' port-bin/omarchy-update)` 为空）。
- 回退：`rm ~/bin/<名字>`（若 `$OMARCHY_PATH/bin` 有同原件，会自动回退到它）。

---

## 3. 用户级 Omarchy 配置（`~/.config/omarchy/`，热生效）

| 文件 | 关键内容 | 回退 |
|---|---|---|
| `shell.json` | bar 用 `charlieras262.floating-bar`（`centerAnchor: omarchy.clock`、`cornerRadius 10`、`floatGap 8`）；`omarchy.tray.hidden: ["Fcitx"]`（藏掉 fcitx5 的托盘图标）；`omarchy.power.showPercentage`；`ronald.input-sources.showSourceName=false`；`meviusisback.ai-subs`（`barDisplay: Data`、900s）；`idle.lock 300` / `idle.screensaver 150`（**screensaver 已由 flag 禁用**）；`disabledPlugins: ["omarchy.lock"]`；`plugins: [jianlongliu.split-lock, io.github.claudsondouglas.arcdock]` | `.bak-20260919-preaisubs`、`.bak-20260919-prehidetray`、`.bak-20260920-bar`、`.bak-20260920-bardisplay` |
| `shell.toml` | `[font] base-size 12`；`[bar]` 尺寸 + `background-alpha 0.45` + **`icon-font 12`**（要 `Style.qml` 的白名单，已进覆盖层）；`[popups]/[notifications]/[tooltip]` alpha；`[menu]` 只有 `background-alpha 0.45`、**不写底色**（走主题的 `[menu] background` ＝ matugen 出的 `colors.toml` `background`，跟 `[bar]` 同档半透明磨砂；2026-09-21 起，替掉 9-20 写死的 `"#2a2a22"` @ 0.7） | `.bak-20260920-{consistency,iconfont,menu}`、`.bak-20260921-menu` |
| `extensions/omarchy-menu.jsonc` | 菜单用户层 override：`trigger.*` 屏蔽、`setup.input` 指 `niri/input.kdl`、screensaver 6 条 `when:"false"`。⚠ 同一 id 别写两遍；**别写行内注释**（`stripJsonc` 只删整行注释） | `.bak-20260919-{prehide,prelearn}`、`.bak-20260920-prescreensaver` |
| `niri-port/` | `niri.patch`（与仓库同 md5）、`Niri.qml`、`plugin-patches/*.patch`（4 个，机器独有，见 §6） | 各自的 `.bak-*` |
| `plugins/`（8 个） | 自研：`jianlongliu.arch-logo`（**源码已进仓库 `plugins/jianlongliu.arch-logo/`**）、`jianlongliu.workspaces`（上游克隆 + `niri-port/plugin-patches/jianlongliu.workspaces.patch`）、`jianlongliu.split-lock`（**正本 `split-lock/`**）（**没有 `.git`**，`omarchy plugin update` 不碰）；第三方：`charlieras262.floating-bar`、`ronald.input-sources`、`meviusisback.ai-subs`、`jrmmhm.pocket`、`io.github.claudsondouglas.arcdock`（**本身就是上游 git 克隆**，本地魔改用 `git diff` 就地生成 patch） | `plugin-patches/*.patch` 反向 `git apply -R` |
| `hooks/` | 与仓库同（`post-update.d/10-niri-repatch` 的 `omarchy-restart-shell` 那 8 行 2026-09-20 已并回仓库，两侧 md5 `b077156959bc9cfb4c37941a4ffb3a5e` 一致） | 从仓库重拷 |

---

## 4. niri 配置（`~/.config/niri/`）

- 文件：`config.kdl`（只留 include 与会话级设置）、`binds.kdl`、`layout.kdl`、`window-rules.kdl`、
  `effects.kdl`、`input.kdl`、`monitor.kdl`；每个都在备份根留了 `.bak-*`（改前必留）。
  **2026-09-20 已收进仓库**：`niri-config/local/`（家目录参数化成 `/home/<user>`，说明见该目录 README）。
  **2026-09-21 两处新改**：① `layout.kdl` 的 `layout { background-color }` —— 这就是**开机到壁纸画出来之间那一屏的底色**（niri 内建默认 `#404040` 深灰，配置里原本没人设过；实测用 `#FF00FF` 试色当场生效），现设成**当前壁纸的平均色**（`magick <bg> -resize 1x1!` 取，当时 `#BDBDBE`），开机那屏因此从"深灰洞"变成与壁纸亮部接近的平色；换壁纸后可跟着重取。② `config.kdl` 的 `cursor` 块加了 `hide-after-inactive-ms 1000`（原块已有 `hide-when-typing`、`Bibata-Modern-Amber` 20）：想让**开机那根箭头**自己消失——niri 没有"立刻藏"的接口，这是唯一的旋钮；副作用是平时停手 1s 箭头也没。备份 `config.kdl.bak-20260921-cursor`（`layout.kdl` 那份 `bgcolor` 备份已随后续改动清掉）。
- **壁纸从会话第一帧就在（2026-09-21 晚，本机新装的包）**：`swaybg`（**extra 仓库 `pacman -S swaybg`，1.2.2-1，非 omarchy 自带**）由 `config.kdl` 的 `spawn-at-startup "swaybg" "-i" "/home/<user>/.local/state/omarchy/current/background" "-m" "fill"` 拉起（走 omarchy 的"当前壁纸"软链 ⇒ 换壁纸自动跟）。
  动机：Quickshell 的 `omarchy.background` 要 ~1.4s 才画出壁纸，这段只有一屏底色（见 `docs/lock.md` §11.27 的"② 可打的部分"）。
  **实测三点**：① `-m fill` = 源图 cover 居中，与插件渲染**逐像素一致**（130 个纯壁纸区块差 0.01/255）⇒ 插件那份上来时无缝；② 杀掉壳层后壁纸仍在（顺带成壳层崩溃时的兜底）；③ **同一 background 层内"后映射的在上"**——把 swaybg 起在壳层之后它就压住插件那份（用一张品红测试图复现：此时换壁纸会看到旧图）。
  故这行**必须排在 `spawn-sh-at-startup "omarchy-launch-shell"` 之前**（niri 按配置里的先后顺序 spawn）；排对了插件永远在上面，swaybg 常驻无害。
  画质：swaybg 走 gdk-pixbuf（连 cairo/png），本机壁纸是 jpg/png ✓；**`.webp` 未装加载器**（`webp-pixbuf-loader`），真换 webp 壁纸要补包。
  不想要了就删这行 + `pacman -Rns swaybg`（唯一影响：回到那 1.4s 空窗）。
- **静默陷阱**：bind 里写开窗属性（`open-floating` 等）→ `only one action is allowed per keybind`，
  而 niri 对**整份** `config.kdl`（含 include）做事务性校验，一处失败**整体丢弃、继续跑旧配置、桌面零提示**。
  改完必须 `niri validate`，再看 `journalctl | grep 'niri\['`。
- KDL 普通字符串里 `\.` 非法（`invalid escape char`）→ 用 `r#"…"#` 或不转义。
- 磨砂五处（effects + window-rules + ghostty + shell.toml + 覆盖层 QML）缺一不可，且**一律 `xray false`**。

---

## 5. 系统级（root / `pkexec`）

| 路径 | 内容 | 回退 |
|---|---|---|
| `/etc/pam.d/omarchy-lock-password` | 锁屏密码门禁（faillock + pam_unix，**不含 howdy**） | 覆盖层/安装器写的，没留 `.bak`；改动前自己 `cp` |
| `/etc/pam.d/omarchy-lock-face` | 锁屏人脸（howdy）独立服务：`auth optional pam_exec.so /usr/local/bin/ir-light` + `pam_python.so /lib/security/howdy/pam.py` | `split-lock/face-pam.sh --remove` |
| `/etc/greetd/config.toml` | `command = "/usr/local/bin/split-greeter"`、`user = "greeter"` | 同级 `config.toml.backup-*`（旧 greeter，真回滚点） |
| `/etc/greetd/split-greeter/` | 登录器 shell + bridge（world readable） | 重跑 `split-greeter/install.sh` |
| `/usr/local/bin/{split-greeter,split-greeter-sync,ir-light}` | 登录器入口、主题/壁纸同步、IR 补光 | 前两个重跑对应 `install.sh`；`ir-light` 仓库副本 `split-lock/ir-light`。**它硬件专属**：写死 `open("/dev/video2")` + UVC 扩展单元 `unit=13 selector=14`（ThinkPad X1 Carbon Gen9 的 Chicony 04f2:b6ea），换机要按自己 IR 摄像头改这两处，否则只是点不亮灯（PAM 里是 `optional`，坏了不会把人锁在外面）。仓库那份必须与 `/usr/local/bin/ir-light` **逐字节相同**（`scripts/local-files-sync.sh` 就守这条），所以说明只能写在这里 |
| `/usr/local/bin/omarchy-greeter`、`omarchy-greeter-sync` | 兼容软链 → `split-*` | — |
| ~~`/etc/systemd/system/flclash-helper.service`~~ **2026-09-21 已删**（用户点名） | FlClash 的 TUN 特权助手：`ExecStart="/usr/lib/flclash/FlClashHelperService"`、`RuntimeDirectory=flclash`、`Environment=FLCLASH_HELPER_OWNER_{UID,GID}=1000`、`WantedBy=multi-user.target`。**FlClash 卸载后单元还留着 `enabled`**，于是每次开机 `203/EXEC`（可执行文件没了）重试 5 次 → `start-limit-hit`，白刷一屏红字（`--since "-3 days"` 里 12 次）。删前核过：`/usr/lib/flclash`、`~/.config/FlClash`、`/run/flclash` **都不存在**（FlClash 包也没装），残留为零；同目录 `vpn-hotspot.service` 只在 Description 文字里提 flclash、**没有任何 `Requires=`/`After=` 依赖**（且它自己 `disabled`+`inactive`，本轮没动）。代理已由系统级 `mihomo` 接管 | `pkexec cp ~/.local/state/backups/etc/systemd/system/flclash-helper.service.bak-20260921-deleted /etc/systemd/system/ && pkexec systemctl daemon-reload && pkexec systemctl enable --now flclash-helper.service`（**前提是 FlClash 重新装上**，否则又是 203/EXEC） |
| `/etc/systemd/logind.conf.d/20-inhibit-delay.conf` | `[Login] InhibitDelayMaxSec=15`（2026-09-21 装，用户拍板）：`omarchy-sleep-lock.service` 的延迟抑制剂窗口上限，给"合盖→锁"留 ~12s 预算（不装只有默认 5s ⇒ 4s 预算）。源件是上游 `$OMARCHY_PATH/etc/systemd/logind.conf.d/20-inhibit-delay.conf`，逐字照抄 | `pkexec rm /etc/systemd/logind.conf.d/20-inhibit-delay.conf && systemctl reload systemd-logind`（**改前本机没有这个文件**；同目录另有更早的 `lid-suspend.conf`，三档合盖都设 `suspend`，2026-05-19 装机写入） |

- 换主题/壁纸后同步到登录页：`sudo split-greeter-sync "$USER"`（还有实验账户时要一起列）。
- 登录页切换是唯一会把自己锁在外面的步骤，所以 `split-greeter/install.sh` **故意不碰 `config.toml`**。

---

## 6. 用户级 systemd 单元

| 单元 | 说明 | 仓库里有? |
|---|---|---|
| `omarchy-crash-watch.service` | 本机版：`ExecStart` 指 `~/.local/share/omarchy/bin/omarchy-crash-watch`，并显式给 `PATH`/`OMARCHY_PATH`（用户管理器环境里没有这两样） | ✅ `default/systemd/user/`（模板指 `/usr/bin/…`，本机包不存在） |
| `omarchy-picker-warmup.service` | `PICKER_WARMUP_DELAY=45` + `ExecStartPre=/bin/sleep`；`toggles/picker-warmup-off` 存在即跳过 | ✅ `default/systemd/user/`（`%h` 模板，2026-09-20 收进；`install.sh` 第 4 步装并链接） |
| `omarchy-sleep-lock.service` | **本机版**：上游那两条 `ConditionEnvironment=` 全删 —— ① `OMARCHY_PATH` 那条读的是**用户管理器**环境、**看不见单元自己的 `Environment=`**（2026-09-21 探针实证），本机又没 UWSM 去 import 它；② 另一条 `WAYLAND_DISPLAY` 看着满足，但**条件是单元被拉起那刻评估的，而单元由 `graphical-session.target` 拉起、那会儿会话还没把环境发布进用户管理器**（2026-09-21 重启实证：20:10:17 被跳过、20:10:18 niri 才起来）⇒ 抑制剂挂不上、合盖不锁。本机版显式给 `OMARCHY_PATH`/`PATH`（`omarchy-system-sleep-lock` 里是裸 `omarchy-shell`），`ExecStart` 指包装器 `%h/bin/omarchy-sleep-lock-start`（`port-bin/omarchy-sleep-lock-start`：有界等会话环境发布 → 采纳 `WAYLAND_DISPLAY`/`XDG_RUNTIME_DIR`/`NIRI_SOCKET` 等 → `exec` 上游 monitor）。**合盖/挂起锁屏就靠它**，见 `lock.md` §11.28 | ✅ `local-config/systemd/user/` + `port-bin/`（2026-09-21 收进） |
| `materal-recolor.{path,service}` | **是本移植的一部分**（不是无关物件）：`.path` 盯 Omarchy 壁纸文件，一变就拉起 oneshot `.service` 跑 `%h/bin/materal-update`（`port-bin/` 里的 matugen 包装，机制见主文档 §8.10）。上游没有、也没有包认领 | ✅ `local-config/systemd/user/`（2026-09-20 收进；装法 `systemctl --user enable --now materal-recolor.path`） |
| `wechat-clipboard-sync`、`wl-clip-persist`、`wl-gammarelay`、`xsettingsd` | 与本移植无关（第一个是私人物件，后三个是通用 Wayland 守护进程；四者都无包认领），仅共存。**`wechat-clipboard-sync` 2026-09-21 修过脚本里的 flock 写法**（同步链真的死了，详见 §8 第 13 条）；它是 `Type=oneshot`+`RemainAfterExit=yes` 而 `ExecStart` 永不退出 ⇒ 永远停在 `activating`、**`systemctl restart` 会挂住**（要 `stop` 再 `start --no-block`） | — |

- 三个 omarchy 单元都软链进 `graphical-session.target.wants/`（**`omarchy-sleep-lock` 是 2026-09-21 才补上的**：本机走 dev-link 装机、绕过上游 first-run 的 `enable-user-units.sh`，所以那批单元集体没装；逐个查过后只有它是真缺口，见 `lock.md` §11.28）。

---

## 7. 状态、工作区与 patch 重生成

- `~/.local/state/omarchy/toggles/screensaver-off` = **screensaver 禁用 flag**（用户明确要关，别恢复）。
- `~/.local/share/omarchy` = `$OMARCHY_PATH`，**工作区里有非移植改动**（2026-09-20 核：`git status` 265 条，
  主要是主题删除）→ **重生成 `niri.patch` 必须限路径**，否则 22 文件会膨胀成 250+：

```bash
# 旧 patch 的文件清单 + 本次新增的文件
git diff -- $(grep '^diff --git' niri.patch | sed 's|.* b/||') <新增文件> > niri.patch
git apply --reverse --check niri.patch   # 必须通过
~/bin/omarchy-niri-repatch               # 应回 "already applied"
```

- `~/Documents/omarchy-niri-*.md`（九个）**已删**（2026-09-21）：2026-09-20 文档归一时它们曾是指向 `docs/` 的软链，
  守它们的 `./scripts/check-doc-links.sh` 一并退役。正本只在 `docs/`，不再有入口层。归一前的真副本备份仍在
  `~/Documents/AI Agents/archive/doc-backups/pre-merge-20260920-232818/`（九个文件，逐字节等于当时的仓库版）。
- 第三方插件的本地魔改：`cd ~/.config/omarchy/plugins/<id> && git diff > ~/.config/omarchy/niri-port/plugin-patches/<id>.patch`，
  改完核对 `git apply --reverse --check` 通过。
- `plugin-patches/*.patch` **没有自动重放器**：`omarchy-niri-repatch` 只管 `$OVL/niri.patch` + `Niri.qml` + `$OVL/plugins/*`；
  插件被 `omarchy plugin update` 覆盖后要手工 `git apply`。

---

## 8. 缺口：本机有、仓库没有（换机不可复现）

1. ~~三个 `~/bin` 垫片~~ **已收进仓库（2026-09-20）**：`port-bin/{omarchy-update,omarchy-picker-warmup,omarchy-display-text-size}`
2. ~~`omarchy-picker-warmup.service`~~ **已收进仓库**：`default/systemd/user/omarchy-picker-warmup.service`
   （写成 `%h` 模板；本机那份是写死 `~` 的等价物）
3. ~~`plugin-patches`~~ **已收进仓库（2026-09-20）**：`niri-port/plugin-patches/`（4 个 patch + README，
   说明怎么 `git diff` 生成、怎么 `git apply` 重放）；机器上这些 patch 的 `.bak-*` 是历史，仍只在本地（备份根里）。
4. ~~`~/.config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}` 的实际取值~~
   **已收进仓库（2026-09-21）**：`local-config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}`
   （照 `local-config/` 的样子逐字节镜像，`local-files-sync.sh` 自动认，已验 rc=0）。三份复扫过
   **不含任何密钥**（无 token / 无 `.hermes`/`.env` 引用 / 无邮箱、URL 凭据），路径零字面量
   （`omarchy-menu.jsonc` 里那处走的是 `$HOME`），出现的 `jianlongliu.*` 只是插件 id。
   ⚠ **换机注意**：这份 `shell.json` 钉的是本机的 bar 偏好 —— `bar.id = charlieras262.floating-bar`
   ＋ 5 个第三方部件（`charlieras262.floating-bar` / `io.github.claudsondouglas.arcdock` /
   `jrmmhm.pocket` / `meviusisback.ai-subs` / `ronald.input-sources`）**都不在仓库里**，直接照抄会得到
   一条缺部件的 bar；`niri-config/shell.json`（上游默认盘）才是中性起手式，两份都留着，按需选。
5. ~~钩子漂移~~ **已修（2026-09-20）**：本机那份多出的 8 行（更新后 `omarchy-restart-shell` ——
   上游 `omarchy-update-restart` 只给"重启"选项，而 QML 换了不重启等于旧部件继续跑、菜单 jsonc 写到一半
   还会解析成空菜单）已并回仓库，两侧一致。
6. `/etc/pam.d/omarchy-lock-face`、`/etc/greetd/*` 是 `split-*/install.sh` 装的（脚本在仓库），
   但**已装好的机器状态**没有版本记录。
7. ~~本机 niri 配置（`~/.config/niri/` 七份 kdl，约 910 行）~~ **已收进仓库（2026-09-20）**：
   `niri-config/local/`（家目录参数化为 `/home/<user>`，`monitor.kdl` 的 modeline 标了「本机面板专属」）。
   此前仓库只有 `niri-config/omarchy.kdl.template`，而本机**没用**那条路 —— 别人照仓库装会缺合成器侧一整块。
8. ~~本机 ghostty 配置~~ **已收进仓库（2026-09-20）**：`local-config/ghostty/config`。
   此前仓库里的 `config/ghostty/config` 是**上游默认**（与
   `~/.local/share/omarchy/config/ghostty/config` 逐字节相同），于是**磨砂五处里"ghostty"那一处整个缺失** ——
   别人照仓库装得到的是"有窗口装饰、无磨砂"，正是本移植当初修掉的症状。
   配色**不随仓库带私有主题文件**：本机原先是 DMS 时代遗留的 `theme = dankcolors`（那份 454 B 静态文件仓库与
   上游都搜不到生成器），2026-09-20 已改回上游写法 `config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"`
   —— 换主题即换配色，机器上那份 `~/.config/ghostty/themes/dankcolors` 已无引用、仅存于本机。
9. ~~自研插件 `jianlongliu.arch-logo` 的源码~~ **已收进仓库（2026-09-20）**：`plugins/jianlongliu.arch-logo/`
   （3 个文件，12 K）。它 manifest 里**没有 `clonedFrom`**，不是上游克隆，所以没有 patch 可以复现 ——
   此前仓库里只在文档里提过它。（`jianlongliu.workspaces` 有 `omarchy.clonedFrom`，靠
   `plugin-patches/jianlongliu.workspaces.patch` 可复现，不需要额外收。）
10. ~~`/usr/local/bin/ir-light`（IR 补光脚本）~~ **已收进仓库（2026-09-20）**：`split-lock/ir-light`。
    此前 `/etc/pam.d/{omarchy-lock-face,greetd}` 都点名 `pam_exec.so /usr/local/bin/ir-light`，而
    `split-lock/face-pam.sh` 只是**检查它在不在**、不装它 —— 别人照仓库装完，暗光下人脸认不出来
    （`optional`，所以不会把人锁在外面）。硬件专属，改法见 §5。
11. ~~`materal-recolor.{path,service}`~~ **已收进仓库（2026-09-20）**：`local-config/systemd/user/`
    （此前 §6 把它误判成"与本移植无关"，其实它跑的就是 `port-bin/materal-update`）。
12. `~/.config/omarchy/{backgrounds,themes}`（壁纸与个人主题，3.3 M）、`~/.config/{Code,Discord,starship.toml,…}`
    —— **不打算收**：个人素材与私人偏好，与本移植无关。
13. **三个"旧存档"（2026-09-21 清 `ls` 时挖出来的，都不是备份、都没人引用，一律加点隐藏、不删）**：
    - `~/bin/.clipboard-sync.bad`（762 B，2026-08-13 01:08）：微信剪贴板同步的**死锁版** —— `wl-paste --watch`
      的回调里再调 `wl-paste`，在 wl-clipboard 2.3 上自己锁自己（活的那份 `~/bin/clipboard-sync.sh` 是 7 分钟后
      重写的架构：watch 只打标记、独立循环消费 + `flock` 单实例；`wechat-clipboard-sync.service` 用的是它）。
      **⚠ 但活的那份 2026-09-21 查出同样是坏的，同日修好并实测通过**：`flock -w 3 "$LOCK"` 只给了**路径、没给命令**
      ⇒ util-linux 2.42.3 的 `flock` 把唯一参数当 **fd 号**、直接 `flock: bad file descriptor: '/tmp/clip-sync.lock'` rc=64
      （本机实测复现）⇒ 循环里那行**永远走 `|| { sleep 0.3; continue; }`**，后面的 `rm -f "$FLAG"` 和真正的同步代码
      **从没执行过** ⇒ **微信剪贴板同步实际早已失效**（`~/.cache/clip-sync-flag` 自开机 20:10:18 起从没被消费），
      只剩 0.3s 一圈空转、每圈 fork 一个 flock 子进程刷 journal（systemd 的 `SyslogIdentifier` 让这些子进程都署名
      `clipboard-sync.sh`，所以看着像"脚本在被反复重启"；实测 198 行/分钟）。**修法**：删掉循环里那行，改成循环外
      `exec 9>"$LOCK"; flock -n 9 || exit 0`（真单实例；单元 `Restart=no` 所以退出安全）。**实测**：Wayland 写入
      `ANTE-FIXED-…` → X11 `xclip -o` 逐字相同 ✓；PNG 6,131,730 B → X11 收到 6,131,730 B ✓；标记文件每次都被消费 ✓；
      空转日志降到 1 行/20s ✓。备份 `~/.local/state/backups/bin/clipboard-sync.sh.bak-20260921-flock`。
      （方向只有 W→X：微信复制、浏览器粘贴那条路**本来就没实现**，单元 Description 写 `<->` 是名不副实。）
    - `~/bin/.wechat.plan-b`（283 B，2026-08-13）：微信启动器备用版；活的 `~/bin/wechat` 是 2026-09-20 版，
      多一个 `--in-process-gpu`。
    - `~/.config/.niri-dms-retired-20260919/`（15 个文件）：**DMS 时代的 niri 配置存档**
      （`config.kdl` + `user.kdl` + `dms/*.kdl` 九个 + `gtk-4.0-stale/` 两份，8 月那批），2026-09-19 移植接管时
      整个退役、留作回滚点。**本文档此前从没记过它**（所以清 `ls` 时才像新发现一样冒出来）。

---

## 9. 一句话回退索引

| 想撤销 | 命令 |
|---|---|
| 某个 `~/bin` 垫片 | `rm ~/bin/<名字>` |
| 覆盖层（回到上游 omarchy） | 在 `$OMARCHY_PATH` 里 `git apply -R ~/.config/omarchy/niri-port/niri.patch`（`omarchy-niri-repatch` **没有**反向开关，反向只能手动 `git apply -R`） |
| 用户级 shell 配置 | 从备份根覆盖回去：`cp ~/.local/state/backups/.config/omarchy/<文件>.bak-* ~/.config/omarchy/<文件>`（热生效，存盘即回） |
| 桌面交接的 bar 滑入（boot reveal） | 反向重放旧覆盖层 `niri.patch.bak-20260921-bootcurtain2`（= 上一版）或 `…bootcurtain`（= 更早的黑幕版），再 `omarchy-restart-shell`；只想关掉动画：删 `$XDG_RUNTIME_DIR/omarchy-boot-splash` 的写入者（`split-greeter/session.sh` 那行）或干脆不装它 |
| 登录交接的另外三处（刷黑 + 输出改道 + 登录面淡出） | 用仓库 HEAD 覆盖 `split-greeter/{install.sh,niri.kdl,Greetd.qml,shell.qml}` 并删 `session.sh`，`GREETER_SESSION` 改回 `niri-session`，重跑 `pkexec ./install.sh` |
| 登录页 | 恢复 `/etc/greetd/config.toml.backup-*`，再 `systemctl restart greetd`（**在 TTY 里做**） |
| 锁屏人脸 | `sudo split-lock/face-pam.sh --remove` |
| 删掉的 `flclash-helper.service`（其实没必要恢复） | 见 §5 那行；备份在 `~/.local/state/backups/etc/systemd/system/flclash-helper.service.bak-20260921-deleted` |
| 合盖/挂起锁屏 | `systemctl --user disable --now omarchy-sleep-lock.service`（回到"合盖不锁"；日志排查法见 `lock.md` §11.28） |
| 微信剪贴板同步脚本改坏 | `cp ~/.local/state/backups/bin/clipboard-sync.sh.bak-20260921-flock ~/bin/clipboard-sync.sh`，再 `systemctl --user stop wechat-clipboard-sync.service && systemctl --user start --no-block wechat-clipboard-sync.service` |
| screensaver 恢复 | 删 `~/.local/state/omarchy/toggles/screensaver-off` + 复原 `omarchy-menu.jsonc.bak-20260920-prescreensaver` |
| 选择器预热 | `touch ~/.local/state/omarchy/toggles/picker-warmup-off`（或 `systemctl --user disable --now omarchy-picker-warmup`） |
| 插件本地魔改 | 在该插件目录 `git apply -R ~/.config/omarchy/niri-port/plugin-patches/<id>.patch` |
