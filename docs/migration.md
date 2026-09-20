# 账户迁移 — Omarchy on niri 卷（migration）

> 正本：`~/Documents/omarchy-niri-migration.md`（与仓库 `docs/migration.md` 逐字节一致）。
> 本卷 2026-09-20 从 `omarchy-on-niri.md` 抽出（模块化拆分），**编号一律沿用正本** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，正本对应位置留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `omarchy-on-niri.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `omarchy-on-niri.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 11. 账户迁移：实验账户 → 主账户（2026-09-19 方案）
- 17. **迁移到主账户 jianlongliu 系统级 vs 用户级（2026-08-30 梳理）**：本移植目前在用户

---

## 11. 账户迁移：实验账户 → 主账户（2026-09-19 方案）

### 11.0 背景与目标

- 两个账户同属一人：`jianlongliu`（uid 1000）是**日用主账户**，`yvonne`（uid 1001）是**专门给本移植做实验**的账户。本节是把移植整体搬进主账户的 runbook。
- **新 session 从哪读**：文档正本随仓库走 —— `git clone https://github.com/jianlongliu/omarchy-on-niri`（公开仓，主账户无需凭据），正文在 `docs/omarchy-on-niri-port.md`，§11 就是本节。`/home/yvonne/Documents/omarchy-on-niri.md` 是 0600，**主账户读不到**（§11.2）；`/var/tmp` 里的摘录重启就没了，不要当唯一来源。
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
5. **搬目录**（11.7，含打包/解包命令）：整份 `~/.local/share/omarchy`、`~/.config/{omarchy,niri}`、`~/.local/state/omarchy`、`~/bin`、systemd 用户单元
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
| `~/.local/state/omarchy` | 7.2M | **`migrations/` 里那 121 个标记**：缺了 `omarchy update` 会重放全部迁移（含危险项）；另有 `toggles/`（功能开关，如 `screensaver-off`，§8 第 23 条） |
| `~/.config/niri` | 80K | 移植的模块化配置（基座另按 11.6 处理） |
| `~/bin` | — | 垫片与包装脚本（仓库 `port-bin/` 是同一批；`__pycache__/*.pyc` 是缓存，删掉即可） |
| `~/.config/systemd/user/materal-recolor.{path,service}` | 8K | 主题取色监听（§8.10）；用 `%h` 是便携的，但 `default.target.wants/` 里的绝对软链要重新 `enable` 生成 |
| fcitx5 配置 + `~/.config/gtk-3.0/settings.ini` | — | 双源 + `ShareInputState=All`（§8.17）与 GTK 字号对齐 |
| `~/.config/omarchy/plugins/*` | 小 | **当前唯一的锁提供者是 `yvonne.split-lock`**（§11.18；explorer 已于 2026-09-19 移除，其每账户状态 `lock-{videos,designs}` 可搬可不搬）。其余用户插件：`charlieras262.floating-bar`（浮栏）、`ronald.input-sources`、`yvonne.{arch-logo,workspaces}`。整套 `plugins/` 随 `~/.config/omarchy` 一起走，无需单独处理 |

**怎么运（实验账户 → 主账户）**：`/home/yvonne` 是 0700，主账户读不到，所以走 `/var/tmp`（§11.2 路线 2）。

```bash
# 实验账户侧：打包（/var/tmp 在 / 上、重启留存，约几百 MB）
tar -C /home -czf /var/tmp/yvonne-to-main.tar.gz --exclude='__pycache__' \
    yvonne/.local/share/omarchy yvonne/.config/omarchy yvonne/.config/niri \
    yvonne/.local/state/omarchy yvonne/bin yvonne/.config/systemd/user \
    yvonne/.config/fcitx5 yvonne/.config/gtk-3.0

# 主账户侧：以 jianlongliu 身份解，**不要 sudo**（否则文件归 root），--strip-components 把顶层 yvonne/ 去掉
tar -C "$HOME" -xzf /var/tmp/yvonne-to-main.tar.gz --strip-components=1
```

**搬完的三个坑**：

1. **硬编码路径不止 `config.kdl` 那三行**：扫一遍 `grep -rl '/home/yvonne' ~/.config ~/bin ~/.local/share/omarchy ~/.local/state/omarchy 2>/dev/null`，逐个改。
2. **绝对软链会悬空**：`find ~/.config ~/bin ~/.local -xtype l 2>/dev/null` 列出坏链重建（`systemctl --user enable --now ...` 那类必须重新生成）。
3. **别把缓存和历史快照一起搬**：`__pycache__/`、`~/.cache/`、`niri-port/backups/` 可弃；但 `~/.local/share/omarchy/.git` **必须留**（238 条删除与分支状态在它身上）。

搬完的**验收数字**（与实验账户逐一对齐）：

```bash
git -C ~/.local/share/omarchy status --short | grep -c '^ D'   # 238
git -C ~/.local/share/omarchy status --short | grep -c '^ M'   # 20
grep -c '^@@' ~/.config/omarchy/niri-port/niri.patch           # 36（20 文件）
ls ~/.local/state/omarchy/migrations | wc -l                   # 121
systemctl --user daemon-reload && systemctl --user enable --now materal-recolor.path
```

