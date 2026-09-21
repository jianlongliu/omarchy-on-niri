# 锁屏与登录 — Omarchy on niri 卷 II

> 文档只有一份：本文件（`docs/lock.md`）。
> 本卷 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽出：**章节编号沿用原号**（`§8.18`、`§11.10–§11.14`、`§11.16–§11.25`），
> 原处留有同名指针，所以 `docs/INSTALL.md`、`split-greeter/README.md`、`split-lock/` 里既有的
> "§11.13"、"§8.18" 之类引用继续解析得到。
> 覆盖范围：登录界面（Split Greeter）、锁屏（`split-lock`）、PAM 门禁、人脸（howdy）与头像、greetd 的
> 单格 `configuring` 陷阱。

## 本卷目录

- 8.18 锁屏"不能锁"：PAM 门禁（手工部署漏了安装器步骤）（2026-09-19）
- 11.10 锁屏插件 `io.github.sirjul1337.lock-explorer`（能力边界与搬运）
- 11.11 登录界面：自研 Quickshell greeter「Split Greeter」（Split 设计，多账户 + 人脸）
- 11.12 登录界面：一条卡住的 PAM 对话 = 密码"没反应"（2026-09-19 真机实测与修法）
- 11.13 密码"按回车没反应"的真正原因：宿主少接了一条设计信号（2026-09-19 二次实测）
- 11.14 人脸改成"回车触发"（2026-09-19，用户指定）
- §11.22 登录界面"第一次输密码没反应"的真因（2026-09-19，真机发现并修复）
- §11.16 自研锁屏 `split-lock/`：桥已跑通（2026-09-19）
- §11.17 niri 上补 `dpmsStatus` / `solitaryBlockedBy`（2026-09-19）
- §11.18 自研锁屏装成插件：`jianlongliu.split-lock`（2026-09-19）
- §11.19 换锁**必须重启 shell**（keepLoaded 的 handler 竞争，2026-09-19）
- §11.20 真机实测通过 + 退役 explorer（2026-09-19）
- §11.21 打包决策：只给 `split-greeter` 做 PKGBUILD，且等迁移之后（2026-09-19）
- §11.23 锁屏补上人脸（howdy）与头像（2026-09-20，用户指定）
- §11.24 提示行换行 + 头像改成账户入口（2026-09-20，用户指定）
- §11.25 tty1 登录被**永久**锁死：greetd 只有一格 `configuring`（2026-09-20，真机定位并修复）

## 另见（锁屏相关的东西分住哪几处）

- 本卷卷末「附：两条锁屏路线并存与收敛」＝原文 `§8 第 6 条`（2026-09-20 已抽入本卷）
- `docs/behavior.md` `§8 第 23 条`：screensaver 关掉并屏蔽（`idle.screensaver` 与锁屏计时的抢跑关系）
- `docs/behavior.md` `§8 第 24 条`：按键表去重，锁屏统一为 `Mod+L`
- 主文档 `§9 验证清单`：锁屏/登录相关的验收步骤


---

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
  **没有** `spawn-at-startup quickshell`），不加载我们的壳层；`/etc/greetd/config.toml` 是主账户
  的 0600 文件（读不到，也没碰）。
- 时序也对不上：`passwordPam:false` 在**发起锁屏之前**就成立，装插件前即如此。

**迁移/重装注意**：同一台机器上**换账户不需要重跑**（`/etc/pam.d/<服务名>` 是全机共享的，
`pam_unix` 认的是锁屏界面里输入的用户名）；但**换机器或重装必须重跑**——它是安装器步骤，
`install.sh` 现在会检测缺失并打印命令（见 §7 步骤 1b）。

**旁证：`niri --session` 那堆进程不是第二个会话**。`ps` 里成排的 `niri --session`（comm
`Command Spawner`、0 CPU、1 个 pipe fd、子进程 `<defunct>`）是 niri 自己 `spawn` 命令时的派生辅助进程，
与 greeter、与我们的移植都无关。

---


---

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


---

### 11.11 登录界面：自研 Quickshell greeter「Split Greeter」（Split 设计，多账户 + 人脸）

§11.10 的三条路里选了"自研"：**直接复用锁屏插件的 Split 设计当 DM**，既不依赖 dms-shell，也不依赖会话内 shell。代码在仓库 `split-greeter/`（本机 `~/Projects/omarchy-on-niri/greeter/`，**只在本地提交，未推远端**）。顺带确认：`greetd-dms-greeter-bin` 只依赖 `greetd quickshell qt6-declarative`，**不依赖 dms-shell**，与 DMS 的唯一耦合是 `dms-greeter sync` 把 DMS 主题/壁纸拷进 `/var/cache/dms-greeter`（0750 `greeter:greeter`，普通用户读不到）。

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

**`ir-light` 是这套里唯一没有替代品的本机脚本**（仓库副本 `split-lock/ir-light`，2026-09-20 收进）：它只做一件事
——`open("/dev/video2")` 后发一个 UVC 扩展单元 ioctl（`unit=13 selector=14`，就是"模式 2 + 亮度 100"）点亮
ThinkPad X1 Carbon Gen9 那块 Chicony 04f2:b6ea 的 IR 灯。没有它，`howdy` 在暗光下认不出人；因此它在
`/etc/pam.d/{greetd,omarchy-lock-face}` 里都是 `pam_exec.so … optional` —— **灯没点亮或脚本缺失都不会把人锁在外面**，
只是退回输密码。换机器要改两处：设备节点（`/dev/video2` 未必是那个摄像头，用 `v4l2-ctl --list-devices` 认）和
单元/选择器号（`uvcvideo` 的扩展单元随固件而异）。`split-lock/face-pam.sh` 只**检查**这个文件在不在、不负责安装它。

**装与回滚**——切 greetd 的 `[default_session].command` 是唯一能把人锁在门外的一步，脚本**不碰** `/etc/greetd/config.toml`：

1. `sudo ./install.sh`：拷到 `/etc/greetd/split-greeter`（世界可读，greeter 用户要读）+ `/usr/local/bin/split-greeter{,-sync}`；建 `/var/lib/greeter/{users,.config/omarchy,.local/state/split-greeter}`（属 `greeter`）。
2. `sudo split-greeter-sync`：同步**全部真实账户**的配色与壁纸（给共享缺省，没自己主题的账户走软链）。建议挂到已有的更新钩子后面，主题一换登录界面就跟着换。
3. 先开着 TTY（Ctrl+Alt+F2）→ 把 `[default_session]` 改成 `command = "/usr/local/bin/split-greeter"`、`user = "greeter"` → 登出实测 → 起不来就在 TTY 改回原值（dms-greeter 留的备份在 `/etc/greetd/config.toml.backup-*`）。
4. **实测能进之后**，才谈 `sudo pacman -D --asexplicit quickshell` 与卸 `greetd-dms-greeter-bin`（§11.1：不先 asexplict，`-Rns` 会顺手带走 quickshell，本 greeter 和 Omarchy shell 一起瘫）。

**2026-09-19 装机状态（`pkexec` 已执行）**：`/etc/greetd/split-greeter`（root:root，文件世界可读）+ `/usr/local/bin/split-greeter{,-sync}` 已就位；`split-greeter-sync` 已跑过一遍（实验账户 = `tonal-spot` 主题 + 当前壁纸；主账户因为**还没迁移**、`~/.local/state/omarchy/current` 根本不存在 → 该账户目前软链到共享缺省）。**`/etc/greetd/config.toml` 的改动是用户自己做的**：15:09 他把 `[default_session].command` 切成 `/usr/local/bin/split-greeter`（备份 `/etc/greetd/config.toml.split-greeter-backup`，168B = 旧的 dms 命令），15:15 登出后 tty1 起的就是本 greeter。装机校验实测：greeter 身份下 `/etc/greetd/split-greeter` 下**所有文件可读**、桥可执行、状态目录可写；`niri validate -c /etc/greetd/split-greeter/niri.kdl` 通过；壁纸 sha256 与源文件一致。

**注意**：`greeter` 账户的 passwd home 是 **`/`**（`greeter:x:964:964:...:/:/bin/bash`），所以 `niri.kdl` 里那行 `HOME "/var/lib/greeter"` 是**关键行**，缺了它主题/状态目录全找不到。

**不登出也能验收**（都在会话里跑，用 `bridge/mock-greetd.py` 假装 greetd）：

- `python3 split-greeter/bridge/test-bridge.py` —— **24 项协议断言全过**：错密码、成功、失败后重试、交互式 secret、人脸命中、人脸未命中转密码、未知用户、epoch 回显、cancel、socket 不可用（不崩）。
- `split-greeter/tests/smoke.sh` —— 7 场景**全过**（人脸命中直通 / 人脸未命中回落密码 / 错密码**不产生**会话 / 切账户后登录 /
  **回车触发扫脸**（先断言"没按回车绝不扫脸"再按回车）/ 真按键注入的输密码 / 真按键注入的切账户），断言「greetd 是否收到 `start_session`」+「greeter 是否干净退出」+「无 QML 报错」。（前 4 个用例显式带 `GREETER_AUTOBEGIN=1` 复现旧行为，后 3 个走新的默认路径。）加 `GREETER=/etc/greetd/split-greeter` 就是**验装好的那份**（含它自己 `bridge/` 下的桥）——实测也是 4/4，并真拿到了 `start_session`。
