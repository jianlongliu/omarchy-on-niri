# 上游跟进 — Omarchy on niri 卷（upstream）

> 文档只有一份：本文件（`docs/upstream.md`）。
> 本卷 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽出（模块化拆分），**编号一律沿用原号** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，原处留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `docs/omarchy-on-niri-port.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 8.7 更新覆盖层：上游更新后自动重放
- 8.9 上游合并基线（`43bfe9b` → `d174d4a`，2026-09-18）
- 8.13 上游小更新（`d174d4a` → `8675600`，2026-09-19）
- 8.20 上游 sudo 安全机制：代码已合入、机制未启用（2026-09-27）
- 8.21 上游 shell 层的取舍：只跟 `Color.qml` 的颜色环修复（2026-09-27）
- 16. **GitHub 发布流程（2026-08-25 建立）**：移植差分推到 pub 仓库
- 8. **A+C 落地 / 更新覆盖层（2026-08-24）**：本节最后两项。

---

### 8.7 更新覆盖层：上游更新后自动重放

- `omarchy update` = `git pull --ff-only`（`omarchy-update-dev`，在 `post-update` 钩子**之前**）+ 迁移。
- **仓库外不碰**：`config.kdl` / `shell.json` / `~/bin/hyprctl` 都不在 omarchy 仓库内，`git pull` 动不到。
- **仓库内会撞**：我们改了仓库内 **27 个文件**。权威清单就是补丁自己的 `diff --git` 行：
  `grep '^diff --git' ~/.config/omarchy/niri-port/niri.patch | sed 's|.* b/||'`（换机器/换仓库路径也别抄下面的名单）。
  起步那 19 个是 `launch-{tui,editor,floating-terminal-with-presentation}`、`refresh-hyprland`、`theme-set`、
  `menu.jsonc`、`qmldir`、`Background.qml`、`ImagePicker.qml`、`Bar.qml`、`Workspaces.qml`、`Menu.qml`、
  `KeyboardPanel.qml`、`osd/Osd.qml`、`AppLibrary.qml`、`panels/power/Panel.qml`，以及 2026-08-25 加的 3 个
  `omarchy-system-{logout,reboot,shutdown}`；之后又加了 `shell/shell.qml`（boot reveal 推送）、
  `notifications/Service.qml`、`Commons/Style.qml`、`panels/monitor/Panel.qml`（分辨率滑块，2026-09-26）、
  `bin/omarchy-battery-status`（充电阈值改 sysfs 优先，2026-09-26，见 `docs/behavior.md` §8 第 38 条）、
  `bin/omarchy-default-agent` 与 `bin/omarchy-agent`（把 ante 加进默认 agent 列表，2026-09-27，见 §8 第 40 条）、
  `bin/omarchy-update`（把 CLI `omarchy update` 委派给 `~/bin` 垫片，2026-09-30，见 `docs/omarchy-on-niri-port.md` §3.1）。
  ——这 27 个文件正是 `niri.patch` 的内容（**27 个文件 / 81 hunk**，2026-09-30 核；2026-09-27 为 26 文件 / 77 hunk；
  2026-09-26 为 24 文件 / 72 hunk；
  2026-09-18 合并上游时为 30 hunk，
  2026-09-19 菜单自愈守卫 +2（§8.14）、Install/Remove 终端回退 +1（§8 第 21 条）、
  2026-09-20 选择器异步解码 +1（§8 第 25 条）、电量数字置右 +1（§8 第 28 条））。
  上游改到其中任何一个，`git pull --ff-only` 会因本地未提交改动而**失败中止**整个更新——这是需要
  手动合并的情况。
- **不在 patch 里的新增文件**：`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/` 是**未跟踪**
  文件，不会出现在 `git diff` 里，所以重放必须单独 `cp`（见下第 2 步）。
- **工作树里另有 238 条"有意删除"**（2026-09-19）：仓库自带主题删掉 21 个（含 `catppuccin-latte`），
  只留 `catppuccin`——用户只要 `tonal-spot` + `catppuccin`，`themes/` 从 64M 降到 1.2M。
  `omarchy-theme-remove`（§3 提到的官方脚本）**只管用户层主题**，仓库层只能直接删。
  内容没丢：git 对象还在，恢复一条命令 `git checkout -- themes`（或单个 `themes/<slug>`）。
  代价：若上游改动这些主题，`git pull --ff-only` 会因本地删除而中止——按同样办法恢复对应主题后重试。
- **自动重放**：`post-update.d/10-niri-repatch` 在每次更新后跑 `omarchy-niri-repatch`：
  1. 把 `~/.config/omarchy/niri-port/Niri.qml` 拷回 `shell/Commons/`。
  2. 把 `~/.config/omarchy/niri-port/plugins/*` 拷回 `shell/plugins/`（目前只有 `blurwallpaper/`）。
  3. `git apply` `niri.patch`；已应用则 `--reverse --check` 判 no-op（幂等）。
  4. 冲突则**不做任何改动**、退出码 2，提示手动合并（找 Ante）。
  5. 再跑一次 `omarchy-restart-shell`。上游更新会换掉 shell 的 QML，但**运行中的 Quickshell 仍执行旧代码**；
     上游 `omarchy-update-restart` 只问要不要重启电脑（读 `reboot-required`、内核版本），**不会重启壳层**，
     所以这一步必须我们自己做。niri 上可用（脚本经 `~/bin/hyprctl` 垫片 dispatch，实测 pid 会变、
     菜单/bar 正常）。
- **第三种情况：上游改到我们 patch 内文件的"其他区域"（2026-09-19 首次遇到，见 §8.13）**：`--ff-only` 会被
  本地未提交改动挡住（`error: Your local changes to the following files would be overwritten by merge`），
  但其实只需处理**那一个文件**：`git stash push -- <该文件>` → `git merge --ff-only origin/quattro` →
  `git stash pop`（3 方合并；区域不重叠就会打印 `Auto-merging` 并干净合并）→ 再
  `git apply --reverse --check niri.patch` 确认补丁仍精确等于工作区。
  **不要**为了更新去 `git checkout -- .`：我们另有 238 条"有意删除"（主题），那会白恢复 64M。
- 说明：覆盖层脚本只处理"上游没改到我们文件"的更新（此时 FF 成功、重放是 no-op）；
  "上游改到同一函数"才需要我重新翻译合并——这是任何移植都绕不开的兜底。

**覆盖层一致性自检**（改完 patch 后必做，否则幂等判断会失真）：

```bash
cd ~/.local/share/omarchy
git apply --reverse --check ~/.config/omarchy/niri-port/niri.patch && echo "patch 与工作区一致"
```

`--reverse --check` 通过 = patch 精确等于当前工作区改动；只有这种情况幂等/重放逻辑才成立。

---

### 8.9 上游合并基线（`43bfe9b` → `d174d4a`，2026-09-18）

首次把上游 342 个提交并入在线安装。**不跑整包 `omarchy update`**：它携带引导器、网络栈与 `/etc` 级
改动（清单见 §8.9.3），违反 §1。采用的流程是「先 FF、再重放移植、最后按类处置迁移」。

**8.9.1 合并与覆盖层重建**

```bash
cd ~/.local/share/omarchy
git fetch --depth=400 origin quattro        # --depth=50 会挂起，须给长超时
git stash push -u -m "niri-port pre-merge"
git merge --ff-only FETCH_HEAD              # 基线是上游直系祖先，无需真合并
git stash pop                               # 冲突集中在这一步

# 解决冲突后，把工作区改动固化成新的覆盖层
git add <已解决的冲突文件>                    # 必须归位 unmerged，否则 git diff 导出不全
files=$(grep '^diff --git' niri-port/niri.patch | sed 's|.* b/||')   # 路径表从上一份 patch 现取
git diff HEAD -- $files shell/plugins/panels/monitor/Panel.qml > ~/.config/omarchy/niri-port/niri.patch
# ↑ 仍然必须限路径：工作区里长期存在非移植改动（2026-09-20 为止：238 条主题删除），
#   裸 git diff HEAD 会把它们一起写进 patch，文件数从 19 变成 250+。
#   **别把路径表存 /tmp**：那份会被清掉 —— 2026-09-26 就因此重导出过一份 1 文件 14 hunk 的坏补丁。
#   另外，本次才新增/改动的文件不在这份清单里，要显式补上（例：2026-09-26 的 `panels/monitor/Panel.qml`）。
git reset                                   # 还原为「未暂存」，保持 pull 前置状态

# 必做自检：patch 必须精确等于工作区改动，否则幂等判断失真
git apply --reverse --check ~/.config/omarchy/niri-port/niri.patch
```

未跟踪的移植文件（`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/`）与上游新增路径不冲突，
合并后原样存活；但它们**不在 `git diff` 里**，因此 `omarchy-niri-repatch` 必须单独 `cp`（见 §8.7）。

**8.9.2 冲突与处置**

| 文件 | 上游改动 | 移植处置 | 理由 |
|---|---|---|---|
| `bin/omarchy-theme-set` | 背景切换改为三分支快照结构，新增 `BACKGROUND_TRANSITION_SNAPSHOTS` | 采用上游结构；各分支回退到持久文件 `${OLD_BACKGROUND_SNAPSHOT:-$old_background}`，并在 `choose_staged_theme_background` 调用处加 `XDG_CURRENT_DESKTOP != niri` 守卫 | 上游开关只对**视频**壁纸关快照，修不了 niri 竞态：快照约 3s 后被删除，而 QML 仍异步加载该路径 → 黑桌面 |
| `default/omarchy/omarchy-menu.jsonc` | 新增 `setup.security.sudoless-docker` 等条目 | 保留上游新条目；重新应用 niri 侧改动（`setup.config.hyprland` → 指向 `config.kdl`、标签 "Niri"；`hyprsunset` 保持 `"when":"false"`） | 菜单是上游与移植共同维护面，逐项合并而非整文件取舍 |

其余 9 个上游同样改过的移植文件（`Bar.qml`、`Osd.qml`、`Menu.qml`、`Background.qml`、
`KeyboardPanel.qml`、`Workspaces.qml`、`AppLibrary.qml`、`Commons/qmldir`、
`omarchy-launch-floating-terminal-with-presentation`）**自动合并**，无需人工介入。

**8.9.3 迁移分类处置**

手工部署的安装没有迁移历史（`~/.local/state/omarchy/migrations/` 为 0/121），直接 `omarchy-migrate`
会重放全部历史。处置办法：**先把 121 条全部标记为已应用，再只摘下要执行的**。

```bash
cd ~/.local/share/omarchy
export OMARCHY_PATH=$PWD XDG_CURRENT_DESKTOP=niri
STATE=$HOME/.local/state/omarchy/migrations

for f in migrations/*.sh; do touch "$STATE/$(basename "$f")"; done   # 全部标记
while read -r m; do rm -f "$STATE/$m"; done < run-list.txt            # 只摘出批准项

# 逐条执行：单条失败不影响其余（omarchy-migrate 一条失败会中止整批）
while read -r m; do
  if bash -euo pipefail "migrations/$m" >"/tmp/miglogs/$m.log" 2>&1; then
    touch "$STATE/$m"; echo "OK   $m"
  else
    echo "FAIL $m"; tail -1 "/tmp/miglogs/$m.log"
  fi
done < run-list.txt
```

| 类别 | 条数 | 处置 | 理由 |
|---|---|---|---|
| 纯配置类（只改 `$HOME`） | 32 | **执行** | 与系统底层无关 |
| 安装类：Cloudflare CLI `cf` | 1 | **执行** | 用户指定只装 `cf` |
| 需 root / 改系统底层 | 44 | 保留标记，**不执行** | 会顶掉 systemd-boot（`1789325478` 装 `linux-omarchy` 并设为 Limine 首启动项）、重建 initramfs（`1786482992`/`1784917531`/`1786605598`/`1784476564`）、退役 systemd-networkd（`1782002156`）、关 sshd 密码认证（`1788124236`）、删 `/etc/sudoers.d` 与 `/etc/systemd/system` 下退役文件（`1788025225`）、要求本机未配置的 Omarchy 签名仓库（`1787589206`/`1784672586`/`1787399318`/`1786952219`）——均违反 §1 |
| 安装额外 CLI | 12 | 保留标记，**不执行** | 用户只要 `cf`；Basecamp 系与各编码 agent 不用 |
| 交互式提问 | 1（`1786549201`） | 保留标记，**不执行** | 非交互环境会挂起 |
| 本机不适用 → **2026-09-21 已另行解决** | 1（`1785608166`） | 保留标记，**不执行** | 修 `omarchy-sleep-lock.service` 单元。**原记的理由不准**：不是"niri 侧未使用"，而是①上游单元的两条 `ConditionEnvironment=` 在本机都过不去 —— `OMARCHY_PATH` 那条读的是用户管理器环境（本机没有 UWSM 去 import 它），`WAYLAND_DISPLAY` 那条则是**评估得太早**（单元由 `graphical-session.target` 拉起，那会儿会话还没发布环境；2026-09-21 重启的 journal：20:10:17 跳过、20:10:18 niri 才起来）；②本机 dev-link 装机绕过了 first-run 的 `enable-user-units.sh` ⇒ 这个单元**压根没装过**，合盖直接 suspend、不锁屏。2026-09-21 已用自建单元 + `omarchy-sleep-lock-start` 包装器补上，见 `local-overrides.md` §6 与 `lock.md` §11.28 |

执行结果：**33 条实跑，30 条一次通过**；2 条因缺 `mise` 失败（`1787215483`、`1789095456`），装上
`mise` 后重跑通过。最终 `omarchy-migrate --pending` 为空，后续 `omarchy update` 不会重放历史。

**特权通道**：`pkexec` 免密可用；`sudo -n` 不可用（需密码）。`omarchy-pkg-add` 经 `sudo pacman`，
非交互必失败——**需要装包的迁移在本机一律走不通**，只能改用 `pkexec pacman -S`。

**8.9.4 新增系统依赖**

| 包 | 用途 |
|---|---|
| `vi`（+ `ex-vi-compat`） | 上游 `install/omarchy-base.packages` 显式列出的基础包；`omarchy-menu-tmux-keybindings` 等会调用 `vi` |
| `qt6-multimedia` + `qt6-multimedia-ffmpeg` | 视频壁纸：`shell/Ui/BackgroundMedia.qml`、`BackgroundVideo.qml` |
| `mise` | `~/.local/bin` 下 agent wrapper 的执行后端。上游从**自家仓库**装 `mise-bin`；本机未配置该仓库，改取 Arch `extra` |

**8.9.5 合并后配置状态**

| 项 | 状态 |
|---|---|
| `~/.config/omarchy/shell.json` bar 布局 | 被上游默认覆盖：center = `indicators, clock, keyboard-layout, weather, system-update`；right 新增 `agents`。**用户接受该默认并自行重新定制**，故不留兼容层 |
| 第三方 bar 部件 | `charlieras262.omablur`、`ryuhzk.ime` 保留；`local.opencode-go`、`io.github.alexinslc.calendar-agenda` 由**用户自行删除**，勿从备份恢复 |
| `~/.local/bin` agent wrapper（约 20 个） | 迁移 `1784909971`、`1787573629` 把**原本已存在**的 wrapper 重写为新模板；**未新装任何 CLI**。它们是 `install/user/mise.sh` 的默认集，装上 `mise` 后**首次被调用时**才下载（惰性） |
| 备份 `~/.config/omarchy/niri-port/backups/20260918-pre-merge/` | 当日快照（含 `~/.config/{omarchy,niri,tmux,kitty,foot}` 打包），**仅作回滚参考，不是要复原的目标状态** |

---

---

### 8.13 上游小更新（`d174d4a` → `8675600`，2026-09-19）

**当前上游基线 = `8675600`**（§8.9 记的是上一次大合并到 `d174d4a`；那份数值仍是那次合并的记录）。

上游又走了 5 个提交（`8675600` Merge PR #12141 + 4 个），内容全是 **php/laravel 开发环境安装**：
改写 `bin/omarchy-install-dev-env`、`bin/omarchy-remove-dev-env`，以及 `default/omarchy/omarchy-menu.jsonc`
里对应的 4 行（判据从 `omarchy-pkg-present php` 改成 `[[ -d $HOME/.local/share/mise/installs/php ]]`，
laravel 从 `~/.config/composer/vendor/bin/laravel` 改成 `~/.local/bin/laravel`）。**三个文件都不含 QML**，
所以这次更新不需要重启壳层。

- **与我们 patch 的重叠**：只有 `default/omarchy/omarchy-menu.jsonc` 一个文件，且是**不同区域**——
  上游动第 277–282 / 343–350 行，我们的 4 个 hunk 在 108 / 123 / 184 / 364 行（菜单 action 指向
  `niri/*.kdl` 与 `omarchy-niri-apply-theme`；那之后 2026-09-19 又加了 install/remove 的回退，
  该文件现为 5 个 hunk，见 §8 第 21 条）。
- **做法**：走 §8.7 的"第三种情况"——只 `git stash push -- default/omarchy/omarchy-menu.jsonc`，
  FF 拉上游，`git stash pop` 由 git `Auto-merging` 干净合并，无冲突。
- **验收**（全部通过）：`git apply --reverse --check niri.patch` ✓（**补丁基线数值当时不变，仍是
  17 文件 / 30 hunk；同日更晚加上菜单自愈守卫后为 32，见 §8.14**）→ `omarchy-niri-repatch` 报 `already applied`（幂等仍成立）→ 该文件相对 `HEAD`
  的差异**恰为 9+/9-**（= 我们 4 个 hunk，不含上游 php 行），相对 `HEAD~5` 恰为 **13+/13-**
  （= 上游 4+4 与我们的 9+9，**零丢失**）→ 上游新判据落地（第 280 / 347 行）、我们的 6 处 niri 指向仍在
  → `omarchy-install-dev-env` / `omarchy-remove-dev-env` 内**无 hypr/uwsm 耦合**（niri 上不会瘸）
  → 壳层进程健在、日志无错、`grim` 截图 bar 在位（栏内 `(46,61,83)` ≠ 栏外 `(90,111,137)`）。
- **附注（别当 bug 修）**：`omarchy-menu.jsonc` 第 370 行有一个**尾随逗号**，严格 JSON 解析会报
  `Illegal trailing comma`——`HEAD` 与 `HEAD~5` 同在 370 行，是上游原有写法，jsonc/QML 解析器容忍它。
- **238 条主题删除未受影响**：上游这 5 个提交没碰 `themes/`，`--ff-only` 因此不会被本地删除挡住；
  更新后 `git status` 仍是 17 M + 238 D + 3 未跟踪（`shell/Commons/Niri.qml`、`shell/plugins/blurwallpaper/`、
  `shell/test-debug.qml`）。
- **下次更新的预期**：上游一旦改到我们那 24 个文件（当时 17，2026-09-20 起 18、当晚 19；2026-09-26 起 23，同日再加 `bin/omarchy-battery-status` 成 24，见 §8.7）里的**同一函数**，`omarchy-niri-repatch` 会以退出码 2
  明确报冲突且不动仓库（见 §8.7），那时才需要手工翻译合并。

### 8.20 上游 sudo 安全机制：代码已合入、机制未启用（2026-09-27）

上游 `8675600` → `c5b4db77`（138 提交）这一批里，"提权"被统一成**命令作用域 sudo**。合入的是代码，
**系统件没装、机制没启用**。

**是什么**

- `bin/omarchy-security-functions`（新）：共享库。`omarchy_security_require_privileged_bash_startup`
  要求脚本以 `bash -p` 启动（并回查 `/proc/<pid>/cmdline` 与 `exe`）；`require_source_root` 校验
  `OMARCHY_PATH` 与入口路径的对应关系；`enable_no_update_sudo` 把 `default/omarchy/sudo-no-update`
  前置进 PATH 并置 `OMARCHY_SUDO_NO_UPDATE=1`；另有吊销凭据/清理 trap。
- `default/omarchy/sudo-no-update/sudo`（新）：`sudo` 包装器，除 `-k/-K/-h/-V` 外一律
  `exec /usr/bin/sudo -N "$@"`——`-N` 不刷新凭据缓存，于是"更新流程用过的 sudo 授权"不会留给后续步骤。
- `bin/omarchy-sudo-passwordless`（重写，449 行）：`omarchy-sudo-passwordless [MINUTES]`，默认 15、上限
  1440，往 `/etc/sudoers.d/99-omarchy-nopasswd-<uid>` 发布
  `<account> ALL=(ALL) NOTAFTER=<YYYYMMDDHHMMSSZ> NOPASSWD: ALL`（`visudo` 校验 → 点开头临时名 →
  原子 `mv` 就位），配一条 `systemd-run --on-calendar` 定时器到期撤销。状态机 fail closed：
  `3` = 确认无授权，其余一律按错误处理，而且**只有 `3` 才允许新发布**。
- 更新流程改造：`bin/omarchy-update`、`-stay-awake`、`-restart`、`-aur-pkgs`、`refresh-pacman`、
  `channel-set`、`remove-dev-env`、`install-service-dropbox`、`restart-shell`。其中
  `omarchy-restart-shell` 是纯健壮性改动：先轮询 `omarchy-shell shell ping`（20 × 0.1s）确认壳层回来，
  把重锁提到这一步之后，再（当重启前通知服务在跑时）等 `org.freedesktop.Notifications` 注册总线名，
  最后才重发一次性邀请吐司。
- 上游打包用的系统件：`etc/tmpfiles.d/omarchy-nopasswd-sudo.conf`（开机删残留授权）、
  `default/libalpm/hooks/05-omarchy-passwordless-revoke.hook`（settings 包变更前先撤授权）。

**本机形态过不去的三条**

1. `INSTALLED_SELF=/usr/bin/omarchy-sudo-passwordless`：UI 提权（`sudo -N -- "$INSTALLED_SELF" __enable …`）
   与到期定时器都走这个**绝对路径**。本机 `/usr/bin` 下只有 `omarchy-setup-security-paru`、
   `omarchy-theme-set-browser-policy` 两个。
2. `verify_boot_cleanup` 要求 `/etc/tmpfiles.d/omarchy-nopasswd-sudo.conf`（内容须逐字节等于
   `r! /etc/sudoers.d/99-omarchy-nopasswd-*`）与 `/usr/share/libalpm/hooks/05-omarchy-passwordless-revoke.hook`
   （内容须逐字节等于模板）。本机两个位置都没有 omarchy 条目。
3. `omarchy_security_require_source_root` 只接受两种入口——`$OMARCHY_PATH/bin/<cmd>`，或
   `OMARCHY_PATH == /usr/share/omarchy` 时的 `/usr/bin/<cmd>`；`verify_root_path` 还拒绝符号链接、
   逐级要求 root 属主且无 group/other 写位。dev-link（`~/.local/share/omarchy` 属用户）两条都过不去。

**为什么不用补丁绕过**：这套东西的安全前提就是"被提权的代码在 root 拥有、普通用户写不了的地方"。
在本机摆一条用户可写的入口再给它 pkexec 免密，等于把那台机器的"无密码 root"送给任何能写该目录的进程
（含任何 agent 进程）——这不是移植，是开洞。真要这套，正当路径是把 omarchy 装成 `/usr/share/omarchy` +
`/usr/bin` 的包形态，即放弃 dev-link 装机。

**验证（2026-09-27 实测）**：`bash -n` 过全部 13 个改动/新增脚本；`realpath ~/.local/share/omarchy`
与原值一致（`require_source_root` 的前提）；`gum` 在 `/usr/bin/gum`（UI 确认框要用）；
`omarchy-shell shell ping` → `ok`（新版 `omarchy-restart-shell` 的前提成立）；非交互直接跑
`bin/omarchy-sudo-passwordless` → sudo 索要密码/指纹、未发布任何授权，
`/etc/sudoers.d` 仍是 `00_jianlongliu` / `fprint-timer` / `omarchy-theme-browser` 三条，`/etc/tmpfiles.d`
与 `/usr/share/libalpm/hooks` 无新增。

**机制未启用意味着**：`omarchy-sudo-passwordless` 本机跑到提权那步就失败（fail closed，不会半发布）；
`omarchy-update` 的上游流程本机本来就走不通（没装 omarchy 包、没配 Omarchy 仓库）：菜单与 bar 的 Update
走 `~/bin/omarchy-update` 垫片，**CLI `omarchy update` 自 2026-09-30 起也走同一个垫片**（`bin/omarchy-update`
顶部的三行委派，随 `niri.patch` 重放；见 §8.7 与 `local-overrides.md` §8 第 19 项），想跑上游真身用
`~/bin/omarchy-update --upstream`。

**更新时注意**：这批文件在工作树里现在"本地改动恰好等于上游版本"，但 `git pull --ff-only` 仍会被
dirty 挡下（git 只比是否 dirty，不比内容）。处置是先丢再 FF：

```bash
cd ~/.local/share/omarchy
git restore --source=HEAD --worktree -- \
  bin/omarchy-channel-set bin/omarchy-install-service-dropbox bin/omarchy-refresh-pacman \
  bin/omarchy-remove-dev-env bin/omarchy-restart-shell bin/omarchy-sudo-passwordless \
  bin/omarchy-update-aur-pkgs bin/omarchy-update-restart \
  bin/omarchy-update-stay-awake config/omarchy/hooks/pre-refresh-pacman.d/add-custom-repo.sample \
  default/agents/skills/omarchy/hooks.md docs/update-process.md \
  etc/tmpfiles.d/omarchy-nopasswd-sudo.conf manual/31-dotfiles.md manual/48-security.md
# 新增的 5 个未跟踪文件（bin/omarchy-security-functions、default/libalpm/hooks/05-omarchy-passwordless-revoke.hook、
# default/omarchy/sudo-no-update/sudo、$OMARCHY_PATH/docs/passwordless-sudo.md、migrations/1788163635.sh）
# 与上游同路径时由 FF 直接快进，不用动。
```

> ⚠ **这条清单里不能有 `bin/omarchy-update`**（2026-09-30 起）：它现在带着我们的三行委派，
> `git restore` 会把委派**静默丢掉**（CLI `omarchy update` 又回上游那套），而它本身是 `niri.patch`
> 的受管路径 —— 真要还原就走 `omarchy-niri-repatch`，或照 `local-overrides.md` §9 索引那行撤回。

丢的是"等于上游的内容"，无损；`bin/omarchy-remove-ai-hermes` **不在本次范围内**（它属于 Hermes 主题，
本机那处 150+/56- 的改动是"自动关闭 Hermes"那批，本次没跟）。

---

### 8.21 上游 shell 层的取舍：只跟 `Color.qml` 的颜色环修复（2026-09-27）

同一批（`8675600` → `c5b4db77`，138 提交）里，shell 层改动的绝大部分是**一个动作的两半**：
把视频壁纸从壳层搬给外部壁纸引擎 OWE。这里只跟了不依赖 OWE 的那一条。

**是什么**

- **跟了**：`shell/Commons/Color.qml`（`flatColor` 加环检测，7+/1-）、`shell/Commons/Util.qml`
  （一行注释 `tensaku` → `omasnap`，纯注释）。
- **没跟（OWE 桌面半边）**：`shell/Ui/BackgroundMedia.qml`（6+/55-，删掉 video loader 与
  `playbackEnabled`/`audioEnabled`/`reloads`/`videoUrl`，只留静图 + `version`）、
  `shell/Ui/BackgroundVideo.qml`（删除，-122）、`shell/Ui/qmldir`（去掉该注册）、
  `shell/plugins/background/Background.qml`（3+/40-，删掉功耗控制那一段）。
- **没跟（OWE 锁屏半边）**：`shell/plugins/lock/LockView.qml`（21+/7-）、`lock/Service.qml`
  （29+/0-，新增 `videoPosterPath` 与 `poster.sh` 调用）、新增 `lock/LockFeedSurface.qml`
  （`import Owe.LockFeed`）与 `lock/poster.sh`（用 `ffmpegthumbnailer` 抽一帧缓存，锁屏在暂停或
  没有 feed 时显示它）。

**机制**：`flatColor` 逐跳解析颜色 token 链（`shell.toml` 里 `x = "y"` 这种别名）。旧实现是
"指向另一个 token 就递归自己"，没有环检测 ⇒ 主题或用户覆盖写出 `A→B→A` 就无限递归（QML 里
栈溢出）。新实现用 `while` + `seen` 表：重复出现过的 role 直接返回 `fallback`，多跳链照旧跟到底。

**为什么其余不跟**：OWE 桌面半边装得上——AUR 有 `owe`（0.2.7，上游 `github.com/omacom/owe`，
**不依赖 hyprland**，依赖 `mpv/ffmpeg/socat/qt6-declarative`；本机只缺 `socat`）；但锁屏半边的
`owe-lockfeed` **AUR 查无**（`import Owe.LockFeed` 无从解析），`poster.sh` 还要本机没有的
`ffmpegthumbnailer`。而且一动就会拆掉移植版在 `Background.qml` 里的 niri 适配（锁屏/屏保/省电/
全屏暂停，音频只出首屏）——那正是本机视频壁纸的功耗控制。要上 OWE 就先用 AUR 的 `owe` 单独实测
（能否在 niri 铺满、可见性暂停是否成立、功耗多少），再回来整组动；那时
`plugins/background/Background.qml` 的 3 个 hunk 要重翻。

**验证（2026-09-27 实测）**：用 node 复刻新旧两版 `flatColor`，喂本机真实配置
（`current/theme/shell.toml` + `~/.config/omarchy/shell.toml`，合并 103 个 key）：
**0 个环、10 个多跳链 ⇒ 逐 key 结果等价，行为零变化**。`omarchy-restart-shell` → exit 0
（本机可用：`hyprctl` 那行由 `~/bin/hyprctl` 垫片翻成 `niri msg action spawn`，锁屏判断读 logind
`LockedHint`），`omarchy-shell shell ping` → `ok`，`journalctl --user -t omarchy-shell` 无加载错误
（只剩移植版常态的 `quickshell.hyprland.ipc` ServerNotFound）；重启前后同会话全屏截图对比：bar 带
平均色一致，带内 494/384000 像素有差异且全落在内容行（时间与图标刷新）。

**回退**：`git restore --source=HEAD --worktree -- shell/Commons/Color.qml shell/Commons/Util.qml`
+ `omarchy-restart-shell`。这两个文件不在 `niri.patch` 的路径表里（`grep '^diff --git'` 可查），
所以补丁不用动；将来 FF 到上游时它们与 §8.20 那批一样属于"本地内容 == 上游内容"，同样先丢再 FF。

---

16. **GitHub 发布流程（2026-08-25 建立）**：移植差分推到 pub 仓库
    `github.com/jianlongliu/onarchi`（PUBLIC，默认分支 `quattro`）。要点：
    - **仓名**：2026-09-28 GitHub 改名 `omarchy-on-niri` → `onarchi`（旧 slug 仍 301 重定向）；
      本地目录 `~/Projects/omarchy-on-niri` 与 `docs/omarchy-on-niri-port.md` 文件名**不改**。
      ⚠ `github.com/jianlongliu/Nirism` 是**另一个项目**（Hyprland 仿 niri，`master` 分支），
      README 改名提交一度把 clone URL 写成它，已改回 `onarchi`。
    - 本地 working clone 在 `/home/<dev-user>/omarchy-on-niri`（独立的临时构建仓库，
      **不是** LIVE 的 `~/.local/share/omarchy`——后者保留未提交工作树改动，避免破坏
      `git pull --ff-only`）。
    - push 走 **SSH**（`gh auth git-credential` 走 https 会弹密码，不可用）。
    - gh 以 **GitHub 账户**的身份操作（hosts/config 已拷进 `~/.config/gh`）；ed25519 密钥 +
      known_hosts 在 `~/.ssh`。
    - 重推流程：`git clone git@github.com:jianlongliu/onarchi.git`（分支 `quattro`）→
      改 → `git commit` → `GIT_SSH_COMMAND="ssh -o BatchMode=yes" git push origin quattro`。
    - 仓库结构含 `port-bin/`（含 hyprctl、uwsm-app、omarchy-update、omarchy-picker-warmup、
      omarchy-display-text-size 等 11 个 override）、`niri-config/`+`shell.json`、`hooks/`、
      `install.sh`（非破坏引导，用户明确不要自动化拼装脚本，见 user-environment 记忆）、`docs/`、`README.md`。
    - 非单机即开即用：每台机器要核 monitor 输出名、背光设备、电源后端(TLP/PPD)、niri 版本。

---

8. **A+C 落地 / 更新覆盖层（2026-08-24）**：本节最后两项。
   - **§8.6 A 层（菜单指向 niri 真配置 + Hyprland 层降级）**。
   - **§8.7 更新覆盖层（上游更新自动重放我们的移植改动）**。
