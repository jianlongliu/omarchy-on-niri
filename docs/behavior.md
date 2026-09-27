# 功能调整 — Omarchy on niri 卷（behavior）

> 文档只有一份：本文件（`docs/behavior.md`）。
> 本卷 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽出（模块化拆分），**编号一律沿用原号** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，原处留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `docs/omarchy-on-niri-port.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录

- **功能覆盖账：还剩什么没实现（2026-09-24 清点）** —— 见本卷末尾同名一节（**不占全局编号**）：口径、8 → 6 条的数字、未实现/用户遗弃/环境不成立三张清单、三项待拍板


- 3. **快捷键重映射已按用户方案落地**（2026-08-24）：tiling 改成方向键方案、移除 vim 键，
- 24. **按键表去重 + 应用启动键统一走 Omarchy 包装器（2026-09-19/20，用户要求）**：用户原话"好多都重复"，
- 26. **按键里不能写开窗属性（`open-floating` 放 bind 里 = 整份配置被拒）（2026-09-20，用户问「Super+E 的 nautilus、
- 9. **system 开关已修并统一标准化（2026-08-25）**：菜单 `system.logout/reboot/shutdown` 走 `omarchy-system-*`，
- 11. **电池面板 POWER PROFILE 区为空（2026-08-25 已修）**：系统电源后端是 **TLP**（`tlp` + `tlp-pd`
- 15. **brightnessctl 授权安装 + 背光权限（2026-08-25）**：媒体键 OSD（§5.3）依赖
- 23. **screensaver 关掉并屏蔽（2026-09-20，用户要求「很烦，屏蔽和禁用他」）**：本机
- 27. **菜单屏蔽 5 项（unlock / web app / preinstalls / channel / config.plymouth+shell）（2026-09-22，用户要求）**：这 6 个 id
- 28. **Update 菜单改造：`update.omarchy` → "Pacman"，新增 `update.aur` / `update.plugins`（2026-09-22，用户要求）**：同一份 override
- 8.17 输入源徽章（`ronald.input-sources`）+ fcitx5 双源前提（2026-09-19）
- 12. **Super+K 键位菜单只剩 2 条（第二次复发，2026-08-25 晚已修）**：同日早些时候修过一次
- 8.6 A 层：菜单指向 niri 真配置，Hyprland 层降级
- 8.14 菜单空白（"Nothing here yet"）的成因与自愈（2026-09-19）
- 14. **菜单 Apps 列表启动全部失灵（2026-08-27 已修）**：菜单 "Apps" provider 经
- 21. **`Install > Package` / `AUR` 点了没反应、也不报错（2026-09-19 修）**：菜单里只有三条绕过演示终端
- 20. **换主题时 `omarchy-theme-set-browser-policy` 因 sudo 要密码失败**（日志成片
- 25. **桌面双击弹窗慢（壁纸/主题切换器"要等会"）（2026-09-20，用户要求）**：入口是 `shell/plugins/background/Background.qml`
- 19. **耗电/续航专项（2026-09-19 测过一轮，下次接着做）**：表现为"感觉慢 + 续航差"。已排除的
- 35. **Herdr 键位：`Super+Ctrl+Return` 必须经终端启动（裸 `herdr` 在 niri 下没有 tty，必死）（2026-09-24）**：`binds.kdl` 里那行原本是裸调 `herdr`
- 38. **电池面板加 CHARGE LIMIT 档位切换（充电阈值可写）（2026-09-26）**：两档 Protect 75–80 / Full 95–100，点击走 `pkexec tlp setcharge`（规则 `/etc/polkit-1/rules.d/49-tlp.rules`）；**真根因＝`omarchy-battery-status` 优先信 UPower 而 UPower 缓存阈值不重读 ⇒ 已改成 sysfs 优先**；`setcharge` 只写运行时 ⇒ Full 一次性
- 39. **Setup > Security 新增 "Paru (AUR)" 开关（paru 的执行位＝本机 AUR 总开关，2026-09-27）**：新命令 `port-bin/omarchy-setup-security-paru` 一身两半（用户半身念警告 + `gum confirm`，root 半身 `chmod ±x /usr/bin/paru`）+ `/usr/bin` root 属主副本 + polkit 规则 `49-paru.rules`（**没放行 chmod**）；菜单侧全在扩展文件（**零补丁**），并给 `install.aur`/`remove.package`/`update.aur` 加 `when` 守卫；⚠ **覆盖默认项必须整条复述**（解析器把每个字段补成默认值 ⇒ 只写 `when` 会把 `action` 冲空、条目静默消失）
- 40. **ante 进菜单的"默认 agent"列表（2026-09-27）**：菜单那一行在扩展文件（零补丁），补丁落在命令侧两处上游脚本 —— `bin/omarchy-default-agent` 新增 `agent_self_managed` 分支（ante 不能被 mise 装、自己 `ante update` 自升级）+ `bin/omarchy-agent` 新增 `ante --yolo`（它的 `--prompt` 是 headless 语义，故不转发）⇒ 补丁 24 → **26 文件 / 77 hunk**、md5 `22dd2334…`
- 41. **vantage 退休并公开归档（2026-09-27）**：自写 TUI `~/Projects/vantage` 的四个功能全部搬进菜单/面板后，用户要求"推到远程仓库、标记归档、二进制发 release、先脱敏"⇒ `github.com/jianlongliu/vantage`（**PUBLIC + 已归档**），release `v2026.8.19` 挂由该 tag 源码构建的 `vantage-x86_64-linux-gnu` + `.sha256`；README 精简成退休说明、`.gitignore` 照抄本仓库基线、commit 用 noreply 身份；⚠ **归档前必须先建 release**（归档后只读）、`gh release create` 里的 `<file>#<name>` 那个 `#` 是 label 不是文件名

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
      备份 `~/.local/state/backups/.config/niri/binds.kdl.bak-dedup-20260920-043728`；`niri validate` 通过、生效行无重复键。
    - **终端类一律走 `omarchy-launch-terminal`**（与菜单同一条路、自带"跟随当前终端 cwd"），不裸调
      `xdg-terminal-exec`——这条依赖垫片在位（§8 第 22 条）。`Mod+Z` 的实测恰好把垫片 v1.0 的 `setsid`
      坑顶了出来（`systemd-run` 路径静默死，见 §8 第 22 条 v1.1），修完 3 秒出 Zen 窗口。
    - ~~遗留未定~~ **2026-09-21 用户定案**：只留 `Mod+Tab`，`Mod+O` 删掉（同一个 `toggle-overview` 不再绑两次）。
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
    - 回退：还原 `~/.local/state/backups/.config/niri/binds.kdl.bak-20260920-floatbinds` 与
      `~/.local/state/backups/.config/niri/window-rules.kdl.bak-20260920-floatbinds`，再 `niri validate`。
    - **后补（2026-09-22）：第三条同形状的规则 = `^org\.omarchy\.about$`**（About 窗口 / fastfetch TUI）。
      跟 `float-tui` 那条一个道理：app-id 不是 `com.mitchellh.ghostty`，Ghostty 的磨砂块不覆盖它，
      所以要**照抄一份磨砂块**；另外它还要 `open-floating true` + 固定 `920x540`（上游这些是 Hyprland 全局 blur 与
      `system.lua` 白给的）。起因是用户「我原汁原味的blur咋没了?」——**"fastfetch 的 blur"指的就是这块 About 面板**。
      根因、尺寸推算、像素级实测（透光低频相关 0.844 / 高频 1/20）与两个操作坑（`reload-config` 子命令不存在、
      `close-window` 关不掉 TUI）见 `docs/visual.md` §8.8 第 34 条；回退
      `~/.local/state/backups/.config/niri/window-rules.kdl.bak-20260922-aboutblur`。

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
     - **更正（2026-09-24 实测）：真正决定档位的是壳层记忆，不是 `TLP_PROFILE_AC/BAT`。** 电源事件其实是
       **两路并发**——TLP 核心那路（`/usr/lib/udev/rules.d/85-tlp.rules` → `tlp auto`，按 `TLP_PROFILE_AC/BAT`
       算）和壳层那路（`plugins/services/battery/Service.qml` 的
       `UPower.onOnBatteryChanged → applyPowerProfile()` → 经本适配脚本把**记忆档位**写进 D-Bus）。
       实测壳层那次随后覆盖 TLP 那次 ⇒ `TLP_PROFILE_AC/BAT` 在本机**等于空转**（改 `/etc/tlp.conf` 看不到效果
       时就是它）。记忆档位在 `~/.local/state/omarchy/powerprofiles/{ac,battery}`（纯文本 profile 名，
       **跨重启保留**，与上面"不持久化"一句指的适配脚本自身不写 TLP 配置并不矛盾）。要改插电/电池各用哪档：
       `omarchy-powerprofiles-set {ac,battery} <profile>`。
     - **power-saver 联动屏幕亮度（2026-09-24 加，在适配脚本内）**：切到 power-saver 时把面板压到 10%
       （先用 `omarchy-brightness-display` 读当前值，**仅当 >10%** 才把原值存进
       `…/powerprofiles/brightness`）；离开 power-saver 时**只在亮度仍等于那个 10%** 才恢复原值，
       用户手动改过则尊重用户并清档。目标百分比三级优先：
       `$OMARCHY_POWERPROFILES_SAVER_BRIGHTNESS` → `…/powerprofiles/saver-brightness` → `10`
       （**要长期改就写文件**：`echo 25 > ~/.local/state/omarchy/powerprofiles/saver-brightness`，
       白天/晚上想要不同值时改这里即可，下次套档生效）；
       走 `--no-osd`（拔插电不弹 OSD），只操作背光（`omarchy-brightness-display` 的 Apple/DDC 外接屏分支
       不参与）。
     - **`/etc/tlp.conf` 的改动 + "两档到底差什么"（2026-09-24 实测）**：`CPU_BOOST_ON_SAV` **0 → 1**
       （用户要求"powersave 也带上睿频"；root 改，备份与原件同目录 `/etc/tlp.conf.bak-20260924`）。
       A/B 验法：`tlp power-saver` 后 `no_turbo=0`；`tlp power-saver -- CPU_BOOST_ON_SAV=0` 后 `no_turbo=1`
       ⇒ 证明旋钮真在起作用（用 in-command config 临时覆盖，**别改文件**）。切档后直读 sysfs 的结论：
       **balanced vs power-saver 只差 2 项** —— `platform_profile` balanced→low-power、`EPP`
       balance_power→power；**其余全同**：`no_turbo`、`max_perf_pct`（两边都 **80**，因 `CPU_MAX_PERF_ON_SAV`
       仍被注释 ⇒ 继承 `CPU_MAX_PERF_ON_BAT=80`）、`min_perf_pct=8`、governor=powersave、hwp_dynamic_boost、
       Wi-Fi 省电、磁盘 APM、PCI/USB runtime PM、SATA LPM、声卡 power_save。
       **本机空转项**（改了没用，排查时先排除）：`PCIE_ASPM_ON_BAT/SAV`（TLP 写
       `/sys/module/pcie_aspm/parameters/policy`，**内核拒写**——root 直接 echo 也 `rc=1`，active 恒为
       `[default]`，TLP 源码自称 `set_pcie_aspm.disabled_by_kernel`）；`AMDGPU_ABM_LEVEL` /
       `RADEON_DPM_PERF_LEVEL`（本机无 AMD GPU）。
       ⚠ 两个坑：`tlp ac|bat` 会写 `/run/tlp/manual_mode` **盖住自动切换**（别拿它收尾验证，要干净就用
       `tlp balanced|power-saver|performance`，它会 `clear_manual_mode`）；`/etc/tlp.d/*.conf`
       **覆盖不了** `/etc/tlp.conf`（读序 `defaults.conf` → `tlp.d/*.conf` → `tlp.conf` 最后读、优先级最高），
       要改就得动 `/etc/tlp.conf` 本体。

