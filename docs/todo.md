# 待办 — Omarchy on niri 卷（todo）

> 文档只有一份：本文件（`docs/todo.md`）。本卷 2026-09-24 立，只记**还没做 / 等拍板**的事。
> **本卷不占全局编号**（`§N`、`§8 第 N 条` 那套号段），所以目录条目故意不带号 ——
> 免得污染"编号全局唯一、永不改号"的约定（脚本 `scripts/check-doc-refs.py` 会把 `- 33. xxx`
> 这类目录条目登记成"本卷定义了这个号"）。
> 做完一条就把结论落到对应卷、把这里那行删掉；**已完成的事不在这里留档**（查
> `docs/behavior.md` 覆盖账的 A / D 表与各卷正文）。
> 跨卷编号找不到在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md` 的 §0 文档地图与 §8 映射表。

## 本卷目录

- 等用户拍板
- 低优先垫片
- 本机卫生项

## 等用户拍板

| # | 事 | 要动什么 | 备注 |
|---|---|---|---|
| 1 | **合盖不挂起**（合盖 + 外屏时继续在外屏干活） | root：`/etc/systemd/logind.conf.d/lid-suspend.conf` 里 `HandleLidSwitchDocked=suspend` → `ignore`，再 `systemctl reload systemd-logind` | 备份路径与回退步骤见 `docs/shims.md` §4 的 clamshell 小节；**本机没外屏 ⇒ 改完也验不了真行为**，所以一直没动 |
| 2 | **窗口缝隙垫片的 niri 侧待重验** | `~/.config/niri/layout.kdl`（仓库副本 `niri-config/local/layout.kdl`）那条 `include optional=true "layout-no-gaps.kdl"` 从**尾部挪到顶部**，再量窗边像素 | 不挪大概率一直是空转（niri 同名键只认第一次定义）；**壳层那半是真的**（`getoption` 是垫片写死的映射）；依据与两份反证见 `docs/shims.md` §4 的「更正」 |
| 3 | **弹窗让位浮栏**（toast / 面板被浮动 bar 压住 `floatGap` 8） | 进 `niri.patch`：`shell/plugins/notifications/Service.qml` 的 `barClearance`、`shell/Ui/KeyboardPanel.qml` 的 `gap`（+2 hunk、限路径重导） | **做不成垫片**（`readonly` 计算值，外部无从覆盖）；按插件 README 用 root 手改会在 `omarchy update` 后静默丢掉 |
| 4 | **单窗口方形比例** | niri **没有 aspect 约束**，最近的是列宽（`default-column-width` / window-rule 定宽）⇒ 效果是"定宽" | 动手前先定口径：要**正方**，还是只要"别太宽" |
| 5 | **夜灯 / 色温的歧义** | 手动色温做不做（`wlsunset` **已在 `/usr/bin`**、全树无引用；`gammastep` 未装） | 现在的记法是"日落自动夜灯不做、**手动**色温以后再说"；若用户的意思是"色温整个不要"，把 `docs/behavior.md` A 表最后一行划掉 |
| 6 | **浮动工具窗底色提亮**（`Ctrl+Shift+Esc` / `Mod+Y` / `Mod+E` 太黑） | 三选一：① 全局 —— `~/.config/ghostty/config` 在 include 之后写一行 `background`（取主题亮档 `#282a2f`，**连 Mod+Return 一起变亮**）+ nautilus 跟主题的 `~/.config/gtk-4.0/gtk.css`；② 只这两个键 —— 加 `XDG_CONFIG_HOME` 垫片指到另一份 ghostty 配置（btop 子进程会继承该变量）；③ 不动 | 漏项已补：三键 + nautilus 都补了 `opacity`（2026-09-25）。**alpha 实测对浮动窗只有 2–3/255 的效果**，主因是底色；机制与全套实测数据见 `docs/visual.md` §8.8 第 37 条（用户 2026-09-25「晚上看看文档」） |

