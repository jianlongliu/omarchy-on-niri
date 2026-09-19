# Omarchy greeter —— 用锁屏的 Split 设计当登录界面

greetd 的登录界面：渲染锁屏插件 `io.github.sirjul1337.lock-explorer` 的 **Split 设计**，
支持**多账户**与**人脸（howdy）优先**的认证，不依赖 dms-shell，也不依赖正在运行的 Omarchy shell。

```
greetd ──► /usr/local/bin/omarchy-greeter ──► niri（本目录的 niri.kdl）
                                                   └─► quickshell -p /etc/greetd/omarchy-greeter
                                                          ├─ designs/Split.qml   （复用的锁屏设计，宿主即 lock 对象）
                                                          ├─ Greetd.qml          （登录状态机）
                                                          └─ bridge/greetd-bridge.py ──► $GREETD_SOCK（greetd IPC）
```

## 认证是怎么走的

**先刷脸，PAM 说了算。** 本机 `/etc/pam.d/greetd` 的顺序是
`ir-light`（optional）→ `howdy`（sufficient）→ `system-local-login`。
所以登录流程是：

1. greeter 发起**不带密码**的 `create_session`：PAM 直接跑 howdy，界面显示
   "Look at the camera, or type your password"，字段处于 `Checking…`。
2. 人脸命中 → PAM 成功 → greeter 立刻 `start_session`，**一次按键都不需要**。
3. 人脸没命中 → PAM **自己**会轮到 `pam_unix` 并抛出 secret 提示；greeter 收到
   `auth_message(secret)` 才把密码框交给用户，用 `post_auth_message_response` 送回。
   在收到提示前就输入的密码会被**排队**，等提示一到自动交付（不会开第二个会话）。
4. 空字段按回车 = 重新武装人脸扫描（对应锁屏里"回车重试指纹/摄像头"的语义）。

没有 howdy 的机器上，第 1 步会立刻收到 secret 提示，密码框就是常规登录框。

**多账户与"长相"**：登录界面的**配色与壁纸跟着选择器里当前选中的账户**走，
启动时选中 = 上次登录的账户（`last-user`）。切换账户时左半边的壁纸和整块面板的色调会一起
换成那个账户的主题，登录进去看到的和登录前看到的一致。字体/间距属于机器级，取自最近一次
`sync` 的那个账户的 `shell.toml`，不随账户切换。

账户列表来自 `/etc/passwd` 里 uid≥1000 的账户 + `/var/lib/AccountsService/icons/<user>`
头像（没有头像就显示首字母）。右上角常驻的账户按钮打开选择器（↑↓ 选择、Enter 确认、
Esc 取消，也可鼠标点）。切换账户会 `epoch += 1`：**旧账户的人脸扫描即使随后命中也会被
丢弃并向 greetd `cancel_session`**，绝不会登成错的人。成功登录的账户写入
`$HOME/.local/state/omarchy-greeter/last-user`，下次默认选中。

## 装与回滚

```sh
sudo ./install.sh        # 拷到 /etc/greetd/omarchy-greeter + /usr/local/bin/omarchy-greeter
sudo omarchy-greeter-sync                    # 每个真实账户的配色/壁纸都同步一遍
sudo omarchy-greeter-sync jianlongliu yvonne # 只同步这两个（第一个同时作为共享缺省）
```

`install.sh` **不动** `/etc/greetd/config.toml`——切 greetd 到本 greeter 是唯一能把人锁在门外的
一步，脚本只在最后把命令打印出来。切换时务必先开一个 TTY（Ctrl+Alt+F2）：

```toml
[default_session]
command = "/usr/local/bin/omarchy-greeter"
user = "greeter"
```

回滚 = 把 `command` 改回原值（dms-greeter 留下的备份在 `/etc/greetd/config.toml.backup-*`），
或在 TTY 里直接换回来。**不要**同时卸 `greetd-dms-greeter-bin`：它一旦被删，
`pacman -Rs` 会顺手带走 `quickshell`（它只剩下这一个反向依赖），本 greeter 和 Omarchy shell
都会跟着瘫。真要卸，先 `sudo pacman -D --asexplicit quickshell`。

## 不登出也能测

```sh
./tests/smoke.sh
```

它用 `bridge/mock-greetd.py` 假装 greetd、用 `GREETER_ACCOUNTS_DIR` 指到一份临时账户目录，
跑四个场景：人脸命中直通、人脸未命中回落密码
（密码在扫描中提交）、密码错误（**不应**产生会话）、切换账户后登录。每个场景都断言
greetd 是否收到 `start_session`、greeter 是否干净退出、有无 QML 报错；
日志落在 `/tmp/greeter-smoke-<场景>.log`。桥接本身另有 24 项协议断言：
`python3 bridge/test-bridge.py`。

