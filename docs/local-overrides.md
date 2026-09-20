# 本机改动总账（Omarchy on niri）

> 文档只有一份：本文件（`docs/local-overrides.md`）。`~/Documents/omarchy-niri-overrides.md` 是指向它的软链。
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

## 1. 仓库内（随 git 走：`~/omarchy-on-niri`）

| 路径 | 内容 | 生效方式 |
|---|---|---|
| `shell/` | 移植后的 Omarchy Quickshell 源码（层 1） | `install.sh` 把覆盖层 `git apply` 进 `$OMARCHY_PATH`（幂等），或手工 `~/bin/omarchy-niri-repatch` |
| `port-bin/*`（8 个） | `hyprctl`、`uwsm-app`、`materal-update`、`omarchy-niri-system`、`omarchy-niri-apply-theme`、`omarchy-niri-repatch`、`omarchy-powerprofiles-{list,set}` | `install.sh` 拷进 `~/bin`（PATH-first） |
| `niri-port/niri.patch` + `Niri.qml` + `plugins/blurwallpaper` | 覆盖层，挺过 `omarchy update` | `~/bin/omarchy-niri-repatch`（幂等） |
| `niri-port/plugin-patches/` | 4 个第三方插件的本地魔改补丁（+ README 说明怎么生成/怎么重放） | 手工 `git apply`（无自动重放器） |
| `scripts/check-doc-links.sh` | 校验 `~/Documents` 那九个软链仍指向 `docs/`（提交文档前跑） | `./scripts/check-doc-links.sh` |
| `scripts/kdl-sync.sh`、`scripts/local-files-sync.sh` | 机器 ↔ 仓库的对账：前者比 `niri-config/local/*.kdl`（家目录占位符），后者比 `local-config/` + `plugins/` + `split-lock/ir-light`（逐字节） | 各自直接跑；不在本机则 `skip` |
| `local-config/` | **本机 `~/.config` 覆盖层**（上游默认树 `config/` 之外那几份）：`ghostty/config`（含 `background-blur-radius = 0` 这条磨砂必需改动）、`ghostty/themes/dankcolors`、`systemd/user/materal-recolor.{path,service}` | 拷到 `~/.config/` 对应路径（见该目录 README）；`materal-recolor.path` 还要 `systemctl --user enable --now` |
| `plugins/jianlongliu.arch-logo/` | 自研 bar 插件的源码（`BarWidget.qml` + `arch-logo.svg` + `manifest.json`；无 `clonedFrom`，不是上游克隆） | 拷到 `~/.config/omarchy/plugins/jianlongliu.arch-logo/` |
| `split-lock/ir-light` | PAM 人脸栈点名的 IR 补光脚本（`pam_exec.so /usr/local/bin/ir-light`）的仓库副本 | `install -m 0755 split-lock/ir-light /usr/local/bin/ir-light`；**硬件专属，见 §5** |
| `niri-config/local/*.kdl`（7 份） | **本机在用的 niri 配置**（`config` + `input/monitor/layout/window-rules/effects/binds` 的模块化拆分） | 拷到 `~/.config/niri/`、把 `/home/<user>` 换成自己家目录、按自己显示器改 `monitor.kdl`，然后 `niri validate`；说明见 `niri-config/README.md` |
| `niri-config/omarchy.kdl.template` + `shell.json` 示例 | niri 侧接线 | `install.sh` 会渲染成 `~/.config/niri/omarchy.kdl` 并拷 `shell.json`（**仅当不存在**）；**本机没走这条** —— 用的是模块化拆分，`config.kdl` 直接 include `{input,monitor,layout,window-rules,effects,binds}.kdl`，`omarchy.kdl` 不存在 |
| `hooks/post-update.d/10-niri-repatch`、`hooks/theme-set.d/{10-niri-border,20-materal}` | 更新后重放覆盖层；换主题写边框渐变 | Omarchy 钩子机制自动调 |
| `split-greeter/`、`split-lock/` | 自研登录器与锁屏，各带 `install.sh` + `tests/` | `sudo ./install.sh`（split-greeter 不碰 `config.toml`，最后一步手工） |
| `default/omarchy/omarchy-menu.jsonc` | `install.package`/`install.aur`/`remove.package` 的 `xdg-terminal-exec` 回退 | 随仓库/覆盖层 |
| `docs/` | `INSTALL{,.zh}.md` + **主文档 `omarchy-on-niri-port.md`（当前事实 + 映射表）** + 模块卷 `visual/behavior/plugins/shims/upstream/migration/lock/local-overrides`（编号沿用原号），**正本就在 `docs/`**，`~/Documents/omarchy-niri-*.md` 是软链 | 改哪边都一样；跑 `scripts/check-doc-links.sh` 确认软链没被换成真副本 |