- 视觉证据：Split 正常渲染（左壁纸 + 时钟、右半透明面板、错误态红框、选择器头像/首字母）；**壁纸跟账户**（实测背景均值 `2.5 → 195.5`）；**配色跟账户**（切到测试账户后 `Color.background` 由 `#111318` 变 `#7f0000`，来源 `users/<dev-user>/theme`）。
- 单跑一次（要截界面时）：`--delay` 调大，再用 `GREETER_SELFTEST_OPEN_PICKER=1` / `GREETER_SELFTEST_PICK=<user>` 驱动；`SelfTest.qml` 只在 `GREETER_SELFTEST_PASSWORD` 非空时经 `Loader` 加载，生产路径不经过它。

**边界**：单输出（只配 `eDP-1`）；指纹 / FIDO2 没有专门 UI，作为 PAM 消息出现；`start_session` 固定 `niri-session`（`GREETER_SESSION` 可改），没有会话选择器；字体/间距不随账户切换；**不动 Plymouth / 启动链**（§11.10 的结论）。vendored 的 `designs/ Commons/ Ui/` 由 `split-greeter/vendor.py` 按组件闭包重拷并重放 4 处补丁（`Color.qml` 的 `themeOverride`、`DesignBase.qml` 的 `loginUser`/`hintOverride`、`Split.qml` 的提示行、`Style.qml` 的 `cornerRadius`），插件或 Omarchy 升级后重跑一次即可。


---

### 11.12 登录界面：一条卡住的 PAM 对话 = 密码"没反应"（2026-09-19 真机实测与修法）

> **修正（2026-09-19 15:5x）**：本节说的"卡住的 PAM 对话"**真实存在**，超时换 helper 的修法保留；但它不是
> "输密码 + 回车毫无反应"的**主因**——主因是宿主少接了一条设计信号，见 **§11.13**。诊断教训：字段
> `activeFocus/enabled/readOnly` 全正常，也不能说明回车能提交。

**现象**：切到自研 greeter 后**登不进去**——输密码毫无反应、连错误都不报；同机 TTY2 用文本登录能进
实验账户（1001，有密码），**主账户的文本登录却失败**（那个账户实际靠 howdy 进）。

**根因**：greeter 一启动就对**默认账户主账户** 发起不带密码的 `create_session` → PAM 进
`howdy`（sufficient）→ 人脸没命中/相机没就绪时 howdy **永远不返回**；而 **greetd 一条连接上同时只允许
一个会话** → 之后所有请求（包括"切到实验账户再输密码"）全排在门外 → 界面既不动也不报错。epoch 守卫只
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


---

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
`password field received input` → `password submitted for 主账户 (7 chars)` → `auth_ok` → `started`
→ mock 收到 `start_session ["niri-session"]`；切账户：`Tab` → `↓↓↓` → `Return` →
`the account picker chose 实验账户` → `account switched to 实验账户 from 主账户` → 输密码 → `auth_ok`。

**测试为什么没拦住（核心教训）**：`SelfTest.qml` 之前直接调 `design.submitPassword(pw)`（宿主公开 API）和
`picker.picked(name)`，**恰好跳过了出问题的两段宿主接线**。已改成走**设计自己的路径**：
`design.passwordTextEdited(pw)` + `design.inputItem.accepted()`。另加两个**真实按键**用例（`wtype`）：
`typed-password` / `typed-switch` → `tests/smoke.sh` 现 6 用例、`tests/state.sh` 6 场景，全 `FAILURES: 0`。
**规则：自检要驱动"设计发什么信号"，不要驱动"宿主提供什么函数"。**

**诊断开关**：`GREETER_DEBUG_FOCUS=1` 每秒打印输入框状态（`enabled/readOnly/visible/activeFocus/尺寸`、文本
**长度**、`pickerOpen/pickerFocus`）。今天正是靠它把"字段看着正常但回车无效"定位到宿主接线；只打长度不打内容，
日志里不会出现密码。

**⚠️ 现存副作用（待定）**：greeter 一启动就对默认账户自动发起 howdy 尝试。15:5x 我 `pkill -u greeter` 让
greetd 重拉 greeter 时，新实例的脸扫**命中**了 → greetd 立刻又开了一个 **主账户的 niri 会话**（VT1）。
**2026-09-19 已改：人脸改成"回车触发"，不再开机就扫（§11.14）。** 启动时**一次认证都不发起**，
`LockInput.onAccepted` 在空输入上回车 = `faceRequested` → 开扫（这是设计原本的语义）；**直接打字就是纯密码**
（`authenticate()` 空闲时会自己开一个带密码的会话）。代价是失去"人脸优先"——走过来的瞬间不再自动登录，
但也因此修掉了"人从镜头前走过就被登进去"以及"自动扫脸掩盖了密码路径到底通不通"。
需要时 `GREETER_AUTOBEGIN=1` 恢复旧行为（只有测试用得上）。


---

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


---

### §11.22 登录界面"第一次输密码没反应"的真因（2026-09-19，真机发现并修复）

**现象**（用户真机）：第一次输密码回车没反应、界面又要求输一次，第二次照做才进去。

**真因不在 UI 接线**（不是 §11.13 那类），而在 **greetd 协议本身**：

- `create_session` **没有密码字段**。桥原来把密码塞进 `create_session` 的 `password` 里发出去 —— 真实 greetd 忽略未知字段，**这个秘密根本没送到 PAM**。
- 于是 PAM 照常跑（本机 `/etc/pam.d/greetd`：`ir-light` → howdy `sufficient` → `system-local-login`），howdy 报 `No face model known`，`pam_unix` 才问 `Password:` —— 而此刻输入框已被清空，人只好再输一次。第二次走的是"回答当前提示"那条路（`awaitingSecret` = true），所以能进去。
- `Greetd.qml` 里本该兜住这件事的 `queuedPassword`（提示还没来就先打好的密码，等提示来了再交）**从来没被赋过值**，一直是死代码 —— 洞因此一直开着。

**修法**：① 桥不再把密码放进 `create_session`（秘密只作为"对提示的回答"传递）；② `queuedPassword` 真正落地 —— 凡是在"没有待答提示"时发出密码（直接登录、或人脸扫到一半改输密码后重连），都先入队，等 `auth_message(secret)` 一到就用它回答；`auth_ok`/`auth_fail`/切账户时清空（不会自动重试错密码）。

**测试为什么没抓到**：mock 的 `create_session` **认**那个 `password` 字段（真实 greetd 不认）—— 宽容的夹具让"密码压根没发出去"在测试里看起来完全正常。现在 mock 与 greetd 同样忽略它，并新增用例 `typed-before-prompt`（`--howdy-fail` + 立刻提交密码），**先红后绿**：修之前它卡到整例超时（`exit=124`），修完全套 8 例 `FAILURES: 0`。

**真机复测（2026-09-19，用户）**：修完并装到 `/etc/greetd/split-greeter` 后注销重登，**一次输密码直接进** —— 通过。

**教训**：夹具必须和真东西一样严格。"测试绿 + 真机不工作"这种组合，八成是夹具比现实宽松（§11.13 是同一个病的另一个症状：当时自测直接调 `submitPassword()`，跳过了真正的接线）。


---

### §11.16 自研锁屏 `split-lock/`：桥已跑通（2026-09-19）

**结论：`LockView.qml` 就是全部适配层，已验证；尚未换装到活会话。**

stock 的锁 Service 用**文件名**实例化 `LockView { ... }`（`reference/Service.qml` 约 304-323 行），而 Split / `DesignBase` 的属性和信号与 stock 视图**同名同形**（`submitPassword` / `clearFailureRequested`）——所以把自己的包装命名为 `LockView.qml` 本身就是适配，不需要重构，也不需要第二个视图。

**离线契约测试**：`cd split-lock && ./tests/state.sh` —— 现 15 项（原 8 项 + §11.23 的人脸/头像 7 项），三轮稳定、全程 offscreen（不碰活会话、不锁屏）。它拼一个一次性 qs 工程（`Commons`/`Ui` 软链 + 平铺的 `.qml`），跑一个照抄 Service 绑定的 mock host，双向断言：视图能实例化、host→view 推送、view→host 的 `passwordTextEdited` / `submitPassword` / 失败回传 / 清除，`clearFailureRequested` 能出去，以及人脸/头像那几条。qs 日志留在 `/tmp/split-lock-state.log`。

**两个踩过的坑（都已写进代码注释）**：