---

15. **brightnessctl 授权安装 + 背光权限（2026-08-25）**：媒体键 OSD（§5.3）依赖
    `brightnessctl` 调背光，但该工具**未装**（这是背光键不生效的根因，非权限问题）。
    已用户授权装系统级：`pkexec pacman -S brightnessctl` + 新建
    `/etc/udev/rules.d/90-backlight.rules`（`SUBSYSTEM=="backlight" GROUP="video" MODE="0664"`）+
    `usermod -aG video <user>` + 对既有 `intel_backlight` 节点手动 `chgrp video`/`chmod 0664`
    （udev `trigger` 只发 `change`、不重挂 group/mode，故手动兜底直到下次冷插拔）。
    验证：`niri msg action spawn -- brightnessctl --class=backlight set +10%` 改变 76→126→恢复；
    无需重登即生效。**注意**：这条打破了 §1 的"不装系统包"约束，属用户明确授权的唯一例外；
    `echo > $brightness` 对实验账户仍 EACCES，brightnessctl 走非 setuid 路径。回滚：
    删 udev 规则 + `usermod -G` 挪出 video + 卸 brightnessctl。

---

23. **screensaver 关掉并屏蔽（2026-09-20，用户要求「很烦，屏蔽和禁用他」）**：本机
    `~/.config/omarchy/shell.json` 是 `idle = {lock: 300, screensaver: 150}`（**这是当时的值；现况见本节末尾那条**），所以空闲 2.5 分钟先弹
    screensaver（在终端里跑 ASCII art）、5 分钟才锁屏。处置分两层，**都走官方机制、不碰 omarchy 本体**：
    - **禁用（本体）**：官方开关 `~/.local/state/omarchy/toggles/screensaver-off`（`omarchy-toggle
      screensaver-off` 打开）。`bin/omarchy-launch-screensaver` 开头就是
      `omarchy-toggle-enabled screensaver-off && [[ $1 != force ]] && exit 1`，于是 idle 计时器这条路
      直接死掉。实测：`omarchy-launch-screensaver` → exit 1、无新窗口（`niri msg windows` 前后一致）；
      当时正在跑的那个实例（ghostty `--class=org.omarchy.screensaver`）已杀掉。
    - **屏蔽（入口）**：用户 override 加 6 条 `when:"false"` —— `system.screensaver`（System 菜单）、
      `trigger.toggle.screensaver`（Trigger→Toggle）、`style.screensaver` 及其 `.text`/`.image`/`.default`
      （Style→Screensaver 那组 branding）。这几条是**唯独带 `force`、能绕过上面那个开关**的入口，
      不屏蔽就等于开关形同虚设。备份 `~/.local/state/backups/.config/omarchy/extensions/omarchy-menu.jsonc.bak-20260920-prescreensaver`。
    - **别去动 `idle.screensaver`**：计时是 `min(screensaver, lock)` + 差值的两段式，把它调成等于 `lock`
      会让 screensaver 在锁屏那一刻抢跑（`screensaverDelay = 0`），比现在更糟。停掉的功能不需要改超时。
    - **（2026-09-24 补）这条闲置腿现在的职责 = 不插电时的「到点锁屏」，顺带记三条现况**：
      ① `idle.lock` 现在是 **1800**（不是上面写的 300）；② `idle.screensaver` 当天从 150 改成 **300**
      （改动前备份 `~/.local/state/backups/.config/omarchy/shell.json.bak-20260924-idle300`；本机
      `~/.config/omarchy/shell.json` 与仓库 `local-config/omarchy/shell.json` 两份同步改、逐字节一致）；
      ③ 屏保被禁用 ⇒ 300 秒到 1800 秒之间原本屏幕一直亮着，而 10% 亮度下那块面板仍占 ~2 W 量级。
      **用户规格**（第一版"150 秒自己灭屏"被他否掉：「不好吧？我就想了一会屏幕就灭了」）：**不插电 + 非全屏 +
      没在播放视频** ⇒ 闲置到点**先锁屏**，灭屏交给锁本身（`jianlongliu.split-lock` 的 `idleBlankTimer`，5 秒）；
      **插电** ⇒ 这条腿完全不干预，交回 `idle.lock`（30 分钟）。实现 = 垫片
      `port-bin/omarchy-launch-screensaver`（`install -m 0755` → `~/bin`，`bash -lc` 下 PATH-first 命中）：
      非 `force` 时不再跑 ASCII 屏保，而是「已锁屏→退；插电→退；全屏（窗口尺寸 == 输出逻辑尺寸）→退；
      否则 `exec omarchy-system-lock`」。`force` 仍转发上游那份；播放视频由
      `IdleMonitor { respectInhibitors: true }` 兜住（压根不进空闲）。
      **唯一的计时值改动就是 `screensaver=300`**（与 `lock` 不等 ⇒ 不触发上面那个"抢跑"坑）。
      回退：`rm ~/bin/omarchy-launch-screensaver`（回落上游 = 回到"什么都不做"）。
      四分支 2026-09-24 用一个 `/tmp` 副本（stub 掉 `omarchy-system-lock` 与 `omarchy-shell`）实测过：
      电池+非全屏→锁、插电→不锁、已锁→不锁、全屏→不锁（`window_size` `1280x800` 命中输出逻辑尺寸）。
    - 回退：`omarchy-toggle screensaver-off off` + 还原上面那个备份。触发点已全局扫过：没有 systemd 单元、
      没有 niri 绑定（`Indicators` 里的 StayAwake 是手动「别睡」开关，与此无关）。
    - 同一次还修掉这份 override 文件里 **5 处超长 `\u` 转义**（2 处历史遗留 + 3 处新增），规则见 §8.6
      末尾那两条 override 注意。