- 覆盖层实际内容：**21 文件 / 38 hunk**（`--reverse --check` 通过、repatch 幂等）；
  **md5 `047e5866a03228e30ae6069e9b2b9dd9`**，与 `~/.config/omarchy/niri-port/niri.patch` 一致（2026-09-20 核）。

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
| `shell.toml` | `[font] base-size 12`；`[bar]` 尺寸 + `background-alpha 0.45` + **`icon-font 12`**（要 `Style.qml` 的白名单，已进覆盖层）；`[popups]/[notifications]/[tooltip]` alpha；`[menu] background "#2a2a22"` + `background-alpha 0.7`（**写字面值就不再随主题走**） | `.bak-20260920-{consistency,iconfont,menu}` |
| `extensions/omarchy-menu.jsonc` | 菜单用户层 override：`trigger.*` 屏蔽、`setup.input` 指 `niri/input.kdl`、screensaver 6 条 `when:"false"`。⚠ 同一 id 别写两遍；**别写行内注释**（`stripJsonc` 只删整行注释） | `.bak-20260919-{prehide,prelearn}`、`.bak-20260920-prescreensaver` |
| `niri-port/` | `niri.patch`（与仓库同 md5）、`Niri.qml`、`plugin-patches/*.patch`（4 个，机器独有，见 §6） | 各自的 `.bak-*` |
| `plugins/`（8 个） | 自研：`jianlongliu.arch-logo`（**源码已进仓库 `plugins/jianlongliu.arch-logo/`**）、`jianlongliu.workspaces`（上游克隆 + `niri-port/plugin-patches/jianlongliu.workspaces.patch`）、`jianlongliu.split-lock`（**正本 `split-lock/`**）（**没有 `.git`**，`omarchy plugin update` 不碰）；第三方：`charlieras262.floating-bar`、`ronald.input-sources`、`meviusisback.ai-subs`、`jrmmhm.pocket`、`io.github.claudsondouglas.arcdock`（**本身就是上游 git 克隆**，本地魔改用 `git diff` 就地生成 patch） | `plugin-patches/*.patch` 反向 `git apply -R` |
| `hooks/` | 与仓库同（`post-update.d/10-niri-repatch` 的 `omarchy-restart-shell` 那 8 行 2026-09-20 已并回仓库，两侧 md5 `b077156959bc9cfb4c37941a4ffb3a5e` 一致） | 从仓库重拷 |

---

## 4. niri 配置（`~/.config/niri/`）

- 文件：`config.kdl`（只留 include 与会话级设置）、`binds.kdl`、`layout.kdl`、`window-rules.kdl`、
  `effects.kdl`、`input.kdl`、`monitor.kdl`；每个旁边都有 `.bak-*`（改前必留）。
  **2026-09-20 已收进仓库**：`niri-config/local/`（家目录参数化成 `/home/<user>`，说明见该目录 README）。
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

- 换主题/壁纸后同步到登录页：`sudo split-greeter-sync "$USER"`（还有实验账户时要一起列）。
- 登录页切换是唯一会把自己锁在外面的步骤，所以 `split-greeter/install.sh` **故意不碰 `config.toml`**。

---

## 6. 用户级 systemd 单元

| 单元 | 说明 | 仓库里有? |
|---|---|---|
| `omarchy-crash-watch.service` | 本机版：`ExecStart` 指 `~/.local/share/omarchy/bin/omarchy-crash-watch`，并显式给 `PATH`/`OMARCHY_PATH`（用户管理器环境里没有这两样） | ✅ `default/systemd/user/`（模板指 `/usr/bin/…`，本机包不存在） |
| `omarchy-picker-warmup.service` | `PICKER_WARMUP_DELAY=45` + `ExecStartPre=/bin/sleep`；`toggles/picker-warmup-off` 存在即跳过 | ✅ `default/systemd/user/`（`%h` 模板，2026-09-20 收进；`install.sh` 第 4 步装并链接） |
| `materal-recolor.{path,service}` | **是本移植的一部分**（不是无关物件）：`.path` 盯 Omarchy 壁纸文件，一变就拉起 oneshot `.service` 跑 `%h/bin/materal-update`（`port-bin/` 里的 matugen 包装，机制见主文档 §8.10）。上游没有、也没有包认领 | ✅ `local-config/systemd/user/`（2026-09-20 收进；装法 `systemctl --user enable --now materal-recolor.path`） |
| `wechat-clipboard-sync`、`wl-clip-persist`、`wl-gammarelay`、`xsettingsd` | 与本移植无关（第一个是私人物件，后三个是通用 Wayland 守护进程；四者都无包认领），仅共存 | — |

- 两个 omarchy 单元都软链进 `graphical-session.target.wants/`。

---

## 7. 状态、工作区与 patch 重生成