1. **目录导入不可靠**：视图里写 `import "designs"` 时，只要它是被当作"类型"加载的（而不是配置的根文件），`Split` 就解析失败。改成把设计文件**平铺**到 `LockView.qml` 同级 —— 同目录类型隐式解析 —— 这类失败整片消失。
2. **offscreen 下不能出现 `PanelWindow`**：layer-shell 窗口需要真实后端，mock host 用它就报 `No PanelWindow backend loaded`；换成 `Rectangle` 容器后干净通过（被测的是属性/信号接线，与父容器是谁无关）。

**`displaysBlank` / `powerSaverActive` 为什么可以不管**：Service 会传这两个（`Service.qml:34-48` 定义，与 `backgroundVersion` 一起在 310 附近传入视图），而 `DesignBase` 没有对应属性，不声明 Quickshell 会直接拒绝创建视图。stock 视图只为**一件事**用它们——暂停壁纸播放（`reference/LockView.qml:94`）；本设计的 `Wallpaper` 是静态 `Image`（`Wallpaper.qml:22`），**没有动画可暂停**。真正有用的是 `loadBackground` / `backgroundVersion`（缓存击穿的 `fileUrl`），设计里已经尊重（`Wallpaper.qml:25`）。

**还没做（换装前必须）**：① niri 的 `hyprctl` shim 补 `dpmsStatus` / `solitaryBlockedBy`，否则 stock 锁屏的"锁住自救"会永远误判成已解锁；② 先留好退路再让插件上位；③ 锁屏/解锁/打错密码由**用户自己**按一次，不主动锁他的屏。


---

### §11.17 niri 上补 `dpmsStatus` / `solitaryBlockedBy`（2026-09-19）

Omarchy 的锁层从 `hyprctl -j monitors` 读两个字段，shim 之前都在瞎答：

- `dpmsStatus` **硬编码 `False`** → stock 锁的 `screenBlank()` 永远说"已黑屏" → 锁屏界面的壁纸播放被永久暂停。niri 的 IPC **不暴露**电源状态（已核对：`niri msg outputs` 的字段里没有），所以改成**在关屏发生的地方记账**：`omarchy-brightness-display` 的开/关都走 `hl.dsp.dpms` 派发，都会经过 shim。niri 自己的 `Mod+Shift+P` 绕开我们，但 niri 在**任何输入**时都会把显示器点亮（binds 注释原文），而唤醒路径发生在输入之后，所以"陈旧的 on"活不过造成它的那次输入。未知状态报 **on** —— 这是不会跳过必要 enable 的方向。
- `solitaryBlockedBy` **缺失** → `omarchy-hyprland-session-locked`（锁服务在轮询它、`omarchy-restart-shell` 在拿它把关）永远报"未锁"。Hyprland 用 `LOCK` 表示存在 ext-session-lock；niri 没有这个概念，但**维护 logind 的 `LockedHint`**（niri 二进制里就有），于是从那里翻译：锁定 → `["LOCK"]`，未锁 → `[]`，问不到 → `["WORKSPACE"]`（正是那个脚本自己对"无法判断"的写法，退出码 2）。

回归测试 `port-bin/tests/test-hyprctl-shim.sh`：**假 niri + 假 loginctl**，完全不碰真实会话/显示器/logind，12 项，含消费者脚本的 0/1/2 退出码。

证据边界：未锁分支已在活会话上验证（`dpmsStatus: true`、`solitaryBlockedBy: []`、退出码 1）；**锁定分支（`LockedHint=yes`）要等用户自己锁一次才算证实**。


---

### §11.18 自研锁屏装成插件：`jianlongliu.split-lock`（2026-09-19）

**形态**：不魔改 omarchy 的任何文件，而是把锁做成 `~/.config/omarchy/plugins/jianlongliu.split-lock/`，manifest 里声明 `"omarchy": {"clonedFrom": "omarchy.lock"}`（与第三方 explorer 插件同款机制）。锁是 `service` 类插件，shell **按文件名**从插件自己的目录实例化 `LockView { }` —— 所以插件目录里放 `Service.qml`（上游锁服务 + 我们的人脸/头像增量，每个块都标 `PORT (split-lock)`；§11.23 起**不再是逐字节副本**）+ 我们的 `LockView.qml` + 平铺的 Split 设计文件，**这就是全部改动**。stock 插件目录本来也只有三个文件（`manifest.json`/`Service.qml`/`LockView.qml`），换掉 `LockView` 就等于换锁。`install.sh` 现在拿**两个** md5 把关：`UPSTREAM_SERVICE_MD5`（上游漂移检测，上游一改就提醒把我们的增量重新落一遍）与 `EXPECTED_SERVICE_MD5`（我们自己那份，防手滑改坏）。

**装法**（`split-lock/install.sh`）：

- `./install.sh --stage`：装好但**禁用** —— 当前锁屏不变，explorer 继续在用；
- 启用：`omarchy plugin disable io.github.sirjul1337.lock-explorer` + `omarchy plugin enable jianlongliu.split-lock`；
- 回滚 = 删掉那一个目录（`rm -rf ~/.config/omarchy/plugins/jianlongliu.split-lock`）再把 explorer 启回来；
- `omarchy plugin validate` 通过（它是**静默成功型**，只有 rc≠0 才说话）。

**互斥**：锁是单例 —— `PluginRegistry.activeCloneFor()` 挑的是**第一个** entry 找得到的克隆，两个克隆并存等于掷骰子，所以必须"先禁 explorer 再启 split-lock"。

**退路（已核实存在）**：锁的 IPC 只有 `lock` / `isLocked` / `status` / `preview` / `hidePreview` —— **没有 `unlock`**；`omarchy-restart-shell` 在锁定时会**拒绝重启**（这是刻意设计）。真正的退路是 ext-session-lock 的协议本意：**杀掉锁客户端就等于放锁** —— 切 VT（Ctrl+Alt+F2..F6）登录，`systemctl --user restart omarchy-shell`。

**证据边界**：离线契约测试（15 项具名断言）证明的是**属性/信号接线**；`Service.qml` 在真实会话里跑起来（PAM、锁面、真实按键）要等**用户自己锁一次**才算证实。PAM 前提 `/etc/pam.d/omarchy-lock-password` 已在（否则 `lock()` 直接返回 `missing-pam`）。


---

### §11.19 换锁**必须重启 shell**（keepLoaded 的 handler 竞争，2026-09-19）

实测：把 explorer 禁用、把 `jianlongliu.split-lock` 启用之后，**活着的锁仍然是 explorer 的**。两层原因：

1. `service` 类插件是 `keepLoaded: true` —— 禁用/启用只改配置，**不会卸载已在跑的实例**；
2. 每个锁 Service 都注册 `IpcHandler { target: "lock" }`，Quickshell 只让**先到的那个**生效；后到的会打印 `Handler was registered but will not be used because another handler is registered for target lock`（行里带完整文件路径）。**赢家什么都不打印** —— 所以"新实例日志里没有 `target lock` 落选行 + `omarchy-shell lock isLocked` 能应答"就是"我们的 handler 赢了"的正向证据。

因此换锁流程必须包含 `omarchy-restart-shell`（`install.sh` 结尾已按"必做一步"写）。

顺手得到的一条无痛验证法：`omarchy-shell lock preview` 会把 `LockView` 以 `inputEnabled: false` 挂成 Overlay 显示（点一下就关）——**不用锁屏**就能确认视图建得起来、渲染对不对。2026-09-19 截图确认：壁纸、时钟、头像圆牌、密码框、`Press Enter to log in` 都在。


---

### §11.20 真机实测通过 + 退役 explorer（2026-09-19）

用户实按 `Super+Ctrl+L`（`Mod+Ctrl+L` → `omarchy-system-lock` → `omarchy-shell lock lock`）：**没问题**。Service 的 `logEvent` 把事件打到 qs 日志，这次完整流程是：

```
09:10:38 lock-requested → lock-pending: screen-stabilizing → 09:10:39 secure=true → 09:10:43 unlocked
```

真锁 → 真 PAM 密码 → 解锁，4 秒。随后 `io.github.sirjul1337.lock-explorer` **已移除**（先 `tar czf /var/tmp/lock-explorer-backup-20260919.tar.gz` 留底；设计代码与署名在本仓库 `split-lock/` + `THIRD-PARTY.md`，原插件随时可 `omarchy plugin add` 装回）。现在系统中唯一的锁提供者是 `jianlongliu.split-lock`。

**遗留（2026-09-19 已解决）**：`binds.kdl:21` 那行 niri 默认的 `Super+Alt+L { spawn "swaylock"; }`（swaylock **根本没装**，键是死的）已随按键去重**注释移除**；锁屏现在只有一条路：`Mod+L` → `omarchy-system-lock`（§8 第 24 条）。


---

### §11.21 打包决策：只给 `split-greeter` 做 PKGBUILD，且等迁移之后（2026-09-19）