---

27. **菜单屏蔽 5 项：`style.unlock` / `install.webapp` / `install.preinstalls` / `update.channel` / `update.config.{plymouth,shell}`（2026-09-22，用户要求）**：
    用户点名"style unlock 屏蔽、install 屏蔽 web app + pre-installs、update 屏蔽 channel + config"。评估后**只屏坏掉的**：
    前四条屏蔽是因为**本机要么没有对应功能、要么动作链在本机必失败**（不是审美取舍）；`update.config` 只屏
    `plymouth`（必失败）与 `shell`（会盖掉本机调优版），**保留还在用的 `update.config.hyprland`（"Niri Theme" →
    `omarchy-niri-apply-theme`，见 §8.6）和 `tmux`**。逐条根因：
    - `style.unlock`：本机**没有 LUKS**（`lsblk -o NAME,TYPE,FSTYPE,MOUNTPOINT` 无 `crypt`、`/etc/crypttab` 空）
      ⇒ 它主题化的是不存在的磁盘解锁屏；且 `omarchy-plymouth-set-by-theme` → `omarchy-plymouth-set` 的 root 事务
      要求 `$OMARCHY_PATH` 归 root 或由 `/etc/omarchy.conf`（dev-link 授权）指定，而本机 `OMARCHY_PATH=~/.local/share/omarchy`
      是**用户所有的 git checkout**、`/etc/omarchy.conf` **不存在** ⇒ `validate_trusted_configuration_file` 断言失败、
      拒绝发布（读代码结论，未实跑——要 sudo）；末尾还会 `plymouth-set-default-theme omarchy` + `mkinitcpio -P`
      重建 initramfs（＝ §11.27 已搁置的启动链工作）。
    - `install.webapp`：脚本能造出 `~/.local/share/applications/<Name>.desktop`，但 Exec 是 `omarchy-launch-webapp "<url>"`；
      它读 `xdg-settings get default-web-browser` = `userapp-Firefox-W32OS3.desktop`（Zen 的 userapp 条目）**不在白名单**
      （chrome/brave/edge/opera/vivaldi/helium）⇒ 回落 `chromium.desktop`，**本机没装 chromium**（`pacman -Q chromium` 无、
      `/usr/share/applications/chromium.desktop` 无）⇒ 命令解析为空串（干跑验证过），最终只执行 `setsid uwsm-app -- --app=<url>`
      ⇒ **造出来的启动器点了没反应**。⚠ 同一根因还挂着 **Learn 里 5 条**（`learn.omarchy/hyprland/arch/neovim/bash` 全是
      `omarchy-launch-webapp`）。唯一修法：把默认浏览器设成 `google-chrome.desktop`（Chrome 已装）⇒ 一处修活 6+ 条。
      本轮按用户决定**只记档：不动浏览器默认值，也不屏蔽 Learn**。
    - `install.preinstalls`：本机没装 omarchy 包、没配 Omarchy 仓库（`/etc/pacman.conf` 只有 core/extra/multilib/archlinuxcn）
      ⇒ 包表里的 `aether`/`cliamp`/`omacut`/`omacalc`/`omawrite` **任何仓库都查不到** ⇒ `omarchy-pkg-add` 整笔事务失败、
      脚本 exit 1（"Preinstalls are still marked as removed"）。另注：它本来也**显示成置灰 ✓（像已装）**——`disabled`
      守卫是 `[[ ! -f ~/.local/state/omarchy/preinstalls-removed ]]`，本机没这个 marker ⇒ 守卫成立。
    - `update.channel`：**最危险的一条**。`stable|rc|edge` 走 `omarchy-refresh-pacman <channel>` + `omarchy-update-pacman -S … omarchy{,-settings}`
      ⇒ **把 Omarchy 自家仓库写进 pacman 配置**；`dev` 更狠 —— `git clone github.com/omacom/omarchy ~/omarchy` + `omarchy-dev-link`
      （写 `/etc/omarchy.conf`、**改 `OMARCHY_PATH`**）+ 标 reboot-required。本机 `~/bin/omarchy-update` 垫片的注释早写明
      "本机没装 omarchy 包、没配 Omarchy 自家仓库，上游流程会卡在 omarchy-update-keyring"。另注 `omarchy-channel-current`
      在本机报 `dev` ⇒ Dev 那行一直挂着个毫无意义的 ✓。
    - `update.config.plymouth`：`omarchy-refresh-plymouth` → `omarchy-plymouth-set --refresh-default`，同 `style.unlock` 那套
      root 事务（且 `/usr/share/plymouth/themes/omarchy` 根本不存在）⇒ 必拒。
    - `update.config.shell`：`omarchy-refresh-shell` → `omarchy-refresh-config omarchy/shell.json`（从 `$OMARCHY_PATH/config/` 拷、先备份你的版本）
      + `omarchy-bar defaults` + `omarchy-restart-shell` ⇒ 会拿 `$OMARCHY_PATH`（本机是 **Sep-19 那份拷贝**，不是活的 checkout）里
      1249 B 的 shell.json 盖掉 `~/.config/omarchy/shell.json` 的 1789 B 本机调优版（`bar.id`、`xray`、字号…）。要重置时走 CLI 仍可。
    - 落地：**只改用户层 override** `~/.config/omarchy/extensions/omarchy-menu.jsonc`（＝ 仓库
      `local-config/omarchy/extensions/omarchy-menu.jsonc`，两边逐字节相同，`scripts/local-files-sync.sh` 可校验）：6 个 id 各一条
      `"when":"false"` + **从默认项复制的 label/icon**（§8.6 那条 override 规矩），同一 id 只写一次、不写行内注释
      （`stripJsonc` 只删整行注释）。备份 `~/.local/state/backups/.config/omarchy/extensions/.omarchy-menu.jsonc.bak-20260922-menuhides`。
      壳层热重载，**不需要 `omarchy-restart-shell`**。
    - 验证（实测）：`omarchy menu refresh` → `ok`；逐屏抓图 + OCR 核对 —— Style 里 **Unlock 消失**、Update 里 **Channel 消失**
      （Omarchy / Config / Process / Hardware / Firmware / Password / Timezone / Time 仍在 ⇒ Config 保留）、Install 里 **Web App 消失**；
      Install 另做 A/B（临时还原备份 → 抓图 → 还原）：A 有 "Web App"、B 没有 ⇒ 确认是这份文件在驱动渲染（不是缓存）。
      离线解析：用 `MenuModel.js` 的 `stripJsonc` 两条正则剥注释/尾逗号后 `json.loads` 通过，默认 340 + 用户 22 项合并无缺。
    - **本轮按用户决定没做**（留档）：① Remove 侧的 `remove.preinstalls` **仍然可见可点**，守卫同样只看那个 marker ⇒ 点了会跑
      `omarchy-webapp-remove-all` + `omarchy-tui-remove-all` + `rm ~/.local/bin/{codex,claude,agy,copilot,gh,opencode,pi,omp,ori,grok,crush,…}`
      + `omarchy-pkg-drop … xournalpp … moonlight-qt …`（本机装着 xournalpp 与 moonlight-qt ⇒ 会真被卸掉）。**只造 marker 会把
      `install.preinstalls` 反过来点亮**，要处理就给它也加一条 `when:"false"`。② Learn 那 5 条死链（见上）。
    - 回退：把上面那个备份拷回 `~/.config/omarchy/extensions/omarchy-menu.jsonc`，再 `omarchy menu refresh`（热生效）。

---

