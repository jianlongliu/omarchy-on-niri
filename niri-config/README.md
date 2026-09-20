# niri 侧配置

TL;DR — `local/` is the niri config this machine actually runs (7 files, ~910 lines: a modular
split with `config.kdl` only holding `include`s + session-level settings). `omarchy.kdl.template`
above it is the *other* route (one merged file, rendered by `install.sh`); this machine never used
it. Copy `local/*.kdl` to `~/.config/niri/`, replace `/home/<user>` with your home directory, fix
`monitor.kdl` for your panel, then run `niri validate`.

这里是本机**实际在用**的 niri 配置，按模块拆成七份：`config.kdl` 只留 `include` 与会话级设置，
其余各自成文件。共约 910 行，2026-09-20 收进仓库。

## 两条路，别混

| 路径 | 是什么 | 本机 |
|---|---|---|
| `niri-config/omarchy.kdl.template` | 一体式接线：`install.sh` 渲染成 `~/.config/niri/omarchy.kdl`，由 `config.kdl` 合并 | **没用**（本机没有 `omarchy.kdl`） |
| `niri-config/local/*.kdl` | 模块化拆分：`config.kdl` 直接 `include input / monitor / layout / window-rules / effects / binds` | **在用**，就是本文这七份 |

## 怎么用到自己机器上

```bash
cp niri-config/local/*.kdl ~/.config/niri/          # 先备份你原有的
sed -i "s|/home/<user>|$HOME|g" ~/.config/niri/*.kdl
$EDITOR ~/.config/niri/monitor.kdl                 # 删掉 modeline 行，scale 按自己 DPI 试
niri validate                                      # 必须通过；见下面的静默陷阱
```

- **家目录必须写字面量**：niri 不展开 `$HOME`/`$PATH`，`config.kdl` 的 `environment` 段里
  `OMARCHY_PATH` 与 `PATH` 都是死路径 —— 仓库版写成 `/home/<user>` 占位符，就是给上面那行 `sed` 用的。
- **`monitor.kdl` 是本机面板专属**：`output "eDP-1"` + 为这块面板手算的 modeline
  （CSO1411，2560x1600@60）。换机删掉 `modeline` 行、`scale` 按自己 DPI 调，别照抄。
- **`binds.kdl` 里 `Mod+Ctrl+Shift+W` 指向 `~/bin/wechat`**：那是本机私人物件，仓库里没有这个脚本 ——
  删掉这条 bind，或自己写一个。

## 哪些是 niri 出厂默认，哪些是这里的改动

对照 niri 自带的默认配置（Arch 包在 `/usr/share/doc/niri/default-config.kdl`）可以看出，这七份是
**从默认改出来的**，本移植的改动主要落在：

- `layout.kdl` —— gaps 收窄到 8、focus-ring / border / shadow 的形状与颜色接 Omarchy 主题变量。
- `effects.kdl` + `window-rules.kdl` —— 磨砂（`xray false`，共出现 20 次）与全局圆角。
  **磨砂是五处联动的**（这两个文件 + ghostty + 覆盖层 `shell.toml` + QML），单改一处看不见效果。
- `binds.kdl` —— 按键去重（每个功能只留一个绑）、终端统一走 `omarchy-launch-terminal`、
  菜单走 `omarchy-menu`，以及 `uwsm-app` 垫片救活的那些调用点（原 §8 第 22 条）。
- `config.kdl` —— `XDG_CURRENT_DESKTOP "niri"`、`QT_QPA_PLATFORMTHEME "qt6ct"`、光标主题、
  `OMARCHY_PATH`/`PATH`。

## 改动纪律（踩过的坑，都在 `docs/` 里）

1. **改前必留 `.bak-*`**，本机每个文件旁边都有历史版本。
2. **bind 里不能写开窗属性**（`open-floating` 之类）：niri 对整份 `config.kdl`（含 `include`）
   做事务性校验，一处失败**整体丢弃、继续跑旧配置、桌面零提示**。改完必须 `niri validate`，
   再看 `journalctl | grep 'niri\['`。
3. **KDL 普通字符串里 `\.` 非法**（`invalid escape char`）→ 用 `r#"…"#` 或不转义。
4. bind 里的 `spawn` 是**直接 exec**，不展开 `~`，路径要写全。

机制与来龙去脉见 `docs/behavior.md`（按键与行为）、`docs/visual.md`（视觉）、
`docs/local-overrides.md` §4（本机配置分层与陷阱）。

## 两份怎么保持同步

机器上的 `~/.config/niri/*.kdl` 是**权威版**（家目录是真路径），本目录是**占位符版**。两者之间
**只差家目录那一处**（`scripts/kdl-sync.sh` 就是按这个不变量对账的）。改完本机配置、`niri validate`
通过后同步过来：

```bash
cd ~/omarchy-on-niri
for f in config input monitor layout window-rules effects binds; do
  sed "s|$HOME|/home/<user>|g" ~/.config/niri/$f.kdl > niri-config/local/$f.kdl
done
./scripts/kdl-sync.sh          # 七份逐字节对账（把本机版换成占位符后比较）
niri validate -c niri-config/local/config.kdl
git diff --stat niri-config/local/
```

**本机专有一律不进这两份文件**：仓库里不写「换机」注释、不写"这是占位符"提示 —— 那些话在这份 README 里
（上面两节），否则同步时会被 `sed` 冲掉、对账出现假差异。
