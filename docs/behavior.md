# 功能调整 — Omarchy on niri 卷（behavior）

> 正本：`~/Documents/omarchy-niri-behavior.md`（与仓库 `docs/behavior.md` 逐字节一致）。
> 本卷 2026-09-20 从 `omarchy-on-niri.md` 抽出（模块化拆分），**编号一律沿用正本** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，正本对应位置留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `omarchy-on-niri.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `omarchy-on-niri.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 3. **快捷键重映射已按用户方案落地**（2026-08-24）：tiling 改成方向键方案、移除 vim 键，
- 24. **按键表去重 + 应用启动键统一走 Omarchy 包装器（2026-09-19/20，用户要求）**：用户原话"好多都重复"，
- 26. **按键里不能写开窗属性（`open-floating` 放 bind 里 = 整份配置被拒）（2026-09-20，用户问「Super+E 的 nautilus、
- 9. **system 开关已修并统一标准化（2026-08-25）**：菜单 `system.logout/reboot/shutdown` 走 `omarchy-system-*`，
- 11. **电池面板 POWER PROFILE 区为空（2026-08-25 已修）**：系统电源后端是 **TLP**（`tlp` + `tlp-pd`
- 15. **brightnessctl 授权安装 + 背光权限（2026-08-25）**：媒体键 OSD（§5.3）依赖
- 23. **screensaver 关掉并屏蔽（2026-09-20，用户要求「很烦，屏蔽和禁用他」）**：本机
- 8.17 输入源徽章（`ronald.input-sources`）+ fcitx5 双源前提（2026-09-19）
- 12. **Super+K 键位菜单只剩 2 条（第二次复发，2026-08-25 晚已修）**：同日早些时候修过一次
- 8.6 A 层：菜单指向 niri 真配置，Hyprland 层降级
- 8.14 菜单空白（"Nothing here yet"）的成因与自愈（2026-09-19）
- 14. **菜单 Apps 列表启动全部失灵（2026-08-27 已修）**：菜单 "Apps" provider 经
- 21. **`Install > Package` / `AUR` 点了没反应、也不报错（2026-09-19 修）**：菜单里只有三条绕过演示终端
- 20. **换主题时 `omarchy-theme-set-browser-policy` 因 sudo 要密码失败**（日志成片
- 25. **桌面双击弹窗慢（壁纸/主题切换器"要等会"）（2026-09-20，用户要求）**：入口是 `shell/plugins/background/Background.qml`
- 19. **耗电/续航专项（2026-09-19 测过一轮，下次接着做）**：表现为"感觉慢 + 续航差"。已排除的

---

3. **快捷键重映射已按用户方案落地**（2026-08-24）：tiling 改成方向键方案、移除 vim 键，
   `Mod+K`=keybindings、`Mod+Ctrl+L`=锁屏 让给 Omarchy（**2026-09-19 起锁屏统一为 `Mod+L`**，见 §8 第 24 条）。
   `Mod+Ctrl+R`/`Mod+comma` 仍被 niri 占用，待后续让出。**`Mod+Escape` 已于 2026-08-31 让出**
   （改回 System menu；逃生键挪至 `Mod+Shift+Escape`，见 §5.5）；**2026-09-19 起系统菜单改到
   `Ctrl+Alt+Delete`**（§8 第 24 条）。

---