- **要**：`split-greeter` = `/etc/greetd/split-greeter` + `split-greeter{, -sync}` 二进制 + `greeter` 用户/目录 + pkexec 助手 → 正是 pacman 的对象（卸载干净、依赖声明、升级有版本）。落地要点：二进制装 **`/usr/bin` 而不是 `/usr/local`**（`/usr/local` 不归包）；`depends=(quickshell greetd)`、`optdepends=(howdy)`；`build()` 里跑 `vendor.py`；`install.sh` 里建用户/建目录那部分搬进 `.install`；**仍然不碰** `/etc/greetd/config.toml`。
- **不要**：`split-lock`（它在 `~/.config/omarchy/plugins/`，用户级；它自己的包管理器就是 `omarchy plugin`）；port 本身（patch + 每用户配置层，家目录文件不归 pacman —— 迁移方式本来就是整目录 cp）。
- **顺序**：等迁到主账户、`install.sh` 那条路径稳定之后再做，否则要同时维护两条装法。
- 动机案例：卸 DMS 时 `-Rs` 差点把 quickshell 一起删 —— "文件归属不清"正是 pacman 要解决的问题。


---

### §11.23 锁屏补上人脸（howdy）与头像（2026-09-20，用户指定）

**用户原话**：「锁屏加上 howdy 和用户头像」。两条缺口在早期勘察里就写明了：`/etc/pam.d/omarchy-lock-password` 里没有 howdy 行；插件 `DesignBase.qml` 的 `faceConfigured` 写死 `false`、`avatarUrl` 没人喂（不读 accountsservice）。

**人脸 = 回车触发，不是自动扫脸。** 本机实测单次 howdy **5~7 秒**：每次都要重新加载 38MB 的 SFace ONNX 模型（命中约 5s；未命中约 7s，`timeout=3` 之后 `compare.py` exit 11）。连续重试 = 相机 + 一个 python 进程常开，而且"人从镜头前走过就解锁"—— 用户 2026-09-19 已在 greeter 上定过同一条规则（§11.14），这里照办。

**人脸走独立 PAM 服务，不塞进密码栈。** `/etc/pam.d/omarchy-lock-face` = `ir-light`(optional) → `pam_python.so /lib/security/howdy/pam.py`(required) → `account include system-local-login`，模块顺序照抄 `/etc/pam.d/greetd`（`ir-light` 点亮 IR 灯，防"image too dark"）。理由：howdy 在相机被占/没模型时**没有客户端超时**，塞进 `omarchy-lock-password` 就可能连"打密码"这条唯一后路一起拖住（§11.12 正是这个病）。独立服务失败只损失人脸路径。

- 生成器：`split-lock/face-pam.sh`（`sudo ./face-pam.sh`；`--remove` 回滚；`--dry-run` 预览）。**不碰** `omarchy-apply-lock`（上游脚本，`omarchy update` 会覆盖）——它只重写 password/fingerprint 两个文件，不会动我们这个。
- `install.sh` 只**报告**它在不在：不在就 `faceConfigured` 探针为 false、人脸入口自己藏起来，锁照常能用（装了 howdy 但没 enroll 的机器也一样）。
- 探针（Service.qml 里一句 `bash -c`）：PAM 文件 + `/lib/security/howdy/pam.py` + **本账户的模型** `/lib/security/howdy/models/$USER.dat` 三样齐才 `faceConfigured=true`。⚠ howdy 的模型与 `config.ini` 都在 **`/usr/lib/security/howdy/`**（`compare.py` 用 `dirname(__file__)` 定位）；`/etc/howdy/config.ini` 是一份陈旧副本，别去改那个。
- 交互：空输入框回车 → 扫描（设计里 `LockInput.onAccepted` 本来就有这条分支，**宿主从前没接**）→ 提示行变 "Look at the camera…"；命中即解锁；未命中 → 提示行 4 秒 "Face not recognized"，**不自动重试**；**一开始打字就 abort 扫脸**（打字 = 密码路径，不跟相机抢同一次解锁）。扫脸期间密码框照常可用。
- 头像：探测链 `~/.config/omarchy/lock-avatar.{png,jpg,jpeg,webp}` → `~/.face` → `~/.face.icon` → `/var/lib/AccountsService/icons/$USER`（最后一条就是本机的账户图片，与 greeter 同源），喂给设计里**本来就存在**的 `Avatar` 组件 —— `Split.qml` 一直画着它，只是从前没人喂 `avatarPath`，所以永远显示首字母圆牌。
- 文案：提示行改成锁屏的说法（那句 "Press Enter to log in" 是从 greeter 带过来的）。有脸 → `󰱻  Press Enter for face unlock, or type your password`；脸+指纹都有 → 提指纹；都没有 → `Press Enter to unlock`。

**验证（全部不锁会话，2026-09-20 实测通过）**

- **PAM 栈（最强证据）**：`pamtester omarchy-lock-face $USER authenticate` → `successfully authenticated`，howdy 回 `Identified face as 主账户`。这条绕开 UI 与锁面，直接证明 `ir-light` → `pam_python`/howdy → 成功这条链是通的。
  ⚠ `pamtester` **不在官方仓库**（`pacman -S extra/pamtester` → target not found），在 **AUR**：`paru -G pamtester` → `makepkg -f` → `pkexec pacman -U pamtester-0.1.2-4-x86_64.pkg.tar.zst`（本机已装）。
- `cd split-lock && ./tests/state.sh` → 15 项全过（新增：人脸开关到视图、头像 URL 与版本击穿、**空回车走设计自己的分支**发出 `faceRequested`、提示行文案、`hintOverride` 覆盖）。
- `omarchy-shell lock preview` + `grim` 截图：右侧面板从上到下 头像（165px 实高）→ 问候 → 用户名 → 密码框 → 提示行全部画出；头像区与 `/var/lib/AccountsService/icons/$USER`（缩到 168×168）**平均像素差 5.6/255**、stddev 66.0 vs 68.9 —— 就是那张账户图片，不是首字母圆牌。
  （面板内容是 `anchors.verticalCenter` 居中，头像在 `y≈512` 而不是顶部；找头像别按顶部算。）
- `omarchy-shell lock status` 多报 `face: true` / `faceAuthenticating` / `avatar: /var/lib/AccountsService/icons/$USER`。
- 真机锁屏按一次回车：**用户自己做**（§11.20 的规矩，不主动锁他的屏）。

**改动落点**：`split-lock/{Service,LockView,Split}.qml`（仓库 → `./install.sh` 装进 `~/.config/omarchy/plugins/jianlongliu.split-lock/`）、`split-lock/face-pam.sh`、`tests/mockhost/shell.qml` + `tests/state.sh`。`Service.qml` 里所有增量都标了 `PORT (split-lock)`，`install.sh` 用两个 md5 把关（见 §11.18）。**回滚**：`sudo split-lock/face-pam.sh --remove`（人脸入口下次起壳层消失）或整目录删掉。改动前的三个文件备份在 `/var/tmp/lock-pre-face-20260920/`。

**证据边界**：离屏契约测试证明接线；`pamtester` 证明**这条 PAM 栈真能刷脸成功**；`lock status` + 截图证明探针与渲染。**唯一还差的是"在真锁屏上按回车"那一下**——那要用户自己锁（顺带一提：`shell.json` 的 `idle.lock = 300` 会让屏幕 5 分钟自己锁上）。


---

### §11.24 提示行换行 + 头像改成账户入口（2026-09-20，用户指定）

**用户原话**：「锁屏和登录页的字太长了, 你换个行. 顺便头像切换用户」，随后追问「锁屏不支持多账户吗?」，并在选项里选「去掉 chip」。

**1. 提示行不是难看，是被裁掉了。** 旧的 `lock-preview.png` 量出来：提示行像素一直延伸到 **x=2558**，而右侧面板内右边界只有 **x=2448**，约 110px 的 "…type your password" 被面板 clip 吃掉了。面板内宽 ~646 物理像素（=323 逻辑），提示却是整句 —— 缩短文案只是止血，正解是 `wrapMode: Text.WordWrap` + `width: lock.fieldWidth`，锁与 greeter 两处同改。新截图（`/var/tmp/lock-wrap.png`、`/var/tmp/greeter-shot.png`）都是两行，最右分别到 x=2390 / 2420，**均在 2448 以内**，不再裁切。

**2. 头像 = 账户入口，顶栏 chip 删掉。**（用户选「去掉 chip」）`Avatar` 加 `avatarClickable` 属性 + `avatarClicked()` 信号，`shell.qml` 的 `onAvatarClicked` 切 `picker`。⚠ **点头像只是打开账户选择器，不会把人登出** —— 真正提交要等选中账户后走密码/人脸。顶栏那个 chip 是纯装饰，删掉后没有替代品。

**3. 锁屏为什么不能"切换用户"**（答用户那句追问）：锁**不是登录管理器**。greetd 是**每次登录才 spawn 一个 greeter 进程**，登录完它就退了 —— 锁屏的时候根本没有活着的 greeter 可以切过去，账户切换需要 PAM/会话那一整套。锁上能做的只有"结束当前会话"，那等于替你登出，不是切换。多账户切换只有登录页有。

