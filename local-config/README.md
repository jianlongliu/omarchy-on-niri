# 本机 `~/.config` 覆盖层

TL;DR — `config/` in this repo is **upstream Omarchy's** default config tree (untouched). This
directory is the other layer: the subset of `~/.config/` that this machine actually runs and that
upstream does not ship. Without it a fresh install comes up with window decorations, no frosting, a
dead recolor unit, and upstream's stock bar instead of this one. Copy the files over your own, then
adjust fonts and DPI.

`config/` 是**上游 Omarchy 的默认树**（我们没动过，`config/ghostty/config` 与
`~/.local/share/omarchy/config/ghostty/config` 逐字节相同）。本目录是压在它上面的**本机覆盖层**：
`~/.config/` 里真正在跑、而上游不提供的那几份。2026-09-20 收进仓库。

## 这里有什么

| 仓库路径 | 机器路径 | 为什么必须收 |
|---|---|---|
| `ghostty/config` | `~/.config/ghostty/config` | 移植的关键改动就在里面：`window-decoration = false`、`background-opacity = 0.85`、**`background-blur-radius = 0`**（niri 不实现 KDE blur 协议，ghostty 自带模糊会叠成双层；磨砂交给 niri 的 `background-effect`）。**磨砂五处之一**，漏了就是"有装饰、无磨砂"的旧症状 |
| `systemd/user/materal-recolor.path` | `~/.config/systemd/user/…` | 换壁纸自动重新取色：`.path` 盯 Omarchy 的壁纸文件，一变就拉起 `.service` |
| `systemd/user/materal-recolor.service` | 同上 | oneshot，跑 `%h/bin/materal-update`（本移植的 matugen 包装脚本，仓库 `port-bin/materal-update`，机制见 `docs/omarchy-on-niri-port.md` §8.10）。单元本身**不是上游的、也没有包认领** |
| `omarchy/shell.toml` | `~/.config/omarchy/shell.toml` | 字号与通透度的**唯一旋钮**：`[font] base-size 12`（基准，见 `docs/visual.md`）、`[bar]` 尺寸 + `background-alpha 0.45` + **`icon-font 12`**（要 `Style.qml` 的白名单，已在 `niri.patch` 里）、`[menu] background-alpha 0.45`（**不写底色**，走主题的 `[menu] background`）。**磨砂五处之一**，漏了就退回不透明卡片 |
| `omarchy/shell.json` | `~/.config/omarchy/shell.json` | bar 布局与 idle 计时：`bar.id = charlieras262.floating-bar`（**在用的 bar 是第三方插件，不在 `niri.patch` 里**）、`idle.lock 300`、`disabledPlugins: ["omarchy.lock"]`。⚠ 钉的是**本机 bar 偏好**＋ 5 个不在仓库里的第三方部件，见下 |
| `omarchy/extensions/omarchy-menu.jsonc` | 同上 | 菜单 override：3 个 setup 项的 label + icon（上游只给 action，会显示成 raw id）＋ screensaver 的 6 条 `when:"false"` 屏蔽（用户要求禁用，见 `docs/local-overrides.md`） |

配色走 **Omarchy 自己的主题**，没有私有主题文件：

```
config-file = ?"~/.local/state/omarchy/current/theme/ghostty.conf"
```

这一行是上游的写法（`default/themed/ghostty.conf.tpl` 渲染出当前主题的那份），换主题即换配色。
`?` 表示文件不在也不报错。**2026-09-20 之前本机卡在 DMS 时代遗留的静态主题 `theme = dankcolors`
上，那份文件没有任何生成器、仓库和上游都搜不到出处，所以已删掉改回这条路。**

不在这个目录里的两类本机文件，分别在仓库别处：

- **自研插件源码** → `plugins/`（如 `plugins/jianlongliu.arch-logo/`）与 `split-lock/`。
- **根文件系统里的**（`/usr/local/bin/ir-light`）→ `split-lock/ir-light`。

## 怎么用到自己机器上

```bash
cp local-config/ghostty/config ~/.config/ghostty/config          # 先备份你自己的
cp local-config/systemd/user/materal-recolor.* ~/.config/systemd/user/
systemctl --user enable --now materal-recolor.path              # 需要 ~/bin/materal-update 在位
ghostty +validate-config                                        # 无输出即通过
```

- **字体是个人口味**：`font-family = SFMono Nerd Font` / `Microsoft YaHei`、`mouse-scroll-multiplier`、
  `async-backend = epoll` 这些换机按需改，只有上面那三条（`window-decoration` / `background-opacity` /
  `background-blur-radius`）是移植必需。
- `materal-recolor.service` 写的是 `%h/bin/materal-update`，**没有家目录字面量** —— 直接可用，
  不需要像 `niri-config/local/` 那样做 `sed` 替换。

## 两份怎么保持同步

机器上的 `~/.config/` 是**权威版**，本目录是它的逐字节镜像（这些文件里本来就没有家目录字面量，
所以不像 niri 配置那样存在"占位符差异"）：

```bash
cd ~/Projects/omarchy-on-niri
./scripts/local-files-sync.sh     # 三层一起对账：local-config/ + plugins/ + split-lock/ir-light
```

改完机器上的文件再跑一次，`DIFF` / `MISSING` 就是漂移。脚本在没装这些东西的机器上会 `skip`。

## 收齐了吗

`~/.config/omarchy/` 这一层**已收齐**（2026-09-21）：`shell.json` / `shell.toml` /
`extensions/omarchy-menu.jsonc` 的实际取值都在上面表里，入库前扫过**不含任何密钥**、路径零字面量
（`omarchy-menu.jsonc` 那处走 `$HOME`），出现的 `jianlongliu.*` 只是插件 id。

⚠ **换机时这份 `shell.json` 别整份照抄**：它钉的是本机 bar 偏好，其中 5 个部件不在仓库里 ——
`charlieras262.floating-bar`（就是 bar 本体）、`io.github.claudsondouglas.arcdock`、`jrmmhm.pocket`、
`meviusisback.ai-subs`、`ronald.input-sources`，都是要从 Omarchy 插件市场单独装的。想要中性起手式就用
`niri-config/shell.json`（上游默认盘），两份都留着，按需选。

`~/.config/omarchy/{shell.json,shell.toml}` 是**热监听**（存盘即生效）；但仓库里这份改了**不会**自动
同步到机器 —— 方向是"机器 → 仓库"，回写靠 `local-files-sync.sh` 报 `DIFF` 后人工 `cp`。