24. **按键表去重 + 应用启动键统一走 Omarchy 包装器（2026-09-19/20，用户要求）**：用户原话"好多都重复"，
    并给定目标键位，于是按"**每个功能只留一个键**"重排 `~/.config/niri/binds.kdl`（清单已同步进 §5.3）：
    - 锁屏 `Mod+L`（合并掉 `Super+Alt+L` 与 `Mod+Ctrl+L`）；终端 `Mod+Return` →`omarchy-launch-terminal`
      （合并掉 `Mod+T`）；关窗口 `Mod+Q` + 新增 `Alt+F4`；系统菜单 `Ctrl+Alt+Delete`（该键原来是 `quit`，
      而 `Mod+Escape` 也是系统菜单 → 让位给它）。
    - 新增：`Mod+E` → nautilus、`Mod+Z` → `omarchy-launch-browser`、`Mod+Y` → yazi、
      `Ctrl+Shift+Esc` → btop（后两个在新终端里跑：`omarchy-launch-terminal yazi|btop`）。
    - **`Mod+Shift+E`（退 niri 会话）不是重复项**，保留——"关窗口"和"退会话"是两件事。
    - 做法：被合并的旧键**就地注释成 `// dropped: …`**（不删行，要恢复取消注释即可），
      备份 `~/.config/niri/binds.kdl.bak-dedup-*`；`niri validate` 通过、生效行无重复键。
    - **终端类一律走 `omarchy-launch-terminal`**（与菜单同一条路、自带"跟随当前终端 cwd"），不裸调
      `xdg-terminal-exec`——这条依赖垫片在位（§8 第 22 条）。`Mod+Z` 的实测恰好把垫片 v1.0 的 `setsid`
      坑顶了出来（`systemd-run` 路径静默死，见 §8 第 22 条 v1.1），修完 3 秒出 Zen 窗口。
    - 遗留未定：`Mod+O` 与 `Mod+Tab` 都绑 `toggle-overview`（用户未表态，暂留两个）。
    - 后补（2026-09-20）：`Mod+Y` / `Ctrl+Shift+Esc` 的命令行多了 `--app-id=org.omarchy.float-tui`、`Mod+E` 的 nautilus 靠 window-rule 浮动，
      见 §8 第 26 条。

---

26. **按键里不能写开窗属性（`open-floating` 放 bind 里 = 整份配置被拒）（2026-09-20，用户问「Super+E 的 nautilus、
    Super+Y 的 yazi 能浮动吗」）**：
    - **结论**：niri 26.04 的 keybind **只允许一个动作**。`Mod+E … { spawn "nautilus"; open-floating true; }` 的报错是
      `× only one action is allowed per keybind`，箭头指在 `open-floating` 上（`unexpected node`）。不是拼写问题：临时配置里
      把键名改成 `open-floaating`，报错**一模一样**；而只留 `spawn "nautilus";` 则 `config is valid`。
      **开窗属性的正确位置是 window-rule**（本机已有两条在跑：Firefox PiP、`org.omarchy.terminal`）。
    - **最坑的地方**：这个错**不弹在桌面上**。niri 的配置 watcher 对整份 `config.kdl`（含所有 include）做事务性校验，
      **任何一处失败就整体丢弃、继续用旧配置**，屏幕上毫无提示；只有 journal 里有
      `niri[pid]: Error: × only one action is allowed per keybind` + `binds.kdl:27` 那样的行号。
      症状因此是"改了跟没改一样"，而且会连累**同一次写的其它按键**（用户那行就是这么一直不生效的）。
      排查口诀：改完按键先 `niri validate`（它会对 include 一起校验），再看 `journalctl` 有没有 `niri\[` 的 config 报错。
    - **落点（2026-09-20）**：`window-rules.kdl` 末尾加两条 —— `^org.gnome.Nautilus$` 与 `^org\.omarchy\.float-tui$`
      （各 `open-floating true` + `default-column-width { proportion 0.6 }` / `default-window-height { proportion 0.7 }`）；
      TUI 那条**要重复磨砂块**，因为 Ghostty 的规则匹配的是 `com.mitchellh.ghostty`，换了 app-id 就不覆盖了。
      yazi 与 btop 都跑在 ghostty 里、app-id 本与所有终端相同，**靠 `--app-id` 分开**，且**共用一个 `org.omarchy.float-tui`**
      （用户偏好统一入口：将来再加 htop 之类只需换命令、不用加规则；要单独调尺寸就给它自己的 app-id 再复制一条规则）：bind 改成
      `omarchy-launch-terminal --app-id=org.omarchy.float-tui yazi|btop` → `xdg-terminal-exec --app-id=` → ghostty desktop entry 的
      `X-TerminalArgAppId=--class=`（跟安装/卸载终端做成 `org.omarchy.terminal` 是同一条路；垫片 `~/bin/uwsm-app` 只吃掉
      `--` 之前它自己的选项，命令行照原样透传）。
    - **实测**（2026-09-20 逐个起窗口、`niri msg --json windows` 读回）：`… --app-id=org.omarchy.float-tui yazi` →
      `app_id=org.omarchy.float-tui, title="Yazi: <cwd>", is_floating=true, window_size=[764,528]`；`… btop` 同样
      `is_floating=true, [764,528]`（= 0.6×1280 / 0.7×760 逻辑像素减 gaps）；
      `nautilus --new-window` → 新窗口同样 `is_floating=true`。`niri validate` 通过、niri 自动重载
      （journal `DEBUG niri_config: loaded config from …`）。测试窗口已关闭，未留垃圾。
    - **两个边角**：① 同文件里写 `match app-id="^org\.gnome\.Nautilus$"` 会报 `invalid escape char` —— KDL **普通字符串里
      `\.` 非法**，要么照上游写不转义的 `"^org.gnome.Nautilus$"`，要么用原始串 `r#"^org\.gnome\.Nautilus$"#`
      （这条是本次自己踩的，改完才 `config is valid`）。② nautilus 是单实例 / D-Bus 激活：**已有窗口时再按 Super+E 只是聚焦**
      （旧窗口当初就没浮动，规则也不会回头改它，规则只作用于新窗口）；要每次开新的浮动窗就把 bind 写成
      `spawn "nautilus" "--new-window"`。手动把当前窗口切浮动是 `Mod+V`。
    - 回退：还原 `~/.config/niri/binds.kdl.bak-20260920-floatbinds` 与
      `~/.config/niri/window-rules.kdl.bak-20260920-floatbinds`，再 `niri validate`。