**4. 测试教训（值得记住的两条）**

- **`activeFocus=true` 是 QML 内部焦点，不等于合成器把键盘给了它。** `enter-triggers-face` 用例偶发失败（全套里失败、单跑通过）就是这原因：wtype 把回车打给了没有键盘焦点的窗口，按键凭空消失。修法：先打一个**探针字符**直到 greeter 报 `password field received input`（证明送达），再 Backspace 清空（空框上 Backspace 是 no-op，且**必须**清空 —— 非空框回车会走密码提交而不是扫脸），最后回车。**断言要证明送达，不能假设送达。**
- **diag 定时器约每秒重复打印同一行，所以"最后一行"最多是 1 秒前的旧样本。** 两个坑都由此而来：`grep -c 'pickerOpen=true'` 数的是**采样次数**不是打开次数（一次运行数出 12）→ 改成 `grep -o … | uniq | grep -c` 折叠成"打开次数 == 1"；`textLen` 清空那条要**轮询等一个新样本**（直接读 `tail -1` 会因采样时机偶发假失败，实测 `/tmp/greeter-smoke-enter-face.log` 里最后一行确实是 `textLen=0`）。
- **跑 `smoke.sh` 期间别执行会抢焦点的命令**（`pkexec` 会弹 polkit 认证框）。有一次连跑 10 项失败，就是我在用例进行中并行执行了 `pkexec ./install.sh`，wtype 的键全打给了认证框。测试要独占键盘，跑之前先把手头会弹窗的事停下。

**5. 密码框左边那块空隙（用户 2026-09-20 追加：「密码输入间隙是不是太靠右了?」「故意这么设计的?」）**

先查清楚再答：**对齐是上游自己写的** —— `Split.qml:104` 的 `textAlignment: TextInput.AlignLeft` 第三方原件里就有（我们没改），文字本来就是左对齐，不是居中。看着"太靠右"的真凶是共享组件 `PasswordField.qml` 算输入区内边距时 **左右两边都套了同一个 `Math.max(fingerprintReserve, glyphReserve)`**：左边本来只需要锁图标那点宽度，却被右侧"眼睛 + 人脸"两个图标的宽度顶开。截图量出来文字左边缘离框左边 ~87 逻辑像素 = 内边距 20 + 右侧图标区 ~65，数字正好对上 —— 就是"把右边的宽度借给左边"的偷懒写法，而 `PasswordField.qml` 与上游**逐字节相同**，所以这条是上游原样，不是我们弄坏的。

改法（用户选「收紧左边」）：`anchors.leftMargin` 用 `field.glyphReserve`，右侧维持原样。实测**占位文字左移 78 物理像素**（1974 → 1896），与锁图标之间的空隙从 110px 收到 32px，右侧眼睛/人脸图标**位置分毫未动**（2325..2406 前后一致）。锁定那份标 `PORT (split-lock)`，greeter 那份靠 `vendor.py` 新增的 `designs/PasswordField.qml` 补丁复现（复测：上游原件 + designs 补丁 → 四份设计文件与仓库逐字节一致）。

**改动落点**：`split-lock/Split.qml`（提示行换行）+ `split-lock/PasswordField.qml`（左边内边距；`./install.sh` 装进插件目录，`service` 类插件 `keepLoaded`，**必须 `omarchy-restart-shell` 才生效**）、`split-greeter/designs/{Split,DesignBase,PasswordField}.qml` + `shell.qml` + `SelfTest.qml` + `vendor.py` + `tests/smoke.sh`。greeter 侧已用 `pkexec ./install.sh` 部署到 `/etc/greetd/split-greeter`（该脚本**不碰** `config.toml`，所以不存在把自己锁在外面的风险），部署后比对**与仓库逐字节一致**。

**验证**：`split-lock/tests/state.sh` 15/15；`split-greeter/tests/smoke.sh` 34 项全过（不被打扰连跑两次稳定），再用 `GREETER=/etc/greetd/split-greeter ./tests/smoke.sh` 对**装好的那份**跑过两轮（换行后、内边距后各一轮）同样全过；锁的两张截图（换行后两行、最右 x=2390）与 greeter 截图（两行、最右 x=2420，均 < 面板内右边界 2448）目视 + 像素量测确认；内边距前后对比截图 `/var/tmp/lock-inset.png`（文字段 1974..2119 → 1896..2041，右侧图标段不变）；greeter 右上原 chip 位置整片平坦（mean 87 / stddev 1）。`vendor.py` 的 designs 补丁**可复现性复测**：拿 `/tmp/le/...` 的原始第三方文件只跑 designs 补丁 → `Split.qml`/`DesignBase.qml`/`PasswordField.qml`/`Avatar.qml` 与仓库**逐字节一致**，且二次运行幂等。

**待用户亲自确认**：锁屏真按一次回车（§11.20 的规矩，不主动锁他的屏）、greeter 上点一次头像（点击无法注入：本机没有 ydotool/dotool，wtype 只会打字）。


---

### §11.25 tty1 登录被**永久**锁死：greetd 只有一格 `configuring`（2026-09-20，真机定位并修复）

**现象**：用户在 tty1 输完密码「黑一下又回来」。greeter 自己的日志（`/var/lib/greeter/greeter.log`，`niri.kdl` 把壳的 stdout 重定向到那儿）末尾是 `event auth_fail error a session is already being configured`，而且**之后每一次**尝试都是这一句；同一时刻 `pgrep -af 'greetd --session-worker'` 里躺着一个从 15:21 起就再没退过的 `--session-worker 12`。

**根因（读源码定的，不是猜）**：greetd 0.10.3 的 `context.rs` 里 `ContextInner` 只有 `current` / `scheduled` / **`configuring`** 三格，而 `configuring` 是**整个守护进程唯一一格**、不按连接也不按用户区分（`create_session()` 进门就是 `if inner.configuring.is_some() { return Err("a session is already being configured") }`，所以后面那段"换掉旧会话再 cancel"的分支**永远走不到**）。能清掉它的只有三条路：`cancel_session`、`start_session`、greetd 重启。**命门在 `server.rs` 的客户端循环**：读到 EOF 就 `return Ok(())` —— 直接返回，**不 cancel**（只有 `client_handler` 返回 `Err` 才会走到 `client_ctx.cancel()`）。于是"开了会话却没走完就断线"= **永久占格**，其后每次 `create_session` 全被拒。

本机怎么踩上的：15:21:11 那次日志里，第一次 `create_session` 后 howdy 报 `Face detection timeout reached`、PAM 接着给 `Password:` 提示，**紧接着又冒出一次 `starting a passwordless (face) attempt`**（第二次 `create_session`，空框回车 = 再要一次人脸）→ 撞格 → 其后**连正确的密码也进不去**。注意 `Greetd.qml` 里 `restartHelper()` 的注释假设（"杀掉 helper → 连接断 → greetd 自己会取消"）**同样是错的**：断线不等于 cancel，那条路一样会留下占格。

**修复（两层，都不需要常驻进程）**：
1. `bridge/greetd-bridge.py`：`create_session` 之前先发一个 `cancel_session`（`clear_pending()`）。`Context::cancel()` 在"没有会话在配置"时也回 `Success`，作用域只可能是半途会话，永远碰不到正在跑的 greeter 或已登录会话 —— 幂等且便宜，等于每次尝试都先清场。
2. `Greetd.qml::begin()`：`busy || faceAttempt || awaitingSecret` 时直接忽略回车（会话未完成时不许再开一个，顺带省掉一次无意义扫脸）。

**没加守护进程**（用户提议后一起定的）：根因是"状态机格子没人 clean"，已在协议层堵死；再挂一个周期性"检测到 wedge 就清场"的 systemd timer 只是给已修的 bug 上保险，多一个常驻面 = 多一处会坏的地方。真要兜底，测试比 daemon 值（见下）。

**踩到的两个环境坑**：① `/run/greetd-<pid>.sock` 是 `0755 greeter:greeter`，但 unix socket 的 `connect()` 要的是**写**权限 → **非 root 连不上**（本大小姐在 `greeter` 组里也照样 `PermissionError`），所以"顺手发个 cancel"这件事必须走 pkexec。② `/tmp/greeter-install.log` 这种**别人的**文件，root 用 `>` 重定向也会 `Permission denied`（`fs.protected_regular` + sticky 位），pkexec 里别往 `/tmp` 的既有文件写日志。

**改动落点**：`split-greeter/bridge/greetd-bridge.py`（`clear_pending()` + `auth` 分支）、`split-greeter/Greetd.qml`（`begin()` 守卫）、`split-greeter/bridge/mock-greetd.py`（**mock 必须忠实**：新增 `Configuring` 单格——撞格回同一句错、EOF **不**清理、只有 `cancel_session`/`start_session` 放格；mock 不忠实就复现不出这个 wedge，这也是它以前一直绿着的原因）、`split-greeter/bridge/test-bridge.py`、`split-greeter/tests/smoke.sh`。已 `pkexec ./install.sh` 部署到 `/etc/greetd/split-greeter`（不碰 `config.toml`），装后 `md5sum` 与仓库**逐字节一致**。