28. **Update 菜单改造：`update.omarchy` → "Pacman"，新增 `update.aur` / `update.plugins`（2026-09-22，用户要求）**：
    用户原话"omarchy menu update 把 omarchy 改 pacman，增加 aur (paru -Sua) 和 plugin (omarchy plugin update) 更新"。
    改的还是 §8 第 27 条那份用户层 override（同一个文件、同一段注释区）：
    - `update.omarchy`：**只改显示** —— `label` → `Pacman`、图标换成 Arch 那枚（从默认项 `install.package` 抄）、
      **`iconFont` 显式清空**。清它是有原因的：`mergeMenuSources` 是**逐字段覆盖**，不清就继续拿默认项的
      `iconFont:"omarchy"` 去渲染这枚普通 Nerd Font 字形；置空后 `Menu.qml` 的
      `font.family: row.iconFont.length > 0 ? row.iconFont : root.fontFamily` 回落到菜单字体。
      **动作保持原样**（`omarchy-launch-floating-terminal-with-presentation omarchy-update`）⇒ 裸调 `omarchy-update`
      落到 `~/bin/omarchy-update` 垫片 = `sudo pacman -Syu` + 一句 AUR 提示，与 bar 的 `system-update` 部件同一条路。
      想更直白就是把 action 换成 `'sudo pacman -Syu'`。
    - `update.aur`：`omarchy-launch-floating-terminal-with-presentation 'paru -Sua'`（本机 paru v2.1.0 在位；
      AUR 另有 `~/bin/yay` 垫片，此处按用户要求用 paru）。
    - `update.plugins`：`omarchy-launch-floating-terminal-with-presentation 'omarchy plugin update'`（= `bin/omarchy-plugin-update`）。
      **它会动真格**：只更新 `~/.config/omarchy/plugins/` 下的 git 克隆（本机 5 个：`charlieras262.floating-bar`、
      `io.github.claudsondouglas.arcdock`、`jrmmhm.pocket`、`meviusisback.ai-subs`、`ronald.input-sources`），其中
      **3 个带本机 patch**（`niri-port/plugin-patches/` 里的 floating-bar / ai-subs / input-sources）⇒ 上游改了同一文件时
      `git merge --ff-only` 会报 "you have local changes" 并跳过、**不会**自动重放 patch，需要手工处理；更新成功后会
      `omarchy-shell shell rescanPlugins`。它拒绝非交互运行（无 TTY 时报 "refusing to continue without confirmation"），
      所以必须走终端——这条正是。
    - **顺序限制（实测）**：新增 id 按 `mergeMenuSources` 规则**追加在 Update 子菜单末尾**（"Time" 之后），
      override 改不了位置；要把它俩挪到 Pacman 下面只能改默认文件（走 `niri.patch`）。
    - 演示终端链路实测（2026-09-22）：`omarchy-launch-floating-terminal-with-presentation 'sleep 6'` 起出窗口
      （`niri msg windows` 见 Title `Omarchy`、App ID `org.omarchy.terminal`）；在窗口里 `: <>/dev/tty` 成功、`tty` = `/dev/pts/2`、
      `sudo -n true` 报 "a password is required" ⇒ **有控制终端、sudo 能弹密码框**（`sudo pacman -Syu` / `paru -Sua` 能正常要密码）。
      本机无免密 sudo，故**不实跑更新本身**（只验到"窗口起得来、终端在、能要密码"）。
    - 验证：`omarchy menu refresh` → `ok`；`omarchy menu summon update` + 抓图 OCR ⇒ `Pacman / Config / Process / Hardware /
      Firmware / Password / Timezone / Time / AUR / Plugins`（Channel 已按 §8 第 27 条隐藏）；离线 `stripJsonc` + `json.loads`
      通过、合并后 26 项、`update.omarchy.iconFont == ""` 且 action 与默认项逐字符相同。
    - **同轮续作（用户"你继续"）：Update 面板逐行体检** —— 只查出**一条**与 §8 第 27 条同性质的死行，已一并隐藏：
      `update.password.drive`（**Drive Encryption**）脚本第一句就是 `blkid -t TYPE=crypto_LUKS`，本机命中 0 个
      （无 LUKS，理由同 style.unlock）⇒ 必走 else 打印 "No encrypted drives available." 后 `exit 1`。
      其余各行体检结论（一律**不动**，只留档）：
      - `update.firmware` 本机没装 fwupd（`fwupdmgr` 缺失）⇒ 脚本会先 `omarchy-pkg-add fwupd`（extra 里有，装得上），
        之后因 `/sys/firmware/efi` 与 `/usr/lib/fwupd/efi/fwupdx64.efi` 都在，会 `install -D` 到**硬编码**的
        `/boot/EFI/arch/fwupdx64.efi`——本机 ESP 是 `/boot/EFI/{Boot,Linux,systemd}`、没有 `arch` 目录，`install -D`
        会把 `/boot/EFI/arch/` 现造出来（无害的野文件）。真正干活的 `fwupdmgr refresh --force` + `sudo fwupdmgr update`
        本身可用，笔记本固件更新也是真有用的 ⇒ 保留可见，只记这个瑕疵（要治就得自己重写 action，绕开那段 EFI 暂存）。
      - `update.time` `systemd-timesyncd` 本机 enabled + active ⇒ 可用。
      - `update.hardware.*` audio = `systemctl --user restart pipewire` 系；wifi/bluetooth = `rfkill` + `nmcli`；
        trackpad 要 `/sys/bus/i2c/drivers/i2c_hid_acpi/i2c-*`（本机有 `i2c-ELAN0672:00`）⇒ 三条都可用。
      - `update.themes`（Extra Themes）的守卫 `omarchy-theme-extras` 本机 exit 1 ⇒ 菜单里本来就自动不渲染。
      - `update.process`（只剩 Shell）/ `update.password.user` / `update.timezone` 照旧可用。
    - **验证法升级（本轮最有复用价值的一条）**：`~/.local/share/omarchy/shell/plugins/menu/MenuModel.js` 是**纯 JS 且
      `module.exports` 全导出**（无 QML 依赖），所以菜单可以用 `node` 在**无头**下按生产逻辑渲染：`parseMenuJsonc` 读两份
      jsonc → `mergeMenuSources` 合并 → `guardScript(items)` 生成的那段 bash 真跑一遍拿到所有 `when/checked/disabled` 结果
      → `isVisible` + `labelFor` + `displayRow` 逐行算出来。这比抓图＋OCR 硬得多（不受窗口遮挡、不受面板位置影响）。
      这个探针已收进仓库：**`scripts/menu-model-render.js`**（`node scripts/menu-model-render.js <parent-id> [--default-only]`，
      无第三方依赖，跑的是机器上那份 `MenuModel.js`，所以换机器仍有效）；实测输出：
      `update` 10 行（Pacman/Config/Process/Hardware/Firmware/Password/Timezone/Time/AUR/Plugins，`update.omarchy` 的
      `iconFont=""` 已生效）、`update.password` **1 行（只剩 User）**、`update.config` 2 行（Niri Theme/Tmux）、
      `style` 6 行（无 Unlock/Screensaver）、`install` 12 行（无 Web App/Preinstalls）、`install.preinstalls` 0 行、
      `system` 5 行（无 Screensaver）。**A/B 也用它做**：`--default-only`（假装没有 override）时 `update.password` 立刻变回
      **2 行（Drive Encryption + User）**，这就是"隐藏确实由这份 override 驱动"的干净证据（无需改动文件）。
      注意 `childCount` **不过滤隐藏项**，要对"看得见的子项数"得自己按 `isVisible` 数（探针里已这么写）。
      ⚠ 抓图路线的坑：菜单是图层表面、会盖住终端，但**子菜单面板小、位置不固定**，OCR 很容易把终端里的文字当成菜单内容
      （本轮就误读过一次）；要抓图就得先把终端窗口挪走，而"挪窗口/切空 workspace"在本机 dynamic workspace 下也不可靠。
    - 回退：`~/.local/state/backups/.config/omarchy/extensions/.omarchy-menu.jsonc.bak-20260922-updatemenu`（改造前）或
      `.bak-20260922-updaudit`（体检前）覆盖回去 + `omarchy menu refresh`。

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
第一个上下文是英文。备份原为 `~/.config/fcitx5/profile.bak-0428`（加源前）、`~/.config/fcitx5/config.bak-0435`
（改共享状态前）—— **这两份 2026-09-21 复核已不在机上**，现存同类备份只有
`~/.local/state/backups/.config/fcitx5/profile.bak-20260919-215213-defaultim`（改默认输入法前）与 `~/.local/state/backups/.config/fcitx5/conf/classicui.conf.bak-*`。一键回到单源（徽章随之隐藏）：

