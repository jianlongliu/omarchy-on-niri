# 上游跟进 — Omarchy on niri 卷（upstream）

> 正本：`~/Documents/omarchy-niri-upstream.md`（与仓库 `docs/upstream.md` 逐字节一致）。
> 本卷 2026-09-20 从 `omarchy-on-niri.md` 抽出（模块化拆分），**编号一律沿用正本** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，正本对应位置留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `omarchy-on-niri.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `omarchy-on-niri.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 8.7 更新覆盖层：上游更新后自动重放
- 8.9 上游合并基线（`43bfe9b` → `d174d4a`，2026-09-18）
- 8.13 上游小更新（`d174d4a` → `8675600`，2026-09-19）
- 16. **GitHub 发布流程（2026-08-25 建立）**：移植差分推到 pub 仓库
- 8. **A+C 落地 / 更新覆盖层（2026-08-24）**：本节最后两项。

---

### 8.7 更新覆盖层：上游更新后自动重放

- `omarchy update` = `git pull --ff-only`（`omarchy-update-dev`，在 `post-update` 钩子**之前**）+ 迁移。
- **仓库外不碰**：`config.kdl` / `shell.json` / `~/bin/hyprctl` 都不在 omarchy 仓库内，`git pull` 动不到。
- **仓库内会撞**：我们改了仓库内 **19 个文件**（`launch-tui`、`launch-editor`、
  `launch-floating-terminal-with-presentation`、`refresh-hyprland`、`theme-set`、`menu.jsonc`、
  `qmldir`、`Background.qml`、`ImagePicker.qml`、`Bar.qml`、`Workspaces.qml`、`Menu.qml`、`KeyboardPanel.qml`、
  `osd/Osd.qml`、`AppLibrary.qml`、`panels/power/Panel.qml`，以及 2026-08-25 加的 3 个
  `omarchy-system-{logout,reboot,shutdown}`）
  ——这 19 个文件正是 `niri.patch` 的内容（`19 个文件 / 35 个 hunk`；2026-09-18 合并上游时为 30，
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
git diff HEAD -- $(cat /tmp/niri-port-files) > ~/.config/omarchy/niri-port/niri.patch
# ↑ 仍然必须限路径：工作区里长期存在非移植改动（2026-09-20 为止：238 条主题删除），
#   裸 git diff HEAD 会把它们一起写进 patch，文件数从 19 变成 250+。
#   /tmp/niri-port-files 从上一份 patch 提取：grep '^diff --git' niri.patch | sed 's|.* b/||'
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
| 本机不适用 | 1（`1785608166`） | 保留标记，**不执行** | 修 `omarchy-sleep-lock.service` 单元；本机无此单元（Omarchy 的 systemd 集成，niri 侧未使用），永远不可能成功 |

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
- **下次更新的预期**：上游一旦改到我们那 19 个文件（当时 17，2026-09-20 起 18、当晚 19，见 §8 第 25/28 条）里的**同一函数**，`omarchy-niri-repatch` 会以退出码 2
  明确报冲突且不动仓库（见 §8.7），那时才需要手工翻译合并。

---

---

16. **GitHub 发布流程（2026-08-25 建立）**：移植差分推到 pub 仓库
    `github.com/jianlongliu/omarchy-on-niri`（PUBLIC，默认分支 `quattro`）。要点：
    - 本地 working clone 在 `/home/yvonne/omarchy-on-niri`（独立的临时构建仓库，
      **不是** LIVE 的 `~/.local/share/omarchy`——后者保留未提交工作树改动，避免破坏
      `git pull --ff-only`）。
    - push 走 **SSH**（`gh auth git-credential` 走 https 会弹密码，不可用）。
    - gh 以 **jianlongliu** 身份操作（hosts/config 已拷进 `~/.config/gh`）；ed25519 密钥 +
      known_hosts 在 `~/.ssh`。
    - 重推流程：`git clone git@github.com:jianlongliu/omarchy-on-niri.git`（分支 `quattro`）→
      改 → `git commit` → `GIT_SSH_COMMAND="ssh -o BatchMode=yes" git push origin quattro`。
    - 仓库结构含 `port-bin/`（含 hyprctl、uwsm-app、omarchy-update、omarchy-picker-warmup、
      omarchy-display-text-size 等 11 个 override）、`niri-config/`+`shell.json`、`hooks/`、
      `install.sh`（非破坏引导，用户明确不要自动化拼装脚本，见 user-environment 记忆）、`docs/`、`README.md`。
    - 非单机即开即用：每台机器要核 monitor 输出名、背光设备、电源后端(TLP/PPD)、niri 版本。

---

8. **A+C 落地 / 更新覆盖层（2026-08-24）**：本节最后两项。
   - **§8.6 A 层（菜单指向 niri 真配置 + Hyprland 层降级）**。
   - **§8.7 更新覆盖层（上游更新自动重放我们的移植改动）**。