**验证**：`bridge/test-bridge.py` 12 用例全过；**改前**有 3 条断言专抓此 wedge 而红（`retry after a failure`、`fresh helper after an abandoned face`、`cancels the stale conversation first`）；`tests/smoke.sh` **34 → 39 项全过**，新增 `enter-twice-while-scanning`（扫脸中再按回车：第二次不许开新会话、不许出现 wedge 文案、最后仍要在那条已开的会话上登成功）。另外 15:30:57 那次 `systemctl restart greetd` 现场验证了恢复路径：`terminate()` 会把 `configuring` 一并 cancel，用户随后在 tty1 **一次就登进去了**（卡死期间同样的操作只会拿到 `already being configured`）。

**注意**：重启 greetd 只带走它自己的子进程（greeter + 半途会话）。本机用户会话挂在 `login`/systemd 下（`login -- $USER` → `niri --session`），因此安全；但若哪天用户会话是 greetd 起的，`systemctl restart greetd` 会把它一起带走。

---

### §11.26 交接过渡：密码到桌面之间那段文字，以及两头各一段淡入（2026-09-21）

**现象**（用户原话：「在开机输入完密码确认后, 和启动完成之间可以加个过渡动画掩盖吗? 有文字, 虽然说无伤大雅」）：认证通过到桌面出来之间会闪一段文字。

**根因（实测，不是猜）**：**greetd 给会话的 stdout/stderr 就是那块 VT** —— `pgrep -af niri-session` 拿到 pid 后 `ls -l /proc/<pid>/fd/{0,1,2}` 三个 fd 全指向 `/dev/tty1`。而 `/usr/local/bin/split-greeter`（以及它的 `niri.kdl`）只把**壳**（quickshell）的输出重定向进 `greeter.log`，**niri 自己没重定向**：niri 是 Rust、日志走 stderr，于是它的 INFO/DEBUG 行（`starting version 26.04`、`loaded config from …`、`using as the render node` …）全部写进 tty1 的**文本缓冲区**。niri 用 DRM 接管屏幕时（VT 处于 `KD_GRAPHICS`）这些行看不见，**greeter 的 niri 一退出、VT 回到 `KD_TEXT`，整屏文字立刻现形**，一直挂到用户那份 niri 抢到 DRM —— 本机这段窗口实测约 1.5~2 秒（本 boot 的 journal：00:19:42 `Login approved`、00:19:43 用户会话打开、00:19:44.5 用户的 niri 起）。

**可复查的两条证据**：本 boot `journalctl -b | grep -c "INFO niri: starting version"` = **1**（只有用户会话那份 niri，它挂在 `niri.service` 下、stdout 进用户 journal）；`journalctl -b -u greetd | grep -c niri` = **0** —— greeter 那份 niri 的启动日志**不在 journal 里**，只可能落在它继承的 VT 上。**顺带**：既然"在图形模式下写 tty1 会更新缓冲区"是文字露出的原因，同一机制反过来就能**盖掉**它——趁 niri 还掌着屏先刷黑，niri 退出时露出来的就是黑的。

**两头都堵（4 处，用户要求"连桌面淡入一起做"）**：

1. **greeter 入口**（`install.sh` 生成的 `/usr/local/bin/split-greeter`）：先 `printf '\033[2J\033[H' >&1`（此刻 fd 1 还是那块 VT）刷黑缓冲，再 `exec >>/var/lib/greeter/greeter.log 2>&1`（**绝对路径**：greeter 用户的 HOME 是 `/`）。日志写不进去就 `if : >>"$log"` 判掉、退回原样 —— 这一步绝不能挡住登录。
2. **会话命令换包装**：新增 `split-greeter/session.sh` → 装成 `/etc/greetd/split-greeter/session`，`niri.kdl` 的 `GREETER_SESSION` 指向它。同样先刷黑再用 `exec >>$HOME/.local/state/omarchy/session.log 2>&1` 收走 `niri-session` 链路（登录 shell、systemctl、未来任何新输出）的字，最后 `exec niri-session "$@"`（`$@` 原样透传，`-l` 的登录 shell 语义不变）。它还 `: > "$XDG_RUNTIME_DIR/omarchy-boot-splash"` —— **桌面壳层靠这个标记区分"真登录"和"重启壳层"**（见 4）。
3. **登录面淡出**：`Greetd.qml` 在 `auth_ok` 后**不再立刻**向 greetd 要会话：先让 `handoffHintMs`（缺省 250ms，`GREETER_HANDOFF_HINT_MS` 可调，0 = 立刻交接）把 "Starting your session…" 停留住，再把 `handoffVeil` 置 1；`shell.qml` 那块黑幕矩形用 `Behavior on opacity`（`handoffFadeMs` = 260ms）淡到全黑，淡完 +40ms 才发 `start`。`start_failed`/`error` 会把黑幕收起来、登录面回来（黑幕留住 = 看起来像卡死）。
4. **桌面 bar 的入场（最终形态：加载期不上屏，到点整块出现）**：omarchy shell 侧**不放任何全屏遮罩**（黑幕/壁纸幕都试过、都废弃，理由见 `docs/visual.md` 第 33 条）。`shell/shell.qml` 启动时读标记 `$XDG_RUNTIME_DIR/omarchy-boot-splash`（读完即 `rm`，所以 `omarchy-restart-shell` 不重放）→ `bootRevealArmed`，再由 `pushBootReveal()` 推给"当前被配置成 bar 的那个对象"（**插件拿不到标记**，只能宿主推）。**在用的浮动 bar**：armed 时把 `PanelWindow.visible` 关掉（surface 完全不上屏，也就没有霜化）、等到**壳层真正组装完**才整块打开——2026-09-21 起不再是固定时长：宿主把 `omarchy.background` 服务里的 `paintedOnce`（壁纸第一帧解码上屏，见 `shell/plugins/background/Background.qml`）推给 bar，控件等它 + 地板 600ms / 天花板 6000ms（`bootHoldMs` / `bootHoldMaxMs`）。**不做滑入**，理由是实测出来的：霜化是 niri 按"区域"**自己画的**（不看客户端画了什么、也不看 alpha），滑入时屏幕上必然先出现一块**空的磨砂矩形**、再有个 bar 追下来 —— 用户原话「屏幕顶部有个 blur 的 bar, 然后再浮下来一个 bar」；而且那块 region 也跟不上位移（跟了就在屏外采样、整块丢霜化，见 `docs/visual.md` 33b ④）。**内置 `shell/plugins/bar/Bar.qml` 保留旧的"停屏外 + 滑入"写法（本机不在用，换回内置 bar 时才用得上）。**

   **关于"动画时长名义值"的教训（2026-09-21，先错后对）**：早先实测到"名义 1500+900 却在 ~0.9s 内一次落位、中途抓不到中间帧"，当时归因为"壳层启动期主线程太忙把动画帧吃掉"。**方向错了**：那轮测的其实是**内置 `plugins/bar/Bar.qml`**——而且它的做法是把 surface 停到屏幕外，surface 不在屏上时压根不出帧，钟照走、画面不同步；而屏幕上真正在显示的是第三方插件 `charlieras262.floating-bar`（见下）。后来改成"**普通 Timer 做 hold + 每帧按墙钟算进度**"，在**真正生效的那个 bar** 上实测节拍稳定 **16ms/次**、`bootReveal` 逐帧平滑 0.001→0.999。教训：① "先停屏外再进场"这类动画别用 `PauseAnimation`/`NumberAnimation` 排（surface 停屏外时它只走钟不出帧）；② 动手测任何"屏幕上该有的东西"之前，先确认你改的文件就是屏幕上那个（`~/.config/omarchy/shell.json` 的 `bar.id`）。

**改动落点**：`split-greeter/{install.sh,niri.kdl,Greetd.qml,shell.qml,README.md}` + 新增 `split-greeter/session.sh` + `$OMARCHY_PATH/shell/shell.qml`（标记 + `pushBootReveal()` 把 `bootRevealArmed`/`bootRevealPainted` 推给当前 bar + `bootRevealWallpaperPainted` 读服务）+ `$OMARCHY_PATH/shell/plugins/background/Background.qml`（**新增 `property bool paintedOnce`**，首帧壁纸解码就位时latch，2026-09-21）+ `~/.config/niri/effects.kdl`（`^omarchy-osd$` → `^omarchy-(osd|boot-banner)$`，让卡片同款霜化）+ `$OMARCHY_PATH/shell/plugins/bar/Bar.qml`（内置 bar 的滑入，**本机不在用**）+ **`~/.config/omarchy/plugins/charlieras262.floating-bar/Bar.qml` → `niri-port/plugin-patches/charlieras262.floating-bar.patch`（本机在用的浮动 bar；**加载期 surface 不上屏、到点整块出现**，见 `docs/visual.md` §33）**；`niri.patch` 现在是 **22 文件/48 hunk**，md5 `6138cc1bece9a94312572d8685c845a4`；重生成照 §8.7 限路径，**新文件必须显式补进路径表**，否则下次重放会漏。备份：`~/.config/omarchy/niri-port/niri.patch.bak-20260921-192644`（46 hunk 的上一版 —— 活体已改出 `paintedOnce`/`pushBootReveal()` 增补而补丁没跟上，repatch 一度 exit 2）、`…bak-20260921-bootreveal`（再上一版 `…bootcurtain2`，黑幕版 `…bootcurtain`）。