```
busctl --user call org.fcitx.Fcitx5 /controller org.fcitx.Fcitx.Controller1 \
  SetInputMethodGroupInfo "ssa(ss)" "Default" "us" 1 "rime" ""
```

**隐藏自带的键盘布局部件（2026-09-19）**：装好插件后 bar 上有两个"当前输入法/布局"标记——插件徽章，以及 Omarchy
自带的 `omarchy.keyboard-layout`（时钟右边那个 `EN`）。后者只是 xkb 布局指示（数据来自垫片的 `hyprctl -j devices`），
在插件徽章存在时纯属重复，于是把 `{"id":"omarchy.keyboard-layout"}` 从 `~/.config/omarchy/shell.json` 的
`layout.center` 摘掉（`shell.json` 是用户层、热重载、抗 `omarchy update`；**不要**去动 `$OMARCHY_PATH` 里的部件本体）。
A/B 实测：摘掉后 bar 只有逻辑 x 706..742（宽 36）这一块像素变化——正是那个 `EN`，其余逐像素不动；
备份写的是 `~/.config/omarchy/niri-port/backups/shell.json.bak-20260919-043957-pre-keyboard-layout`
（**该 `backups/` 目录 2026-09-21 已不在机上**，回退就近用 `~/.local/state/backups/.config/omarchy/shell.json.bak-*` 或 `git log`），想加回来就把
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
   clients/devices 无回归；备份 `~/.local/state/backups/bin/hyprctl.bak-20260825-211843`。

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
    02:01 失败过一次。**根因（2026-09-24 查清）：两半都缺** ——
    ① 脚本 `require_root` 最终 `exec sudo|pkexec /usr/bin/omarchy-theme-set-browser-policy`，
    而本机**根本没有 `/usr/bin/omarchy-*`**（`/usr/bin` 里 omarchy 条目数 = 0）⇒ 路径不存在，怎么提权都失败；
    ② `/etc/sudoers.d/omarchy-theme-browser`（上游那条 NOPASSWD 规则）本机**没装**，
    而本机没有 polkit agent UI ⇒ 退到 `pkexec` 也没法弹认证框。
    **修法（2026-09-24 已落地，两条 root 动作）**：
    - `install -m 0755 -o root -g root $OMARCHY_PATH/bin/omarchy-theme-set-browser-policy /usr/bin/omarchy-theme-set-browser-policy`
      —— **root 属主的副本，不是指回用户可写树的软链**：规则放行的那个路径一旦能被普通用户改写，
      就等于给了无密码 root（上游脚本自己的注释也在防这件事，其 dev-link 场景靠 `PATH` 固定兜）。
    - `install -m 0440 -o root -g root $OMARCHY_PATH/etc/sudoers.d/omarchy-theme-browser /etc/sudoers.d/omarchy-theme-browser`
      —— 规则逐字照抄上游（`%wheel … NOPASSWD: <该路径> [0-9a-f]×6`），装前 `visudo -cf` 验过 parsed OK。
    **验证**：`sudo -n -l -l /usr/bin/omarchy-theme-set-browser-policy aabbcc` 出
    `Options: !authenticate` + `Matched: …`；以**普通用户**跑 `omarchy-theme-set-browser-policy 7aa2f7`，
    经 sudo 落地的 `color.json` 内容 `{"BrowserThemeColor": "#7aa2f7", "BrowserColorScheme": "device"}`、
    属主 root、模式 0644；`omarchy-theme-set-browser` 整体 rc=0。
    **验证局限**：本机**没装任何 Chromium 系浏览器**（chromium / chrome / edge / brave 全无）
    ⇒ 四个策略目录都不存在，脚本按设计**不创建**它们（"creating one here would hand a browser a
    managed-policy root it does not otherwise have"）。所以端到端只验到"提权链 + 写入落盘"：
    上面那次写入是靠临时 `install -d /etc/chromium/policies/managed` 造出真目录做的，**验完已 `rm -rf`**
    （`/etc/chromium` 一并删回原样）。真浏览器装好后，色值才会被读走 —— 那时才谈得上"看得见的变色"。
    **维护**：`/usr/bin` 那份是副本，`omarchy update` **不会**刷新它；上游改了那个脚本，
    要重跑上面第一条 `install`（其余无需改动）。
    另注（同次发现，**未动**）：`/etc/sudoers.d/fprint-timer` 权限不是 0440（`visudo -c` 因此 rc=1 报
    "bad permissions, should be mode 0440"），sudo 会因此**忽略整份文件** —— 与本次无关，别顺手改。

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

---

35. **Herdr 键位：`Super+Ctrl+Return` 必须经终端启动，裸 `herdr` 在 niri 下必死（2026-09-24）**：
    用户问「`binds.kdl` 里 `Super+Ctrl+Return` 启动 herdr 是我写错了吗」。**键位与命令名都没写错**
    （`herdr` = `/usr/bin/herdr`，v0.9.1），错的是**启动方式** —— 那一行原本是裸调 `spawn-sh "herdr"`。
    - **根因**：herdr 是 TUI，要挂在 tty 上；而 niri 派给 bind 的子进程**没有 tty**。实测 niri 自己
      （pid 取 `pgrep -x niri`）是 `fd0 → /dev/null`、`fd1/fd2 → journald socket`，所以裸跑固定报
      `herdr: Not a tty (os error 25)`、exit 1 —— 按了等于没按，niri 也不会给任何提示。
    - **上游本来就是这条路**：`default/hypr/bindings/applications.lua` 写的是
      `o.bind("SUPER + CTRL + RETURN", "Herdr", { omarchy = "terminal-herdr" })`，而
      `bin/omarchy-launch-terminal-herdr` 的内容就一句 `exec omarchy-launch-terminal herdr`。
      本机那行绕过了这层包装（§5.3 那条「终端类一律走 `omarchy-launch-terminal`」同样适用）。
    - **修法**（`~/.config/niri/binds.kdl` 一行，顺带把 `ctrl` 规范成 `Ctrl`）：
      `Mod+Ctrl+Return … { spawn-sh "omarchy-launch-terminal herdr"; }` ⇒ `niri validate` = `config is valid`。
      改前快照 `~/.local/state/backups/.config/niri/binds.kdl.bak-20260924-herdr`（与改后只差这一行），
      并同步进仓库 `niri-config/local/binds.kdl`（`scripts/kdl-sync.sh` 七份全 ok）。
    - **排查陷阱（别再白测一轮）**：从 agent 自己的 shell 里测 `herdr`，先撞上的是 herdr 的**嵌套检测**
      （`nested herdr is disabled by default` / `recursion detected. base case not found. aborting.`）——
      agent 就跑在 herdr pane 里，`env -u HERDR_*` 清掉变量也没用（它按进程祖先判），
      **得换到没有 herdr 祖先的进程树里才看得到真错误**：
      `setsid env -i HOME="$HOME" PATH="$PATH" TERM=dumb herdr </dev/null` → 这才现出 `Not a tty`。
    - **顺带修正 §5.5 的旧结论**：那儿写的「因本机不用 tmux/herdr，不再绑定」只对**键位面板**成立
      （`Super+Alt+K` Tmux keybindings、`Super+Ctrl+K` Herdr keybindings 确实没绑，`Mod+K` 已让给
      `omarchy-menu-keybindings`），**herdr 本身是在用的**，现在也直接从键位进。