- `~/.local/state/omarchy/toggles/screensaver-off` = **screensaver 禁用 flag**（用户明确要关，别恢复）。
- `~/.local/share/omarchy` = `$OMARCHY_PATH`，**工作区里有非移植改动**（2026-09-20 核：`git status` 265 条，
  主要是主题删除）→ **重生成 `niri.patch` 必须限路径**，否则 21 文件会膨胀成 250+：

```bash
# 旧 patch 的文件清单 + 本次新增的文件
git diff -- $(grep '^diff --git' niri.patch | sed 's|.* b/||') <新增文件> > niri.patch
git apply --reverse --check niri.patch   # 必须通过
~/bin/omarchy-niri-repatch               # 应回 "already applied"
```

- `~/Documents/omarchy-niri-*.md`（九个）= **指向仓库 `docs/` 的软链**（2026-09-20 文档归一，取消"母本 + 镜像"双写）。
  改哪边都一样；被人换成真副本、或指错地方，`./scripts/check-doc-links.sh` 会报红。归一前的真副本备份在
  `~/Documents/archive/doc-backups/pre-merge-20260920-232818/`（九个文件，逐字节等于当时的仓库版）。
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
   说明怎么 `git diff` 生成、怎么 `git apply` 重放）；机器上同目录的 `.bak-*` 是历史，仍只在本地。
4. `~/.config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}` 的实际取值
   （仓库只有 `niri-config/shell.json` 示例）。**这是 `~/.config` 层最后一个缺口**（2026-09-20 复核）：
   三份加起来 16 K、已扫过**不含任何密钥**（无 token / 无 `.hermes`/`.env` 引用 / 无邮箱、URL 凭据），
   收不收只取决于"要不要公开本机偏好"。收法是照 `local-config/` 的样子放进
   `local-config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}`，`local-files-sync.sh` 会自动认。
5. ~~钩子漂移~~ **已修（2026-09-20）**：本机那份多出的 8 行（更新后 `omarchy-restart-shell` ——
   上游 `omarchy-update-restart` 只给"重启"选项，而 QML 换了不重启等于旧部件继续跑、菜单 jsonc 写到一半
   还会解析成空菜单）已并回仓库，两侧一致。
6. `/etc/pam.d/omarchy-lock-face`、`/etc/greetd/*` 是 `split-*/install.sh` 装的（脚本在仓库），
   但**已装好的机器状态**没有版本记录。
7. ~~本机 niri 配置（`~/.config/niri/` 七份 kdl，约 910 行）~~ **已收进仓库（2026-09-20）**：
   `niri-config/local/`（家目录参数化为 `/home/<user>`，`monitor.kdl` 的 modeline 标了「本机面板专属」）。
   此前仓库只有 `niri-config/omarchy.kdl.template`，而本机**没用**那条路 —— 别人照仓库装会缺合成器侧一整块。
8. ~~本机 ghostty 配置~~ **已收进仓库（2026-09-20）**：`local-config/ghostty/config` +
   `local-config/ghostty/themes/dankcolors`。此前仓库里的 `config/ghostty/config` 是**上游默认**（与
   `~/.local/share/omarchy/config/ghostty/config` 逐字节相同），于是**磨砂五处里"ghostty"那一处整个缺失** ——
   别人照仓库装得到的是"有窗口装饰、无磨砂"，正是本移植当初修掉的症状。`theme = dankcolors` 指着那份
   454 B 的静态主题文件（DMS 时代遗留，仓库与上游都搜不到生成器），不一起收 ghostty 会因未知主题起不来。
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

---

## 9. 一句话回退索引

| 想撤销 | 命令 |
|---|---|
| 某个 `~/bin` 垫片 | `rm ~/bin/<名字>` |
| 覆盖层（回到上游 omarchy） | 在 `$OMARCHY_PATH` 里 `git apply -R ~/.config/omarchy/niri-port/niri.patch`（`omarchy-niri-repatch` **没有**反向开关，反向只能手动 `git apply -R`） |
| 用户级 shell 配置 | 用同目录 `.bak-*` 覆盖回去（热生效，存盘即回） |
| 登录页 | 恢复 `/etc/greetd/config.toml.backup-*`，再 `systemctl restart greetd`（**在 TTY 里做**） |
| 锁屏人脸 | `sudo split-lock/face-pam.sh --remove` |
| screensaver 恢复 | 删 `~/.local/state/omarchy/toggles/screensaver-off` + 复原 `omarchy-menu.jsonc.bak-20260920-prescreensaver` |
| 选择器预热 | `touch ~/.local/state/omarchy/toggles/picker-warmup-off`（或 `systemctl --user disable --now omarchy-picker-warmup`） |
| 插件本地魔改 | 在该插件目录 `git apply -R ~/.config/omarchy/niri-port/plugin-patches/<id>.patch` |