---

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

---

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

---

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

---

23. **screensaver 关掉并屏蔽（2026-09-20，用户要求「很烦，屏蔽和禁用他」）**：本机
    `~/.config/omarchy/shell.json` 是 `idle = {lock: 300, screensaver: 150}`，所以空闲 2.5 分钟先弹
    screensaver（在终端里跑 ASCII art）、5 分钟才锁屏。处置分两层，**都走官方机制、不碰 omarchy 本体**：
    - **禁用（本体）**：官方开关 `~/.local/state/omarchy/toggles/screensaver-off`（`omarchy-toggle
      screensaver-off` 打开）。`bin/omarchy-launch-screensaver` 开头就是
      `omarchy-toggle-enabled screensaver-off && [[ $1 != force ]] && exit 1`，于是 idle 计时器这条路
      直接死掉。实测：`omarchy-launch-screensaver` → exit 1、无新窗口（`niri msg windows` 前后一致）；
      当时正在跑的那个实例（ghostty `--class=org.omarchy.screensaver`）已杀掉。
    - **屏蔽（入口）**：用户 override 加 6 条 `when:"false"` —— `system.screensaver`（System 菜单）、
      `trigger.toggle.screensaver`（Trigger→Toggle）、`style.screensaver` 及其 `.text`/`.image`/`.default`
      （Style→Screensaver 那组 branding）。这几条是**唯独带 `force`、能绕过上面那个开关**的入口，
      不屏蔽就等于开关形同虚设。备份 `~/.config/omarchy/extensions/omarchy-menu.jsonc.bak-20260920-prescreensaver`。
    - **别去动 `idle.screensaver`**：计时是 `min(screensaver, lock)` + 差值的两段式，把它调成等于 `lock`
      会让 screensaver 在锁屏那一刻抢跑（`screensaverDelay = 0`），比现在更糟。停掉的功能不需要改超时。
    - 回退：`omarchy-toggle screensaver-off off` + 还原上面那个备份。触发点已全局扫过：没有 systemd 单元、
      没有 niri 绑定（`Indicators` 里的 StayAwake 是手动「别睡」开关，与此无关）。
    - 同一次还修掉这份 override 文件里 **5 处超长 `\u` 转义**（2 处历史遗留 + 3 处新增），规则见 §8.6
      末尾那两条 override 注意。

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
若要绑快捷键，`Mod+Space`（Omarchy 菜单）与 `Mod+D`（Apps 菜单）已占用（§5.3；`Mod+Alt+Space` 那个重复键
2026-09-19 已释放，见 §8 第 24 条），需另挑。
fcitx5 自身由 `/etc/xdg/autostart/org.fcitx.Fcitx5.desktop` 在登录时拉起（非 systemd 用户单元）。