38. **电池面板加 CHARGE LIMIT 档位切换（充电阈值可写，2026-09-26）**：用户要求「把充电阈值做进 bar 的电池
    图标」（bar 右侧 `omarchy.power` 那个 🔋）。**读路径原本就有** —— `omarchy-battery-status --shell`
    早就输出 `threshold<TAB>75-80%`，面板也一直在右下角显示它，缺的只有**写回**。
    - **两档**（用户拍板「一档可以充满，一档 0-75/80 就行」，数值由我润色）：**Protect 75–80** 与
      **Full 95–100**。起点取 75 而不是 0，是因为 0 会让电芯长期停在 80% 上、每次小幅回落都触发微循环；
      75 是"放到 75 再充"，对电芯友好。75/80 同时**正是本机出厂值**（`/etc/tlp.conf:592` 与 `:594`
      的 `START/STOP_CHARGE_THRESH_BAT0`，sysfs 实测一致）。
    - **实现**（`shell/plugins/panels/power/Panel.qml`，活体）：在 POWER PROFILE 之后追加 CHARGE LIMIT 区
      —— `PanelSeparator` + `PanelSectionHeader` + `Row`/`Repeater` 的 `Button`，按钮样式**照抄**同一面板里
      POWER PROFILE 那排（`active`/`hasCursor`/`onHovered`/`onClicked`），没新造零件。点击 →
      `Process` 跑 `pkexec tlp setcharge <start> <stop>`。键盘导航从"一段"扩成"两段"：上下键在两排之间
      跳（`focusSection`），左右键在**当前那排内**走（`chargeLimitIndex`），回车激活。
    - **按钮点亮的判据**：读回的 `threshold` 去掉 `%` 后与 `start + "-" + stop` **逐字符相等**才点亮；
      手工设的第三组值（如 60–90）两边都不亮 —— 这是有意的诚实行为，代码里已注释。实测 Protect 亮、
      配色与 POWER PROFILE 里 active 那颗一致（截图取样 rgb `129,116,123` vs `125,115,121`）。
    - **为什么必须 pkexec**：本机从终端裸跑 `pkexec`（无匹配规则时）**会永久挂住**（`exit=124`，polkitd 记
      `FAILED to authenticate … unix-process:unknown`）。放行方式选的是 **polkit 规则**（而非 sudoers
      NOPASSWD，也非只读展示）：`/etc/polkit-1/rules.d/49-tlp.rules`，匹配
      `action.id == "org.freedesktop.policykit.exec"` 且 `action.lookup("program") == "/usr/bin/tlp"`
      且 `subject.isInGroup("wheel")` → `polkit.Result.YES`。**规则只对 `/usr/bin/tlp` 生效**，其余程序
      仍照旧卡住（这既是验证方法，也是"别把口子开大"的边界）。
    - ⚠ **壳层自己也注册了 polkit agent**（`journalctl -t omarchy-shell` 里的 `omarchy polkit agent registered`）——
      所以面板里 `Process` 发的 `pkexec` 有可能本来就够、这条规则只是保险；但**没去撤验**（撤验要 root 动
      `/etc`，而前一轮已经因为给 polkitd 加 `--debug`（**127 版不认这个开关**，正确的是 `--log-level=debug`）
      把它弄进过 `start-limit-hit` 重启循环）。**别拿那段时间"pkexec 免密过了"当结论** —— 那是瞬态假象，
      `pkcheck … --process $$` 同时报 `exit=2`（需要认证）。另：`pkexec` 一次只发一条命令，并发两条会双双
      静默挂死。
    - **`tlp setcharge` 只写运行时 sysfs、不落任何配置** ⇒ **Full 是一次性的**：重启（或 TLP 重启）后一律
      回落 `/etc/tlp.conf` 的 75/80，面板也会重新亮 Protect。想真正持久化得改 `/etc/tlp.conf` —— 那是另一件
      系统级改动（备份/验证/回退），**尚未做、也没擅自做**。
    - **实测到的**：`pkexec tlp setcharge 95 100` → sysfs 读回 `95/100` → 再 `75/80`，`exit=0`、无提示、
      无挂起；用临时 Quickshell 配置（`Process` 跑同一条命令，等价于面板里的执行环境）复验也是 `exit=0`
      且 sysfs 落地。**没验到的**：鼠标点击那一步本身 —— 本机只有 `wtype`（无 `dotool`/`ydotool`/指针注入
      工具），而 `wtype` 的按键**送不进面板的 `PanelKeyCatcher`**（连按三次 Down/Right 前后两张截图**逐字节
      相同**，面板纹丝不动），所以"点一下按钮"这条路只能靠代码审读 + 上述等价链路取证。
    - **手感问题与修法（2026-09-26 当轮追加）**：用户反馈"xx 太慢了"。实测：**延迟不在 TLP 而在 pkexec 的
      polkit 握手** —— `tlp setcharge` 本体 **87 ms**，套上 `pkexec` 变 **1.7–4.5 s**（`pkexec tlp --version`
      也 1.87 s，与写不写 sysfs 无关）⇒ 点下去要 ~2 秒后那颗按钮才亮，看起来像"没反应 / 写反了"。
      用户同时问"下面的模块不能显示当前状态吗"，于是两处一起改（同一文件）：
      ① **乐观高亮** —— 新增 `property int chargePendingIndex`，点击瞬间就把高亮挪过去（不等进程返回）；
      `setChargeLimit` 签名改成 `(index, preset)`，下标由 `Repeater` / 键盘选择**显式传入**（不拿 `indexOf`
      反查对象 —— 那样一旦查不到就会把"高亮丢了"变成静默失败，而且这条没法靠点击复验）；
      `actionProc.onExited` 里先清 pending 再 `refresh()`，**以读回的真值为准**，写入失败会自动退回不亮；
      打开面板时（`onOpenedChanged`）也清一次，免得"pkexec 永久挂住"把假高亮留在屏上。
      ⚠ 那个 5 秒的自动 `refresh()` 计时器**不碰** pending（否则会在进程飞行中闪回旧档一次）。
      ② **CHARGE LIMIT 标题行右侧加 `now 75-80%`** 当前值读数（照抄 network 面板 `bandHeader` + 右侧
      `Row` 的 `Item{width:parent.width}` + 左贴/右贴布局），不再只靠"哪颗亮着"去推断。
      **顺带修一句旧注释**：代码里原来写"本机没有认证 agent"，实测不准（见下条）。
    - **⚠ 真根因（2026-09-26 用户追问"功能是不是写反了 / 是 omarchy 的 charge limit 慢还是我的不准"时挖出来的）**：
      `omarchy-battery-status` **优先读 UPower**（`upower -i` 的 `charge-*-threshold:` 两行），sysfs 只是**兜底**；
      而 **UPower 这两个字段是设备建立时缓存、运行期不重读** —— 实测 `tlp setcharge 95 100` 之后 sysfs 立刻是
      `100`，UPower 在 **45 秒内一直报 `80%`**，于是脚本照样输出 `threshold 75-80%`。
      ⇒ 所以"点了 Full 但高亮没动 / 像写反了"**不是命令错，是读数陈旧**：sysfs 真的变了，面板读回来的还是旧值。
      ⚠ 这也意味着**上一版"只加乐观高亮"会更糟**（亮一下再弹回旧档）—— 两处必须一起改。
      - **修法**：把 `bin/omarchy-battery-status` 那两行改成 **sysfs 优先、UPower 兜底**（← 这个上游文件已进
        补丁，是第 24 个文件；sysfs 读不到时不至于是空值）。**验证**：写入 95/100 后**同一秒**读
        `omarchy-battery-status --shell` = `95-100%`，而同一刻 `upower -i` 仍 `80%`；还原 75/80 同理。
      - ⚠ **`pkexec` 单趟耗时是飘的**：同一晚量到 **1.7 / 2.9 / 4.5 s**，后来同一条命令涨到 **~20 s**。
        所以"慢"这件事不要按固定值记；乐观高亮就是为了不把手感绑在这个握手上。
    - **"电池停在阈值之上"不是失准**：EC 只会**停止充电、不会主动放电**。用户切到 Full 会让充电重启，
      切回 Protect 时包已经在阈值之上 ⇒ 停在 82%（当场实测它从 82 一路爬到 88；AC 在线而 `status=Not charging`
      正说明阈值在生效）。想降回去只能让它放电。
    - **补丁要跟着动**：`Panel.qml` 在覆盖层里 ⇒ 用同一份路径清单重导出
      （`git diff -- <niri.patch 里那 24 个路径>`）⇒ **24 文件 / 62 → 72 hunk**，新 md5
      `e6868080f48c5f7cd1711a22e163de86`（`--reverse --check` 通过；旧版 `4ec279cf…` 已退役）。
      注意 `omarchy-niri-repatch` **只负责重放、不会重生成**补丁文件。
      ⚠ **2026-09-27 已被 §8 第 39/40 条那版超过**：**26 文件 / 77 hunk**、md5 `22dd2334c2210d91618b9ad903d3cbc2`（那条只加了 ante 的 5 个 hunk；`e6868080…` 这一版的 72 hunk 于是变成中间版本）。

