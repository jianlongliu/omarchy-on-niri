# 本机 `~/.config` 覆盖层

TL;DR — `config/` in this repo is **upstream Omarchy's** default config tree (untouched). This
directory is the other layer: the subset of `~/.config/` that this machine actually runs and that
upstream does not ship. Without it a fresh install comes up with window decorations, no frosting and
a dead recolor unit. Copy the files over your own, then adjust fonts and DPI.

`config/` 是**上游 Omarchy 的默认树**（我们没动过，`config/ghostty/config` 与
`~/.local/share/omarchy/config/ghostty/config` 逐字节相同）。本目录是压在它上面的**本机覆盖层**：
`~/.config/` 里真正在跑、而上游不提供的那几份。2026-09-20 收进仓库。

## 这里有什么

| 仓库路径 | 机器路径 | 为什么必须收 |
|---|---|---|
| `ghostty/config` | `~/.config/ghostty/config` | 移植的关键改动就在里面：`window-decoration = false`、`background-opacity = 0.85`、**`background-blur-radius = 0`**（niri 不实现 KDE blur 协议，ghostty 自带模糊会叠成双层；磨砂交给 niri 的 `background-effect`）。**磨砂五处之一**，漏了就是"有装饰、无磨砂"的旧症状 |
| `systemd/user/materal-recolor.path` | `~/.config/systemd/user/…` | 换壁纸自动重新取色：`.path` 盯 Omarchy 的壁纸文件，一变就拉起 `.service` |
| `systemd/user/materal-recolor.service` | 同上 | oneshot，跑 `%h/bin/materal-update`（本移植的 matugen 包装脚本，仓库 `port-bin/materal-update`，机制见 `docs/omarchy-on-niri-port.md` §8.10）。单元本身**不是上游的、也没有包认领** |

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
cd ~/omarchy-on-niri
./scripts/local-files-sync.sh     # 三层一起对账：local-config/ + plugins/ + split-lock/ir-light
```

改完机器上的文件再跑一次，`DIFF` / `MISSING` 就是漂移。脚本在没装这些东西的机器上会 `skip`。

## 还没收进来的

`~/.config/omarchy/{shell.json,shell.toml,extensions/omarchy-menu.jsonc}` 的**实际取值**仍是缺口
（仓库只有 `niri-config/shell.json` 示例）—— 总账 `docs/local-overrides.md` §8 第 4 条。这三份已经扫过
**不含任何密钥**，属于"要不要公开本机偏好"的选择题，不是技术障碍。