---

12. **Super+K 键位菜单只剩 2 条（第二次复发，2026-08-25 晚已修）**：同日早些时候修过一次
   （垫片 `cmd_binds` 从解析 Hyprland 改为解析 niri 配置，见 §4）；晚上配置模块化拆分（§5.7）后
   **再次复发**——根因是 `_config_bindings()` 只读 `config.kdl` 本体找内联 `binds { }` 块，
   而键位已整体搬进被 include 的 `binds.kdl` → 解析为空 → 菜单只剩脚本里写死的 2 条
   static_bindings。修复：垫片加 `_niri_config_lines()` 递归展开 `include`（防再拆文件再断）。
   验证：`hyprctl binds` 129 条记录、`omarchy-menu-keybindings --print` 恢复 131 条、
   clients/devices 无回归；备份 `~/bin/hyprctl.bak-20260825-211843`。

---

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

- **Icon 转义：`\u` 只吃 4 位十六进制，>U+FFFF 必须写 UTF-16 代理对（2026-09-20 修）**：这份文件里
  `\uf0379`／`\uf10ac`／`\uf1104` 这类**五位**写法会被 `JSON.parse` 读成 `U+F037` + 字符 `"9"`（默认项用的是
  **字面量字符**，所以只有 override 会踩这个坑）。正确写法：`U+F0379` → `\udb80\udf79`、`U+F10AC` →
  `\udb84\udcac`、`U+F1104`（screensaver 图标）→ `\udb84\udd04`。本轮共修 5 处（2 处历史遗留 + 3 处新增）。
  校验法（不依赖壳层、可离线跑）：把 `MenuModel.js` 的 `stripJsonc` 两条正则原样搬过来剥注释/尾逗号 →
  `json.loads` → 逐项比 user 与 default 同 id 的 `icon` 码点（2026-09-20 自查 13 项全等）。
- **`stripJsonc` 只删「整行 `//` 注释」和「尾随逗号」**：正则分别是 `/^\s*\/\/[^\n]*(\n|$)/gm` 与
  `/,(\s*[}\]])/g`。所以这份文件里**代码后面不能写行内注释**——`"a":1, // note` 会留下 `// note` 让
  `JSON.parse` 抛错，而 `parseMenuJsonc` 出错时**静默返回 `[]`**，菜单会变成空卡片（成因见 §8.14）。

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
`~/.config/omarchy/extensions/omarchy-menu.jsonc`（2026-09-19 时 10 项；2026-09-20 起 16 项，多了
6 条 screensaver 屏蔽，§8 第 23 条）合并而来。用户那些都是**覆盖项**，其
`parent` 都指向 default 里的条目；一旦 default 解析失败（读到半截/坏内容时 `parseMenuJsonc` 静默返回
`[]`，而 FileView 是 `printErrors: false`），合并结果只剩这 10 个"孤儿"——根菜单 0 个子项，于是渲染成空
卡片。要点：这是**一次性读取失败**，不是配置损坏；文件再变一次（watcher 触发重读）或重启壳层即可恢复。
2026-09-19 那次正是如此：`omarchy update` 的 pull 正在改写该文件时壳层读到半截内容，之后没有新的文件
事件，就一直空着。