**验证**：
- **判据 = `tests/state.sh` 对账**（离屏、不开合成器，可随时跑）：本树与 `git archive HEAD` 的干净副本**各 7 项 FAIL、输出逐字节一致**（`diff` 全等）⇒ 本机那 7 项本来就红，本次改动**没有新增失败**。
- `tests/smoke.sh` **不作判据**：它**在当前会话里**跑、每个用例还要**独占键盘几秒**（靠 wtype 注入），本机拿不到键盘焦点时注入类必然 FAIL —— 那次半轮里 `no QML errors` 全绿（说明改后的 `Greetd.qml`/`shell.qml` 在真壳里起得来），但 9 项 FAIL 全是"键没落到密码框"这一类，与本次改动无关。要跑它请在能拿到键盘焦点时跑，**用户在场时别跑**。
- 桌面 bar 滑入**真机验过**（等价于真登录里壳层启动那一段）：写标记 → kill 旧壳 + `niri msg action spawn -- omarchy-launch-shell`（`omarchy-restart-shell` 也行）→ 逐帧 `grim -t ppm` 并把**顶部条带**裁出来拼图看（`magick -crop 2560x75+0+0` + `montage`，这一步不能省：**亮度数字很容易被别的窗口污染**）—— 抓到"无 bar → 半透明中间态 → 落位"三态，标记被消费，journal 无 QML 错误；**不写标记直接重启后条带立刻是落位值 0.509075**（不滑、不藏 bar）。`niri msg layers | grep -c omarchy-bar` 不作为判据：parking 是**改 margin、surface 一直 mapped**，图层计数不变。
- `qmllint` 对带 Quickshell 导入的文件只会静默失败（干净 HEAD 版同样 exit 255），别拿它当验证。

**验证/状态**：整条链已在一次**真登录**里目视确认过（用户认可动画与时机；随后指出两个观感问题——"没 blur"与"顶部一块空 blur + 一个 bar 追下来"，都已修掉 ⇒ 最终形态是上面的"整块出现"）。`omarchy-restart-shell` 只能验桌面侧那一段（而且锁屏期间会被拒）。greeter 侧四处改动**已装**（`sudo ~/Projects/omarchy-on-niri/split-greeter/install.sh` 跑过了，回退件 `/etc/greetd/config.toml.backup-*`）。

**还没做的两件事**（2026-09-21 只评估，下次研究）：见 §11.27。
### §11.27 交接那段黑：方向 A（底部 `Thinking…` 卡片）已实施，方向 B（plymouth 盖交接）仍搁置（2026-09-21）

**现状**：这次只做到"把那段 VT 文字变干净"——greeter 侧刷黑、桌面侧 bar 的入场（§11.26）。屏幕上仍是**黑 ≈1.5~2s**（greeter 的 niri 退出 → VT 回到文本控制台 → 用户的 niri 抢到 DRM，实测见 §11.26 根因段），之后壁纸才随壳层首帧出现。下面两条能进一步盖住它，**今天只评估、没实施**。

**决议（2026-09-21）：plymouth 这一路先搁置。** 用户原话：「我这个系统和 omarchy 关系都不是特别大了，主要是蹭他的插件」⇒ 本机（niri + greetd + 自绘 quickshell greeter）与上游（Hyprland + SDDM）已不是同一套，**上游"plymouth/SDDM 主题统一"的思路对本机没有参考价值**；且 plymouth 的 mkinitcpio 钩子是按 `plymouth-set-default-theme` 把主题目录**拷进 initramfs** ⇒ **换主题要重建 initramfs（本机走 UKI）**，换壁纸还得再重建一次。收益只是把 0.4~0.6s 的结构性黑换成一张图（B2），却要冒 root 单元 + 抢 DRM 的锁门风险 ⇒ **B1/B2 均搁置**。真要动时最省事一档：保持现状 `bgrt`，或 `omarchy-plymouth-set <背景色> <文字色> <logo.png>` 一次性生成主题（**不做"壁纸 splash"**）。本机只借上游的**壳层与插件**（`omarchy-shell`/`omarchy-restart-shell`、`~/.config/omarchy/plugins/*`、`omarchy-osd` 一类工具）。

**上游 Omarchy 怎么做（2026-09-21 查本机 Omarchy 树，非猜测）**：登录器是 **SDDM**（主题化 `/usr/share/sddm/themes/omarchy`，素材只有 `Main.qml`/`logo.png`/输入框一类、**没有壁纸图** ⇒ 登录屏大概率是纯色底 + logo，**此处是推断**）、会话走 **systemd 用户会话**（`uwsm-app`）。它处理交接观感的办法**不是盖住，而是让两头长得一样**：`bin/omarchy-plymouth-set <background-hex> <text-hex> <logo.png>`（另有 `--refresh-default` / `--refresh-sddm-default`）**一次把 plymouth 主题与 SDDM 主题刷成同一背景色 + 同一个 logo**。⇒ 三点结论：① 那段"没人画"的物理窗口**上游同样没解决**（SDDM 是 Wayland greeter、自己管 VT，所以它不会遇到我们这套"greeter 的 niri 日志漏到 VT"的毛病）；② 我们其实更连贯——greeter 的背景**就是账户壁纸**（`Greetd.qml` 的 `accountWallpaper()` + `/var/lib/greeter/{theme,wallpaper}`），两头都是壁纸；③ 值得抄的是 **plymouth 主题本身**：本机现在是 `bgrt`（厂商 logo），换成"背景色 + 自己的 logo"（用 `omarchy-plymouth-set` 或自写）**零风险**——plymouth 本来就只在 boot 期显示、DM 起来即 quit；**有风险的只是把 plymouth 拉起来盖登录交接**（= 方向 B 的后半段）。⇒ **方向 B 可拆成 B1（换 plymouth 主题，零风险）与 B2（用 plymouth 盖交接，需防锁门）。**

**`osd` 实操补充（2026-09-21 实机验过）**：`omarchy-osd -i <icon> -m <text> -p <0-100> -d <ms>` 只是把 payload 转给 `omarchy-shell -q osd show`（字段 `{icon,message,value,progressText,max,duration}`，默认 `duration` 1200ms）；**`-p` 一旦非空，脚本就把 `progressText` 填成 `"N%"`** ⇒ 想要"无数字的跑马灯"必须**绕过 `omarchy-osd` 直接** `omarchy-shell -q osd show '{"message":"Thinking…","value":"30","progressText":"","max":"100","duration":"1500"}'`（实测可用）。吐司是单块表面，连发就地替换（进度条 `Behavior on width` 140ms 缓动）⇒ 循环 0→100 大约每 150~200ms 发一次最顺。图标名走 `plugins/osd/OsdModel.js`。

**实测拆解（2026-09-21，01:39:50 那次真登录，系统 journal 与用户 journal 对齐）**：从 greetd PAM 打开用户会话算起 —— +47ms logind 建会话、**+205ms 才 `Starting niri.service`**（会话建立本身只 ~0.2s，greetd/systemd 不是瓶颈）、+765ms niri 进程起来（DRM/connector 就绪再 ~0.35s）、**+965ms quickshell 开始加载 `shell.qml`**（niri→壳层 ~0.75s），之后才是壳层解码壁纸出首帧。**开机那次还要多 ~0.5s**：systemd 用户管理器冷启动（`loginctl show-user … -p Linger` = `Linger=no`；从建会话到 `user@1000` 的 default target 约 0.7s），登录过一次再登就快。

⇒ 可分成三层：① **结构性黑（消不掉）** greeter 的 niri 退出 → 用户 niri 拿到 DRM 并画首帧 ≈ **0.4~0.6s**（VT/DRM 同一时刻只能一个客户端持有，这段没人画，只有 root 级 framebuffer 能盖 = 方向 B）；② **可打的部分 ~0.6~1.0s**：niri 已经能画、但壳层还没出壁纸，屏幕上是 niri 的空画面 ⇒ **✅ 2026-09-21 晚已实施**：niri `spawn-at-startup` 挂原生壁纸客户端 **`swaybg`**（本机新装，extra 仓库）先铺同一张图，壳层自己的 `Background.qml` 上来盖住它 —— 两份**逐像素一致**（130 个纯壁纸区块差 0.01/255），故无缝；`-m fill` 实测 = 源图 cover 居中；**必须排在 `omarchy-launch-shell` 之前**（同一 background 层内后映射的在上）。细节与回退见 `docs/local-overrides.md` §4。比 plymouth 便宜得多、风险也低 ✓；③ 开机独有的 ~0.5s：用户管理器冷启动，`linger` 可省（有副作用，需权衡）。