39. **Setup > Security 新增 "Paru (AUR)" 开关：paru 的执行位就是本机 AUR 的总开关（2026-09-27）**
    - **是什么**：菜单 Security 区多一条 `Paru (AUR)`，切换 `/usr/bin/paru` 的执行位。**执行位即总开关**：本机 AUR
      全走 `~/bin/yay` 垫片（`docs/shims.md` §8 第 34 条），而垫片是**按 "PATH 上找得到可执行的 paru"** 挑真帮手的
      （`[[ -f $dir/paru && -x $dir/paru ]]`，找不到就报 `yay(shim): paru not found on PATH …`）⇒ `chmod -x` 一次停掉
      `install.aur` 与 `remove.package` 两条路（`/usr/bin/paru` 由 pacman 拥有，没有用户副本能 shadow 它）。
      语义 = 整机不再碰 AUR：AUR 装过的包照旧能用，只是不再能升级。
    - **实现三处（都在补丁之外；菜单侧零补丁）**：
      ① `port-bin/omarchy-setup-security-paru` → `~/bin`（PATH 首位）：**一身两半**，按 `EUID` 分。用户半身提供
         `--status`（菜单 `checked:`）、`--enabled`（菜单 `when:`，纯退出码）、无参时念警告 + `gum confirm`；
         root 半身只认 `--enable`/`--disable`，`chmod` 目标与 `PATH` 都写死 —— 形状照
         `omarchy-theme-set-browser-policy`（§8 第 20 条）。
      ② `/usr/bin/omarchy-setup-security-paru`：**root 属主副本**（`install -m 0755 -o root -g root`）。pkexec 的目标
         只能是这种固定路径 —— 放行一个普通用户改得动的路径就等于无密码 root。
      ③ `/etc/polkit-1/rules.d/49-paru.rules`：`org.freedesktop.policykit.exec` + 只认这一个 program + wheel →
         `polkit.Result.YES`（裸 pkexec 无规则会挂死，见 §8 第 38 条）。**刻意没放行 `/usr/bin/chmod`**：vantage 原实现
         `pkexec chmod ±x /usr/bin/paru` 要的正是这个（= wheel 无密码改任意文件权限、`chmod u+s` 就地提权），
         故改成"专用 helper + 只放行该 helper"。polkit 规则**不能按 argv 过滤** ⇒ 参数形状在 root 半身再校验一遍。
    - **菜单侧**（`~/.config/omarchy/extensions/omarchy-menu.jsonc`，热监听 + 合并）：`setup.security.paru`
      （icon 󰣇、label `Paru (AUR)`、勾选走 `--status`、动作照 Security 区其余五条套
      `omarchy-launch-floating-terminal-with-presentation` —— 脚本要先念警告，需要一块能等回车的终端）+
      **三条 `when` 守卫**（`install.aur`、`remove.package`、`update.aur`）：paru 关掉后这些入口本来只会失败，于是
      跟着消失；开关自身**不带**守卫（否则关掉就开不回来）。
    - ⚠ **覆盖默认项必须整条复述**：`parseMenuJsonc` 把**每个字段**都补成默认值（`action:""`，`kind` 由 action 推），
      合并是**逐字段覆盖** ⇒ 用户层只写 `when` 会把默认项的 `action` 冲成空串，条目退化成"没有子项的子菜单"、
      `isVisible` 判 false、**静默消失**（install 面板 14 → 11 行）。改默认项就要一并复述 `icon`/`label`/`action`。
    - **验法**：`scripts/menu-model-render.js <面板 id>` 走的是壳层同一份 parse → merge → guard → isVisible。paru 开时
      install 12 行（含 `AUR`）、remove 6 行（含 `Package`）、update 10 行（含 `AUR`）、`setup.security` 6 行；
      关掉后 12→11 / 6→5 / 10→9，而 `setup.security` 恒 6 行。提权那一跳：
      `pkexec /usr/bin/omarchy-setup-security-paru --enable|--disable` 应 rc=0 且**不弹认证**（= 规则在生效）。
      ⚠ 用鼠标点那条开关本机验不了（`wtype` 送不进菜单，也没有 `dotool`/`ydotool`）。
    - **回退**：`pkexec rm` 掉 `/usr/bin` 副本与那条规则 + `systemctl restart polkit`（逐条见 `docs/local-overrides.md` §5）。
      ⚠ **paru 包升级会恢复执行位** ⇒ 这是开关、不是锁，`omarchy update` 之后要复查。

40. **ante 进菜单的"默认 agent"列表（2026-09-27）**
    - **列表机制**：`Setup > Default Agent` 每条动作都是 `omarchy-default-agent <name>` —— 把名字写进
      `~/.config/omarchy/defaults/agent` 后 `exec omarchy-agent`（即"设为默认 **并** 启动"），勾选靠
      `checked:"[[ \"$(omarchy-default-agent)\" == \"<name>\" ]]"`。这是 vantage `a()` 的官方版。
    - **补丁落点（命令侧两处；菜单那一行在扩展文件、零补丁）**：
      ① `bin/omarchy-default-agent`：case 新增 `ante) agent="ante"; name="Ante"; agent_self_managed=true`，并新增
         `elif [[ -n ${agent_self_managed:-} ]]` 分支 —— ante **不是 mise 能装的东西**（原 else 分支会先
         `mise where ante` 再 `mise use -g ante`，必败后弹 "Could not install Ante with mise"），它自己用
         `ante update` 升级 ⇒ presence 定义为"PATH 上找得到"（`omarchy-cmd-present`），install 是空操作。
      ② `bin/omarchy-agent`：启动 case 新增 `ante) command=(ante --yolo) ;;`。`--yolo` 是 Ante 的权限旁路拼法；
         **故意不转发 prompt** —— ante 的 `-p/--prompt` 是 **headless** 语义，与"开一个交互窗口"不符（`pi` 同样留白）。
    - **菜单那行**：`setup.default.agent.ante`，icon 󱚤 借 `install.ai` 那枚（已确认能渲染，`iconFont` 留空；Ante
      不在 omarchy 品牌字体里），动作 `omarchy-default-agent ante`。
    - **PATH 事实**（Security 开关那条与本节都靠它）：菜单动作与守卫走的是**壳层进程的 PATH**
      （`/proc/<quickshell>/environ`）—— `~/bin` 居首、且**含 `~/.ante/bin`**，所以裸 `omarchy-setup-security-paru`
      与裸 `ante` 都能解析。⚠ `systemctl --user show-environment` 那条 PATH **不含**这两者（user manager 的 ≠ 会话的），
      别拿它判断菜单行为。
    - **验法**：`omarchy-default-agent bogus` 的 usage 里应出现 `ante`；全链可用桩启动器验（PATH 前置一个只 echo 参数的
      `omarchy-launch-tui`）⇒ 期望打印 `LAUNCH: --app-id=org.omarchy.agent ante --yolo` 并写 `defaults/agent`；
      `scripts/menu-model-render.js setup.default.agent` ⇒ 15 行、末行 `Ante`。
    - **补丁**：+5 hunk ⇒ **26 文件 / 77 hunk**，md5 `22dd2334c2210d91618b9ad903d3cbc2`（路径清单加 `bin/omarchy-agent`、
      `bin/omarchy-default-agent`；`--reverse --check` 通过，两个副本逐字节一致）。