单跑一次（要截界面时用）：

```sh
python3 bridge/mock-greetd.py --socket /tmp/m.sock --user jianlongliu --password hunter2 \
  --log /tmp/start.log --howdy --delay 5 &
GREETD_SOCK=/tmp/m.sock GREETER_BRIDGE=$PWD/bridge/greetd-bridge.py \
GREETER_USER=jianlongliu GREETER_ACCOUNTS_DIR=/var/lib/greeter/users GREETER_CORNER_RADIUS=10 \
GREETER_SELFTEST_PASSWORD=x GREETER_SELFTEST_OPEN_PICKER=1 qs -n -p .
```

`SelfTest.qml` 只在 `GREETER_SELFTEST_PASSWORD` 非空时经 `Loader` 加载，生产路径不经过它。

## 配置面

分辨率固定 modeline 2560x1600@60、`scale 1.5`（和 dms-greeter 的 greeter 合成器一致），
**没有** `mode` 行；圆角走 `GREETER_CORNER_RADIUS`。

登录用户 / 会话命令在 `niri.kdl` 的 `environment` 段（`GREETER_USER` / `GREETER_SESSION`）；
`GREETER_ACCOUNTS_DIR` 覆盖每个账户的取色与壁纸目录（只在测试里用，缺省 `/var/lib/greeter/users`）。

主题/壁纸由 `sync.sh`（`omarchy-greeter-sync`）拷进 `/var/lib/greeter`：`/data` 壁纸库对
greeter 用户不可读，所以是拷贝而非软链。布局：

```
/var/lib/greeter/.local/state/omarchy/current/theme/   共享缺省配色（也是 Color.qml 的兜底路径）
/var/lib/greeter/wallpaper                             共享缺省壁纸
/var/lib/greeter/.config/omarchy/shell.toml            机器级外观（字体/间距）
/var/lib/greeter/users/<账户>/theme/                   该账户的配色
/var/lib/greeter/users/<账户>/wallpaper                该账户的壁纸
```

从没跑过 Omarchy 的账户，`users/<账户>/theme` 与 `wallpaper` 会是指向共享缺省的软链。
改完主题重跑一次 `sudo omarchy-greeter-sync` 即可。

## 复用的锁屏组件与补丁

`designs/`、`Commons/`、`Ui/` 是从锁屏插件与 Omarchy shell **拷进来的**（greeter 用户读不到
用户 home，登录时也没有 shell 在跑，不能靠 import）。`vendor.py` 负责按组件闭包重新拷贝并重放补丁：

```sh
python3 vendor.py     # 插件升级或 omarchy update 之后重跑
```

只有四处改动 vendored 代码，都写在 `vendor.py` 的 `PATCHES` 里：

1. `Commons/Color.qml`：配色目录可以从外面指定（`themeOverride`）。greeter 用户的 HOME 只有
   一份主题，而登录界面要按选中的账户换色，所以 `shell.qml` 把 `Color.themeOverride` 指到
   `users/<账户>/theme`。默认值仍是原来那条 `$HOME` 路径。
2. `DesignBase.qml`：`userName` 不再是 `$USER`（那是 `greeter`），改为宿主可设的 `loginUser`；
   另加 `hintOverride` 让宿主接管提示行（显示"看摄像头"等状态）。
3. `Split.qml`：提示行 "Press Enter to unlock" → "Press Enter to log in"，并优先用 `hintOverride`。
4. `Style.qml`：`cornerRadius` 缺省从 `GREETER_CORNER_RADIUS` 取——greeter 里没有 hyprctl 可问。

`Commons/qmldir`、`Ui/qmldir` 由 `vendor.py` 生成，**必须**保留 `singleton` 关键字
（丢了会让 `Color.lock.*` 全变 undefined）。

## 已知边界

- 单输出假设：greeter 合成器只配了 `eDP-1`。
- 字体/间距不随账户切换：每个账户自带的 `~/.config/omarchy/shell.toml` 覆盖不会被读（只读主题自带的
  与共享缺省），换字体请改 `niri.kdl` 或共享缺省。
- 选择器以鼠标为主；键盘上下/回车/Esc 只在它获得焦点时有效。
- 指纹/FIDO2 没有专门 UI：它们会作为 PAM 消息出现，而不是被单独渲染成一个图标。
- `start_session` 固定 `niri-session`（`GREETER_SESSION` 可改），没有会话选择器。
- 密码只经由 bridge 的 stdin 传递（不进 argv、不落盘）；PAM 与日志会话创建始终在 greetd 里完成。