**方向 A：底部 `Thinking…` 卡片（2026-09-21 已实施）**
- 形态（用户点名）：**底部居中的深色卡片，脑形图标（menu 的 `learn` 用的 U+F09D1）+ `Thinking…`**，加载期占住观感。
- **`omarchy-osd` 路线实测被否**：真登录路径下 `osd` 图层 **@2073ms** 才上屏，而标记在 **891ms** 已被读走 ⇒ 晚 ~1.2s、落在 bar 现身之后，只停 0.39s。探针证明**命令本身成功执行**（`rc=0`）⇒ 不是失败，而是**会话里第一次 `osd show` 要付 ~1s 的插件加载费**（对照：预热过之后手动发一发 54ms 上屏、`-d 1200` 停满 1200ms）。顺带否掉下面 (a)(b) 两条：两种做法都要付这笔首屏钱。
  - (a) 壳层小循环发 `-p`（0→100，每 ~100ms 一次 IPC，不改上游代码）—— 仍要付首屏钱；
  - (b) 给 `Osd.qml` 加 indeterminate 模式（几行，它在 `niri.patch` 里，要按 §8.7 重生成补丁）—— 同样。
- **最终形态**（浮动 bar 插件里加第二个窗口，全部落在 `plugin-patches/charlieras262.floating-bar.patch`）：`Variants{model:Quickshell.screens}` + `component BootBannerPanel: PanelWindow`，**必须逐屏 + 显式 `screen: modelData`**（照抄同文件 `BarPanel` 的写法；不写 `screen` 的 `PanelWindow` 在这个宿主里**根本不建、还不报错**）；`exclusionMode: Ignore` + `mask: Region{}`（不占位、不吃点击）；卡片本体**照 OSD 关机吐司那套尺寸做**（`pad = Style.space(16)`、字距 `round(pad*2/3)`、字形 `Style.font.displayLarge`、消息 `Style.font.title` **加粗**、离底 `Style.space(67)`、高 = 边框 + pad + displayLarge + pad + 边框、图标列按**墨迹**宽度量而不是字格宽度），表面**不是全宽条**而是**卡片本身大小**（左右用 `margins` 居中），这样它才能借用 `~/.config/niri/effects.kdl` 里 `^omarchy-(osd|boot-banner)$` 那条 `blur true` 规则、和关机吐司**一样是霜化的**（`blur true` 磨的是整块 surface，全宽表面会磨满屏；底填 `Color.menu.background` 原样不压平，靠这条规则撑）。
- **常驻映射、藏在屏下**（`margins.bottom` 取负值）：因为**首次上屏要付 ~800ms**（建 layer surface + 塑字形）。实测：`visible` 开关版在 822ms 读到标记、**1798ms 才上屏**；改成停屏外后只剩 ~20ms 的 margin 变化（bar 自己就是这么做的）。
- **触发与实测时序**（2026-09-21 冷启动，探针 + 逐帧 `grim` 小区域对表）：`bannerUp = root.bootRevealArmed && !root.bootRevealShown` 驱动 margins；壳层起来后 bar 插件在 **~350ms** 上屏（层在）、**~1059ms** 收到 armed（卡片升上来，此刻底子是 niri 的灰底、壁纸还没画）、宿主 **~1348ms** 报"壁纸已画"（独立像素对表：壁纸区亮度在 **1335~1443ms** 之间从 0.251 跳到 0.751 ⇒ 信号准到 100ms 内）、**~1782ms** 卡片收回 + bar 整块出现。即**卡片只在真正的空窗期（灰底 → 壁纸）里挂着**，bar 永远落在壁纸之后；固定时长做不对这件事——同一台机器各次冷启动差几百毫秒，开机那次还要多 ~0.5s。
- **顺带修掉一个把前面所有实测都带偏的坑**：`BarPanel` 里 `visible:` 被写了两次（插件自带的 `visible: !remapGuard.remapping` + 之前种进去的 `visible: root.bootRevealShown`）⇒ Qt 报 `Property value set multiple times`（**致命**，不是警告）⇒ **整个插件加载失败**，宿主 `shell.qml` 静默 `bar option charlieras262.floating-bar failed to load, falling back to omarchy.bar` ⇒ 屏幕上换成了**内置 bar**。于是"改插件毫无反应"，而此前测到的各种时长/上屏时间全是内置 bar 的。**现已合并成 `visible: root.bootRevealShown && !remapGuard.remapping`。排查口诀：改插件没反应 ⇒ 先 `journalctl --user -t omarchy-shell | grep -E "failed to load, falling back|Property value set multiple times"`；同一个对象里一个属性只能赋值一次（`visible`/`color`/`implicitWidth` 这类）。**
- **两个尺寸/配色坑（2026-09-21，用户当场抓包）**：① **`Style.space(n)` 是像素直通、不是间距档位**（`space(11)` = 11px）⇒ 我按档位算，卡片做出来只有 **23px 高**（`Style.font.body` 12 + 11），再加上 `space(6)` 的"内边距"= 每边 3px、`space(2)` 的字距 ⇒ 一条又扁又挤的细条；截图缩到 0.5x 时我还判成"小巧、没问题"。真实尺寸应为：药丸高 = 字形 24 + `space(24)`、左右各 `space(18)`、字距 `space(8)`（`Style.spaceReal(px)` 是同一个东西的浮点版）。② **底色必须压成不透明**：主题的 `Color.menu.background` / `Color.tooltip.background` 都带 alpha，平时靠 **niri 的磨砂**撑着——而本图层没有 blur 规则 ⇒ 卡片半透明、背后的 dock 图标直接透出来。改成抄 OSD 那套 `BorderSurface` + `Color.menu.background`（用 `Qt.rgba(...,1)` 压平）+ `Color.popups.text/border` 之后正常。
- 仍未做的观感项：**`arc-dock` 也是加载期整块出现**，而且它和卡片同处"底部居中"⇒ 卡片会压住 dock 图标（可选：给 dock 同一套 reveal 处理，或把卡片抬到 dock 之上）。

**方向 B：用 plymouth 盖交接空窗（大工程，单独立项）**
- **机体现状（2026-09-21 实测）**：plymouth 已装（`26.134.222-2`）且**已在用**——`/etc/mkinitcpio.conf` 的 `HOOKS` 含 `plymouth`、内核 cmdline（`/etc/kernel/cmdline`，走 UKI）含 `splash`、`/etc/plymouth/plymouthd.conf` 的 `Theme=bgrt`（厂商 logo）、`plymouth-poweroff.service` / `plymouth-reboot.service` 是 static（关机画面就是它）；本 boot journal 有 `Show Plymouth Boot Screen`。**（本卷早先记的"装了没配"是错的。）**
- **机制**：照抄关机那套 —— 交接瞬间用 root 单元重新拉起 `plymouthd --mode=…` + `plymouth show-splash`（换成**壁纸主题**：全屏壁纸 + 一个指示器），等会话的合成器要 DRM 时 `plymouth quit --retain-splash`（画面**原地保留**，直到 niri 第一帧才被替换）。
- **能盖多少**：盖掉 greetd 交接后、systemd 用户会话起来的那 1~1.5s；盖不掉 **niri 起来到壳层画出壁纸之间的 ~0.3~0.7s**（那时 plymouth 已让位，niri 自己在画黑底）。净效果 **黑 1.5~2s → ~0.3~0.7s**，且中间不再有"壁纸突然冒出来"。**不是零。**
- **前置与风险**：① 要做一个 plymouth 主题（`bgrt` 是厂商 logo，不能用）；② 登录链路多一个 **root systemd 单元**；③ 与 greetd/niri 抢 DRM 的时机必须对齐 —— **plymouthd 不让位 = niri 起不来 = 把自己锁在门外**。所以必须：先备份（initramfs / `/etc/kernel/cmdline` / greetd 配置 / `plymouthd.conf`）、留 TTY（Ctrl+Alt+F2）回退路、先做**不进登录链路**的干跑验证，再改一处验一处。
- **结论**：先做 A（零风险）；B 等"那 0.3~0.7s 尾巴仍旧碍眼"再立项，顺带可把开机的 `bgrt` logo 一起换掉。

---

## 附：两条锁屏路线并存与收敛（原文 `§8 第 6 条`，2026-08-24 前后）

> 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽入本卷：锁屏主题的内容归锁屏卷，别再回主文档找。

6. **锁屏**：niri 侧 `Super+Alt+L`（swaylock）与 Omarchy `Mod+Ctrl+L`（`omarchy-system-lock`
   → `omarchy-shell lock lock`）两条路线并存（**2026-09-19 已收敛为单键 `Mod+L`，swaylock 那条删了**，
   见 §8 第 24 条）；后者依赖 QuickShell 的 `omarchy.lock` 插件，
   在 niri 上是否真正锁住待实测。