41. **vantage 退休并公开归档（2026-09-27）**
    - **四功能归位**：`res` 分辨率切换 → **弃用**（交给 Monitor 面板；代码里 `DISPLAY_LOCKED = true` 保持屏蔽）；
      `charge` 充电阈值 → 电池面板 CHARGE LIMIT 档位（§8 第 38 条）；`paru` 执行权限 → Security 开关（§8 第 39 条）；
      `agent` 默认 AI agent → `Setup > Default Agent`（§8 第 40 条）。
    - **仓库**：`github.com/jianlongliu/vantage` —— **PUBLIC + 已归档**（`isArchived=true`，只读），单个 commit，
      tag `v2026.8.19`（= `Cargo.toml` 的 version）。**顺序：先建 release 再归档**（归档后资产改不了；下载不受影响）。
    - **Release `v2026.8.19`**：资产 `vantage-x86_64-linux-gnu`（805 544 B，动态链接 glibc 的 x86_64 ELF，
      `lto = true` + `strip = true`）与 `vantage-x86_64-linux-gnu.sha256`；二进制**由该 tag 的源码构建** ——
      `cargo build --release --offline` 零重编译，发布件 / `target/release/vantage` / `/usr/local/bin/vantage`
      三者 md5 同为 `05352d1459183639dfe9388978b26e1c`。
    - **脱敏口径**（= skill `writing-docs`）：源码本就干净（无家目录 / 主机名 / 内网 IP / URL / token，只有 `~/.zshrc`、
      `~/.config/vantage/config.json` 这类通用路径）。README 从"个人工作记录"精简成"退休说明 + 用法 + 构建"，
      **删掉四节本机专属内容**（开机分辨率 `user.kdl`、EDID 注入与 `/data/App/firmware/…` 备份路径、内核/UKI
      `loader.conf`、DMS 输出管理坑与 `dms-howdy-integration.md` 指针 —— 这些知识本就在本仓库 docs/ 里）；
      `.gitignore` = `/target` + 本仓库那份敏感文件基线；commit 身份用 GitHub noreply（与本仓库一致）。
      **没加 LICENSE 文件**（`Cargo.toml` 已声明 MIT）。
    - **本机残留：用户拍板"都不动"**（本轮只做到仓库 + release）：`/usr/local/bin/vantage`（与发布件同 md5）、
      `~/.config/vantage/config.json`、`~/.zshrc` 第 130–140 行那段 `# >>> vantage agent launcher` 的 `a()` 函数
      （**自包含**：读 `config.json` 再裸起 agent，不依赖那个二进制）、`~/.zshrc.bak-vantage`。
      **没有任何菜单项/键位还在调 vantage**（只有 `~/.config/niri/monitor.kdl` 一句注释提到它，历史说明，保留）。

---

## 功能覆盖账：还剩什么没实现（2026-09-24 清点）

> **本节不占全局编号**（`§8 第 N 条` 那个号段），只是把"移植到什么程度、还差什么"记在仓库里，
> 免得只活在对话里。口径是**估算**，不是上游给的现成数字。

**怎么算的**：菜单树共 **346 条**（`scripts/menu-model-render.js` 渲染 `MenuModel.js` 的口径），
10 个菜单组（Learn / Trigger / Style / Setup / Install / Remove / Update / About / System / Capture）
与 **15 个**插件目录**没有一个整块缺席**；被 niri 缺口挡住或降级的条目 **8 → 6**（本轮关掉窗口缝隙、
浏览器策略两项）**→ 5**（同日再修掉内屏开关那条假成功）⇒ **菜单口径 ≈ 98.6%**；
**功能口径 ≈ 96–97%**（clamshell 的显示半边同日补齐 —— 它不是菜单项，只影响这个口径；
剩下扣分的是"能用但语义打折"的那些，如 `hl.device` 只能按设备**类型**关、单窗口方形比例只能是"定宽"）。

### A. 还没实现（用户没遗弃，按可行性排）

| 项 | 现状 | 差什么 |
|---|---|---|
| 弹窗让位浮栏（toast/面板被浮动 bar 压住 `floatGap` 8） | **随时可做**，答案已查清 | 两处上游文件要改（`shell/plugins/notifications/Service.qml` 的 `barClearance`、`shell/Ui/KeyboardPanel.qml` 的 `gap`）。**做不了垫片**（`readonly` 计算值，外部无从覆盖）⇒ 正解是进 `niri.patch`（+2 hunk、限路径重导）。按插件 README 用 root 手改会在 `omarchy update` 后静默丢掉 |
| clamshell 的"不挂起"那半（合盖 + 外屏 ⇒ 继续用外屏） | 显示半边已做（2026-09-24，见 D 表）；这一半**没动** | `/etc/systemd/logind.conf.d/lid-suspend.conf`（装机写入）是 `HandleLidSwitchDocked=suspend`，"插着外屏"也算 docked ⇒ 合盖+外屏照样挂起。要改成 `ignore` 才谈得上"合盖不挂起" —— **root 改动，等用户拍板**（备份 + 回退命令见 `docs/shims.md` §4 的 clamshell 小节） |
| 单窗口方形比例（上游 Hyprland `single_window_aspect_ratio = 1,1`） | 没有 | niri **没有 aspect 约束**；最近的是列宽（`default-column-width` / window-rule 定宽），效果是"定宽"而非"正方"。要做先定口径：要正方，还是只要"别太宽" |
| 色温（手动，低优先） | 没有 | `wlsunset` **已在 `/usr/bin`**（唯一现成的 niri 可用件）但全树无引用；`gammastep`/`hyprsunset` 未装（后者是 Hyprland 专有）。**与"夜灯"歧义未清**（见 B 表末注） |
| 内屏开关（`omarchy-hyprland-monitor-internal off`） | ~~假成功~~ → **2026-09-24 已修**（见 D 表） | — |

### B. 用户主动遗弃（别再提议）

- **镜像输出**：`niri msg output` 只有 `off/on/mode/scale/transform/position/vrr`，**没有 mirror** ⇒ 补不了。
- **夜灯（日落自动那套）**：`omarchy-toggle-nightlight` / `omarchy-refresh-hyprsunset` /
  `omarchy-restart-hyprsunset` 都在，但走的是 hyprsunset（Hyprland 专有），本机也没装。
- 更早的遗弃项另见 `docs/shims.md` §4 末尾（workspace-layout / window-transparency「不需要，别补」）。
- **用 sudo-rs 替换 sudo（2026-09-27 评估后不换）**：Arch 的 `sudo-rs 0.2.15` 只提供
  `sudo-rs`/`sudoedit-rs`/`visudo-rs`/`su-rs`，不动 `/usr/bin/sudo`；本机现有 sudoers 它能解析
  （实测 `visudo-rs -cf` → `parsed OK`），但它是**功能子集**，两个缺口正打在上游"临时免密 sudo"的地基上——
  `NOTAFTER` 不支持（实测报 `syntax error: NOTAFTER is not supported by sudo-rs`）、
  `-N/--no-update` 没有（man page 与二进制选项表都查不到）⇒ 与那套机制**互斥**。
  要真替代得自己改 PATH 或覆盖 `/usr/bin/sudo`（与 sudo 包互踩：pacman 升级覆盖、属主打架，
  且它必须 root 属主 + setuid）。收益是 sudo 自身的内存安全，代价是多养一条提权入口 + 每次系统更新盯着。
  **除非"减少提权面"成为明确目标（且接受并存维护），否则不回头。**
- ⚠ **歧义**：「夜灯遗弃」与「色温做低优先垫片」在同一台机器上是**同一个功能面**。
  目前的记法是"**日落自动夜灯不做，纯手动色温以后再说**"；若用户的意思是"色温整个不要"，把 A 表最后一行划掉。

### C. 环境不成立（用户明确**不算**移植缺口）

`style.unlock`（本机无 LUKS）、`install.webapp` / `install.preinstalls`（没装 chromium）、
`update.channel`（没配 Omarchy 仓库）、`update.password.drive`（无 LUKS 加密盘）。
这 5 条都在用户 override 里 `when:"false"` 隐藏，属"机器没有这个能力"，不是移植欠账。

### D. 本轮关掉的项（2026-09-24）

- **窗口缝隙开关**：已实现并端到端验过 —— 规格、坑（壳层 watch 只在启动时 `…/toggles/hypr/` 已存在才挂得上，
  `install.sh` 已补 `mkdir -p`）与截图为证见 `docs/shims.md` §4。
- **浏览器主题策略**：已修（root 属主副本 `/usr/bin/omarchy-theme-set-browser-policy` + 上游那条
  NOPASSWD 规则），根因与验证局限见 §8 第 20 条与 `docs/local-overrides.md` §5。
- **内屏开关 + clamshell 的显示半边**（同一条链子，2026-09-24）：`_eval_monitor()` 补上 `disabled`
  （写/删 `output-toggle-off.kdl` 覆盖文件，`niri validate` + 读回核对），`cmd_monitors` 的
  `disabled`/`active` 改成真实值；新增 `omarchy-hyprland-monitor-watch` 垫片 + 常驻用户单元
  `omarchy-clamshell-watch.service`（niri 没有外屏事件源、也没有 `switch:Lid Switch` 绑定 ⇒ 轮询
  盖子状态，只在**盖子合上**时才查一次 `niri msg outputs`）。规格、实测（真屏关了再开、模式没掉回 4K）、
  **没验到的分支**（本机无外屏、没合过盖）与 include 顺序规则见 `docs/shims.md` §4 的「内屏开关 / clamshell」小节。