**证据**（临时探针 `console.log("DBGMENU …")`）：正常时 `default loaded items=340` → `merged order=341`；
坏掉时只有 `user loaded items=10` → `merged order=11`（合并后 `items` 是字典，没有 `.length`，探针里
`merged items=undefined` 就是这个原因，不是 bug）。

**根治**（已进 `niri.patch`；`Menu.qml` 2 → 4 个 hunk，整份 patch 30 → 32；2026-09-19 再 +1 到 33，
见 §8 第 21 条）：

- `Menu.qml` 新增 `menuHasRootChildren()`：模型里存在 `parent === "root"` 的条目即判健康（顶层条目在
  `MenuModel.js` 里默认落到 `"root"`，jsonc 不写 `parent` 字段）。
- `rebuildItemsFromSources()` 末尾：若"根菜单没有子项"且**并非两个源都还没加载**（`default=0 且 user=0`
  只说明 FileView 尚未回调），则 1.2s 后重读两个 jsonc，最多 5 次（`menuSourceRetries` 计数，健康时归零）。
  健康路径最多在启动瞬间空判一次（源加载顺序所致，代价是重读两个小文件），之后不再触发。
- 实测：健康 → 菜单 6 项、日志无 QML 报错；截断 → 菜单空但可见重试（4 次）；恢复 → 菜单自己回来。

**兜底**：真遇到空白菜单，先 `omarchy-restart-shell`（§8.7 第 5 步）；`post-update.d/10-niri-repatch`
现在也会在每次上游更新后重启壳层。

---

---

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

---

21. **`Install > Package` / `AUR` 点了没反应、也不报错（2026-09-19 修）**：菜单里只有三条绕过演示终端
    包装器、直接调 `xdg-terminal-exec`（`install.package` / `install.aur` / `remove.package`），而本机
    **没有这个包**（上游 `install/omarchy-base.packages` 里列着它，移植环境缺）→ `bash -lc` 直接
    "command not found"，没有窗口、没有提示，看起来就像菜单坏了。其余 install 项走
    `omarchy-launch-floating-terminal-with-presentation`，那条 niri 分支早有 ghostty 回退，一直是好的。
    修法两层：① `sudo pacman -S xdg-terminal-exec` 补回基础依赖——ghostty 的 desktop entry 是合规的
    （`Categories=System;TerminalEmulator;` + `X-TerminalArgExec=-e` + `X-TerminalArgAppId=--class=`），
    所以 `--app-id=org.omarchy.terminal` 会实打实翻成 ghostty 的 `--class`，**即使 ghostty 带
    `--gtk-single-instance=true`，新窗口也是这个 app-id**（`niri msg windows` 实测）；② 三条 action 加回退，
    `command -v xdg-terminal-exec` 通过才用它、否则走那个 ghostty 包装器（与 §3.2 里三条 `uwsm-app`
    回退同构），这样**没装包的新机器也不会哑**。
    配套 niri 规则：`~/.config/niri/window-rules.kdl` 加 `match app-id=r#"^org\.omarchy\.terminal$"#` →
    `open-floating true` + `0.6 / 0.7` + 与 ghostty 同款 `xray false` 模糊。app-id 一变，ghostty 那条模糊
    规则就不再匹配这条终端，不补模糊的话半透明窗会直接穿帮（这才是必须一起加的原因，不只是为了好看）。
    实测：`xdg-terminal-exec --print-cmd` 展开正确；窗口 `Is floating: yes`、768×532；两个分支各跑一次
    都有结果；`test/shell.d/menu-test.sh` 仍只有那条既有红（它断言 `setup.input` 指上游 `input.lua`，
    而 §8.6 已把它改成 `niri/input.kdl`）。

---

20. **换主题时 `omarchy-theme-set-browser-policy` 因 sudo 要密码失败**（日志成片
    "a password is required"）→ Chromium 系主题色不跟着变；`materal-recolor` 也因此在 2026-09-19
    02:01 失败过一次。下次查上游是否预期 polkit/sudoers 放行，或我们这层该跳过这一步。