| 7 | **把三条自定义时序塞进注入 EDID**（让它们成为内核原生模式，少依赖自定义 modeline） | 改 `/usr/lib/firmware/edid/CSO1411.bin`（先备份）→ `pkexec mkinitcpio -P` → 重启；试件已备好（`~/.local/state/omarchy/edid-trial/trial-2.bin` = 合法重排 + 三条 CTA DTD，本地校验通过） | 起因：用户以为"四档分辨率就在注入件里"，2026-09-26 复核**不成立**（件里只有 DTD1 4K + 一条被内核丢弃的 DTD2）。**收益有限** —— 档位靠 modeline 注入已经能上屏；且 EDID 是承重墙、验证必须走重启。`debugfs edid_override` 热验**不通**（eDP 不重探测，试完）。见 `local-overrides.md` §5 第 16 条 |
| 8 | **跟进 Omasnap 截图**（上游已用它取代 satty + tensaku：`omarchy-capture-screenshot` 重写成它的壳，参数从 `smart\|region\|windows\|fullscreen [slurp\|copy\|save] [--editor=]` 变成 `… \|scroll [copy\|save]`，`--editor=` 取消） | 上游这份来自 `omarchy-pkgs` 的 `omasnap` 包（本机没配那个仓库）；AUR 有 `omasnap-bin 1.21.0`，但**硬依赖 `hyprland`** 与 `layer-shell-qt`（本机两个都没装） | 2026-09-27 拍板**暂不跟进**（依赖太重、且"for Omarchy and Hyprland"在 niri 上未验证）。真跟进时要动：`bin/omarchy-capture-screenshot`、`config/imv/config`、`install/omarchy-base.packages`、`migrations/1788129995.sh`、`manual/12-screenshots-recording.md`；同批上游也改了 `default/hypr/apps/screenshot-selection.lua`（Hyprland 专有，本机不用） |
| 9 | **要不要真启用上游的"临时免密 sudo"**（`omarchy-sudo-passwordless [MINUTES]`，默认 15、上限 1440：往 `/etc/sudoers.d/99-omarchy-nopasswd-<uid>` 发布一条带 `NOTAFTER` 截止的规则，配 `systemd-run` 日历定时器到期自撤） | 启用需三样 **root 拥有、路径链不可被普通用户写** 的东西：`/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf`（开机清残留授权）、`/usr/share/libalpm/hooks/05-omarchy-passwordless-revoke.hook`（内容要逐字节等于模板）、**真实文件**（非符号链接）`/usr/bin/omarchy-sudo-passwordless` | 代码 2026-09-27 已随上游合入工作树（见 `docs/upstream.md` §8.20），**机制未启用**。dev-link 形态与上游三条前提正面冲突（`omarchy_security_require_source_root` 只认 `$OMARCHY_PATH/bin/<cmd>` 或 `/usr/share/omarchy` + `/usr/bin/<cmd>`；`verify_root_path` 拒绝符号链接、逐级查 root 属主）。**别为了绕过而在用户可写路径放入口再配 pkexec 免密**：那等于把"无密码 root"送给任何能写该目录的进程 |

## 低优先垫片

- **色温** —— 等上表第 5 条口径；落点/机制/回退一律照 `docs/shims.md` 的垫片标准写
  （`wlsunset` 是唯一现成的 niri 可用件；`hyprsunset` 是 Hyprland 专有，别想）。

（「内屏开关」原本也归这类，2026-09-24 已做完 ⇒ 规格见 `docs/shims.md` §4，状态见
`docs/behavior.md` 覆盖账 D 表。）

## 本机卫生项

- **未提交**：本仓库工作树里有一批本地改动没 commit，其中**混着并行会话的改动**
  （如 `docs/lock.md`、`docs/omarchy-shell.md`、`local-config/omarchy/shell.json`、
  `port-bin/omarchy-powerprofiles-set`）⇒ 提交前先看 `git diff --cached`，**别长暂存、别改历史**。
- **机器 ↔ 仓库的 4 份既有差异**（不是漂移故障，是"本机版 vs 仓库模板"）：
  `~/bin/omarchy-update`、以及 `~/.config/systemd/user/` 下的 `omarchy-crash-watch.service` /
  `omarchy-picker-warmup.service` / `omarchy-sleep-lock.service` —— 本机那几份写死 `$HOME` 路径、
  带本机专属注释，`default/systemd/user/` 那几份是 `%h` 模板。**要不要收口由用户定**，
  收之前别当成仓库 bug 去"修"（2026-09-24 核对 `install.sh` 与 `local-config/` 时确认过）。