**唯一的硬编码路径**：`~/.config/niri/config.kdl` 第 18 / 19 / 32 行写着 `/home/yvonne`（`OMARCHY_PATH`、`PATH`、`spawn-sh-at-startup` 的 `-p` 参数），必须全改成 `/home/jianlongliu`。`~/bin/*` 与两个 systemd 单元用的是 `$HOME` / `%h`，便携。

### 11.8 迁移后自检

```bash
niri validate
omarchy version
omarchy-shell lock status           # passwordPam 应为 true
omarchy-shell lock isLocked         # 能应答（说明有锁处理器注册）
omarchy-migrate --pending           # 应为空
omarchy plugin list | grep lock     # 应只有 yvonne.split-lock enabled
~/bin/hyprctl -j monitors | jq -r '.[0].scale'
```

外加人工确认：bar 三件套（胶囊工作区 / Arch logo / 浮栏）、输入源徽章 `rime ⇄ keyboard-us`、媒体键 OSD、亮度条（`video` 组生效）、`omarchy theme bg next` 能触发 materal 取色、**真人按一次 `Mod+Ctrl+L` 锁屏并解锁**（✅ 2026-09-19 已完成，见 §11.20）。

### 11.9 回滚

- 系统层：`sudo snapper -c root undo <N>`；家目录：`sudo snapper -c home undo <N>`
- 只回壳层：重装 `dms-shell dms-shell-niri` 后 `systemctl --user enable --now dms.service`
- 移植侧：`~/.config/omarchy/niri-port/` 内有备份，覆盖层可 `git apply --reverse`

### 11.10 锁屏插件 `io.github.sirjul1337.lock-explorer`（能力边界与搬运）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### 11.11 登录界面：自研 Quickshell greeter「Split Greeter」（Split 设计，多账户 + 人脸）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### 11.12 登录界面：一条卡住的 PAM 对话 = 密码"没反应"（2026-09-19 真机实测与修法）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### 11.13 密码"按回车没反应"的真正原因：宿主少接了一条设计信号（2026-09-19 二次实测）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### 11.14 人脸改成"回车触发"（2026-09-19，用户指定）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

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
- `~/bin/` 里自写的：`hyprctl`（niri 的 shim，**必需**；`.bak-*` 可丢）、`uwsm-app`（**必需**，§8 第 22 条）、
  `materal-update`、`omarchy-niri-apply-theme`、
  `omarchy-niri-repatch`、`omarchy-niri-system`、`omarchy-powerprofiles-{list,set}`、`vantage`（分辨率 TUI，若在别处也一并带）、
  `omarchy-picker-warmup`（登录后台预热 picker，配 `~/.config/systemd/user/omarchy-picker-warmup.service`，§8 第 25 条）。
- `~/.config/omarchy/`：`themes/`（含 tonal-spot 等自定义）、`plugins/`、`shell.json`、
  `extensions/omarchy-menu.jsonc`（用户级菜单 override，含 screensaver 屏蔽与 icon 转义修复）、hooks。
- `~/.config/systemd/user/materal-recolor.{path,service}` → 搬完 `systemctl --user daemon-reload && systemctl --user enable --now materal-recolor.path`。
- `~/.config/systemd/user/omarchy-picker-warmup.service`（+ `graphical-session.target.wants/` 软链；预热 picker，§8 第 25 条）、
  `omarchy-crash-watch.service`（同上软链；忘搬就少了崩溃诊断）。
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
- 自研锁屏 `split-lock/`：**已换装并实测通过**（§11.18–§11.20；`Super+Ctrl+L` 真锁→解锁）。niri shim 的 `dpmsStatus`/`solitaryBlockedBy` 已补（§11.17），explorer 插件已退役。
- niri 的 `hyprctl` shim 缺 `dpmsStatus` / `solitaryBlockedBy` → stock 锁屏的"锁住自救"会永远误判成已解锁，做锁屏前补。
- 浮栏弹窗避让（toast/托盘面板压栏 8px）。

### §11.16 自研锁屏 `split-lock/`：桥已跑通（2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.17 niri 上补 `dpmsStatus` / `solitaryBlockedBy`（2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.18 自研锁屏装成插件：`yvonne.split-lock`（2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.19 换锁**必须重启 shell**（keepLoaded 的 handler 竞争，2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.20 真机实测通过 + 退役 explorer（2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.21 打包决策：只给 `split-greeter` 做 PKGBUILD，且等迁移之后（2026-09-19）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.22 登录界面"第一次输密码没反应"的真因（2026-09-19，真机发现并修复）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.23 锁屏补上人脸（howdy）与头像（2026-09-20，用户指定）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.24 提示行换行 + 头像改成账户入口（2026-09-20，用户指定）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

### §11.25 tty1 登录被**永久**锁死：greetd 只有一格 `configuring`（2026-09-20，真机定位并修复）
> 已移入锁屏/登录专卷 → `docs/lock.md`（编号保留，供既有引用解析）。

---

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