---

25. **桌面双击弹窗慢（壁纸/主题切换器"要等会"）（2026-09-20，用户要求）**：入口是 `shell/plugins/background/Background.qml`
    末尾那个 `MouseArea` —— **左键双击**桌面 → `omarchy-theme-bg-switcher`（壁纸），**右键双击** → `omarchy-theme-switcher`
    （主题）；两者都是 `omarchy-menu-images` + Quickshell 的 `omarchy.image-picker` 面板（IPC target `image-selector`）。
    - **根因**：切片 delegate 里的 `Image` 写的是 `asynchronous: false` → **首帧同步解码**最多 33 张 1536×864
      缩略图（`nearby` 半径 16），≈300ms 全压在 GUI 线程：选择器晚出 300ms，**bar 也跟着僵住**（同一线程）。
    - **修法**：只把这一行改成 `asynchronous: true`（附 4 行说明注释），进 `niri.patch`（2026-09-20 当天
      为 **18 文件 / 34 hunk**；当晚电量数字置右后为 **19 文件 / 35 hunk**；2026-09-20 下半场补 `[bar]` 令牌后为
      **20 文件 / 36 hunk**（见 §8 第 28、31 条）。
    - **实测**（`grim -o eDP-1 -t ppm` 每 ~75ms 采一帧定"画面何时出现"，脚本段用 QML `console.log` 时间戳对齐）：
      壁纸路径（75 张）**550ms → 250ms**；主题路径（2 张预览）本来就 ~250ms。**~250ms 是下限**：脚本+IPC ~95ms
      （其中 `qs ipc` 进程启动 ~50ms）+ QML ~68ms（建 75 个 delegate 占 15~25ms）+ 首帧合成 ~90ms。
      异步不伤观感：开窗 320ms 与 1.5s 两张截图逐像素平均差 0.03（差 >8 的像素仅 0.1%），切片不缺图。
    - **冷缓存不用管**：行缓存按**目录 mtime** 失效，换主题后首次双击本要 ~600ms 重建；上游 `omarchy-theme-set`
      结尾已有 `omarchy-theme-switcher --preload` + `omarchy-theme-bg-cache &` 兜底（实测后台重建 553ms、
      之后脚本段 30ms）。`omarchy-theme-bg-set`（换壁纸）不动主题背景目录，不会让缓存失效。
    - 改完必须 `omarchy-restart-shell`：`omarchy-launch-shell` 用 `QS_DISABLE_FILE_WATCHER=1` 起 quickshell，
      **QML 没有热重载**；QML 的 `console.log` 落在 `journalctl -t omarchy-shell`（查时序比截图准）。
    - **2026-09-20 续：用户纠正"不是切换，是打开那个 picker"，于是分层量了一遍** ——
      ① 脚本段（`omarchy-theme-bg-switcher` → `omarchy-menu-images` → IPC open）：`bash -x` + `EPOCHREALTIME`
      跟踪 764 行，**全程 21ms**（rows 缓存 74 行命中、缩略图全在 `~/.cache/omarchy/image-selector`，18M/115 文件）；
      ② 面板窗口进合成器 121ms 冷 / 18ms 热（轮询 `niri msg --json layers`）；
      ③ 可见首帧（条带探针）：**scrim ≈220~280ms、整卡（切片+名字）≈240~400ms**。
      **慢只在冷态**（开机后 / 重启壳层后第一次）：18M 缩略图的页缓存冷读 + 首帧的驱动侧管线/纹理分配。
      **修正一个曾经的误判**：不是"每次壳层启动重编译 shader" —— Qt 有磁盘着色器缓存
      `~/.cache/qtshadercache-x86_64-little_endian-lp64`（44K/3 文件，反复开 picker 不再写 = 命中），
      重启后重付的只是管线创建 + 纹理/FBO 分配，比编译轻。
      **不对称（壁纸比主题更明显的原因）**：主题路径带 `--lazy-thumbnails`，且 `omarchy-theme-set:402` 换完主题会
      `omarchy-theme-switcher --preload` 焐热；壁纸路径（`omarchy-theme-bg-switcher`）**两样都没有** —— 永远冷启动。
    - **2026-09-20 新增：登录后台预热（用户「如果开机做预热可以延迟吗?」→「搞」）**。
      `~/.config/systemd/user/omarchy-picker-warmup.service`（软链进 `graphical-session.target.wants/`，
      照 `omarchy-crash-watch.service` 的式样：`After=/PartOf=graphical-session.target`、
      `ConditionEnvironment=WAYLAND_DISPLAY`、显式 `Environment=OMARCHY_PATH/PATH`）→ 跑
      `~/bin/omarchy-picker-warmup`。**2026-09-20 深夜这两份已收进仓库**
      （`default/systemd/user/omarchy-picker-warmup.service` 用 `%h` 模板化 +
      `port-bin/omarchy-picker-warmup`，`install.sh` 第 4 步安装并链进 `graphical-session.target.wants/`），
      新机器不再靠手装。三个设计点：
      **① 延迟**：`Environment=PICKER_WARMUP_DELAY=45` + `ExecStartPre=/bin/sleep ${PICKER_WARMUP_DELAY}`
      （systemd 支持在命令里做变量展开，实测生效）—— 预热会同步 fan-out `nproc` 个 vipsthumbnail，
      会话刚起来时跟它抢盘不划算；**② 不抢资源**：`Nice=19` + `IOSchedulingClass=idle`；
      **③ 可关**：`toggles/picker-warmup-off` 存在即跳过（沿用 crash-capture 的约定，不用 disable 单元）。
      脚本做三件事：`omarchy-theme-switcher --preload`（顺手重建主题预览软链）、
      `omarchy-menu-images --preload --selected … <主题 backgrounds> <用户 backgrounds/$theme_name>`
      （**参数必须与 `omarchy-theme-bg-switcher` 一字不差**，否则行集不同 = 白热；已核对 md5 键
      `b618dc51…` 同一份 74 行 rows 缓存）、`cat` 一遍 `*.jpg` 把 18M 缩略图拉进页缓存。
      **顺序有讲究**：QML 只保留最后一次 preload 的行集，所以壁纸那条必须放最后。
      **实测**（`systemctl --user start --no-block`）：45.16s 后执行、`Result=success`、
      三段 `theme 113ms / background 98ms / thumbnails 10ms`；`touch toggles/picker-warmup-off` 后
      `ConditionResult=no` 直接跳过。**它省不掉首帧渲染**（`preload` 只装数据不画，`card.visible=false`
      时委托不渲染，且真开一帧会抢 `keyboardFocus: Exclusive`），所以预热后的可见首帧在我这边
      与预热前同量级（177~280ms scrim / 240~400ms 整卡，噪声级别）—— 预热买的是**冷态**那几百 ms 的
      页缓存与脚本重建，**热态无感属正常**。
    - **测量备忘（重要，别再走弯路）**：`grim` 全屏一帧 ≈1.7s（2560×1600 → 逻辑 1280×800 的 CPU 缩放），
      **完全不够用**；`grim -g "x,y 8x8"` ≈31ms/帧、`grim -g "0,396 1280x8"` ≈57ms/帧（起几条参考列做亮度时间线）
      才是可用的时序探针。另外 `grim -g` 收**逻辑**坐标、输出却是物理像素（scale 2 → 2 倍尺寸）。
    - 回退：`git checkout -- shell/plugins/image-picker/ImagePicker.qml`，或先还原
      `niri.patch.bak-20260920-prepickerperf` 再 `omarchy-niri-repatch`；预热另回退
      `systemctl --user disable --now omarchy-picker-warmup` + 删 `~/.config/systemd/user/omarchy-picker-warmup.service`
      与 `graphical-session.target.wants/` 里的软链 + 删 `~/bin/omarchy-picker-warmup`（全在用户级，不碰 root）。

---

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
