# 视觉调整 — Omarchy on niri 卷（visual）

> 文档只有一份：本文件（`docs/visual.md`）。`~/Documents/omarchy-niri-visual.md` 是指向它的软链。
> 本卷 2026-09-20 从 `docs/omarchy-on-niri-port.md` 抽出（模块化拆分），**编号一律沿用原号** ——
> `§4`、`§8 第 N 条`、`§8.x`、`§11.x` 都是原号，原处留同名指针，所以仓库里既有的
> "§8 第 22 条"、"§11.13" 之类引用继续解析得到。
> 主文档（当前事实：约束 / 架构 / 文件清单 / niri 配置 / 部署 / 验证 / 环境）见 `docs/omarchy-on-niri-port.md`。
> 跨卷引用：看到 `§8.x` / `§8 第 N 条` / `§11.x` 不知在哪一卷时，查主文档 `docs/omarchy-on-niri-port.md`
> 的 §0 文档地图与 §8 映射表（**编号全局唯一、永不改号**）。

## 本卷目录


- 8.8 视觉磨砂（frosted Quickshell / 状态栏面板毛玻璃）
- 32. **吐司"一来通知整屏变糊"：全屏 surface 撞上 niri 侧 `blur true`（2026-09-20，用户 "我的吐司通知,
- 27. **不透明 app 的磨砂：只写 `background-effect { blur true }` 是看不见的（2026-09-20，用户要求「微信加上 blur，
- 8.19 全桌面字号 / DPI 一致性：一切向 bar 的 Display 面板看齐（2026-09-20）
- 31. **`[bar]` 段只认 3 个键 → 让 `shell.toml` 能覆盖全部 bar 整型令牌（2026-09-20，起因："bar 上字体是不是有的大有的小" →
- 28. **bar 的内联部件设置：电量百分比与摘掉 `omarchy.system-update`（2026-09-20，用户 "bar的电池加百分比, 去掉中间的
- 30. **菜单卡片"过于黑"：底色 = 主题 `[menu] background`（2026-09-20，用户 "omarchy menu过于黑了"）**：卡片底色不是
- 29. **窗口缝隙 16 → 8（2026-09-20，用户 "窗口缝隙过大调小些"）**：`~/.config/niri/layout.kdl` 的 `gaps`（逻辑像素，
- 18. **弹窗未给浮栏让位（TODO，下次修）**：toast（`shell/plugins/notifications/Service.qml` 的
- 8.10 主题动态取色（tonal-spot / matugen / materal-update）
- 8.12 共享壁纸库（omarchy-wallpaper-aio）
- 8.15 overview 模糊壁纸延迟（500ms 轮询 + 每次重解码）（2026-09-19）
- 8.16 overview 背板与窗口动画错位（"壁纸和窗口是反的"）（2026-09-19）
- 10. **overview 背景与桌面不一致（需求，2026-09-03 已修）**：niri 总览（`Mod+O` / `Mod+Tab` 触发
- 13. **Ghostty 磨砂模糊（2026-08-26 已修）**：见 §5.8。niri 侧 `background-effect {xray true; blur true}`
- 4. **显示器缩放 SCALE 生效**：`omarchy-hyprland-monitor-scaling` → `hyprctl eval hl.monitor(...)` 被
- 1. **CLI 依赖已装**：`jq` / `satty` / `inotify-tools` 已用 `pkexec pacman -S --needed jq satty inotify-tools` 装好
- 1b. **壁纸/背景已修**（2026-08-24）：除装 `qt6-imageformats` 外，两处代码改动——

---

### 8.8 视觉磨砂（frosted Quickshell / 状态栏面板毛玻璃）

niri 26.04 的 `background-effect` + Quickshell 的 `ext_background_effect` 形状磨砂，让 Omarchy shell
的卡片呈毛玻璃。设计原则：**绝不让 niri 侧对整面 layer-shell 做全屏模糊**（那会把整个屏幕霜化），
而是每个面板用 `BackgroundEffect.blurRegion` 只磨砂自己的卡片区域。

**仓库内改动（已进 `niri-port/niri.patch`；2026-09-18 合并上游 `d174d4a` 后整份 patch = 17 个文件 /
30 个 hunk，2026-09-19 起 32 个 hunk（菜单自愈守卫，§8.14）、再 +1 到 33（Install/Remove 终端回退，
§8 第 21 条）、2026-09-20 再 +1 到 34（选择器异步解码，§8 第 25 条）；2026-09-20 晚实测
**21 文件 / 38 hunk**（吐司 `blurRegion` +2，§8 第 32 条；中间还加过 bar 字号等改动，计数以实测为准）；
`--reverse --check` 通过）**：
- `shell/plugins/menu/Menu.qml`：加 `import Quickshell.Wayland._BackgroundEffect`，根 `PanelWindow`
  挂 `BackgroundEffect.blurRegion: Region { item: card; radius: root.cornerRadius }`。
- `shell/Ui/KeyboardPanel.qml`：同上，根 `PanelWindow` 挂
  `BackgroundEffect.blurRegion: Region { item: card; radius: Style.cornerRadius }`。**所有 bar 弹窗面板**
  （audio/bluetooth/clock/dropbox/monitor/network/power/tailscale/weather + agent 面板）都复用
  `KeyboardPanel`，所以这一处改动统一磨砂了它们全部（一次覆盖 9+ 面板）。
- `shell/plugins/osd/Osd.qml`（2026-08-31 新增）：**OSD 不用 blurRegion，改用"卡片大小 surface"**。
  官方版是全屏透明 `PanelWindow`（`anchors` 四边铺满），niri 的 layer-rule blur 会把它整面霜化
  （表现为"OSD 弹出时全屏变糊"）；且 Quickshell 的 `blurRegion` 在 niri 上 region 几何跟踪异常
  （实测把磨砂区域放大到约 2.6 倍），也不可靠。改为：`PanelWindow` 用
  `anchors { left; right; bottom }` + `margins`（左右按 `Quickshell.screens[0].width` 居中、底部
  `Style.space(67)`）+ `implicitHeight: card.height`，让 layer surface 本身就是卡片大小，
  卡片 `BorderSurface` 保留显式宽高、去掉居中 anchors，背景 `Color.menu.background`（透明度跟随
  `shell.toml [menu] background-alpha 0.7`）。这样 `effects.kdl` 的 blur 天然只磨砂卡片。
  实测（scale 2.0 物理 px）：屏幕主体 0 差异、卡片 556×130 物理（278×65 逻辑）居中底部、磨砂生效。

**仓库外 Layer-1 配置（pull 安全，不在 `niri.patch` 内）**：
- `~/.config/niri/effects.kdl`（被 `config.kdl` `include`）：全局
  `blur { passes 4; offset 3.5; noise 0.03; saturation 1.6 }` + layer-rule：
  - `^omarchy-osd$` → `background-effect { blur true; xray false }`（Osd.qml 已是卡片大小 surface，
    所以整面 blur 也只盖卡片；xray 与其余规则统一取 `false`，本篇早先写的 `xray true` 已过期）。
  - `^omarchy-notifications$` → `background-effect { xray false }`（**只设 xray，不设 `blur true`**）。
    吐司 surface 与 OSD 相反、**必须保持全屏**（`Service.qml`：固定尺寸，免得增删吐司时 surface 变尺寸、
    卡片被短暂拉伸），所以 `blur true` 会霜化**整个屏幕**——2026-09-20 修的就是这个（§8 第 32 条）。
    磨砂区域改由客户端下发：该文件根 `PanelWindow` 挂
    `BackgroundEffect.blurRegion: Region { item: popupColumn; radius: service.cornerRadius }`。
  - `^omarchy-keyboard-panel$` → `background-effect { xray false }`（**只设 xray，不设 `blur true`**——
    Quickshell 已发卡片形状区域，该区域就是唯一磨砂范围，全屏 surface 不会霜化）。`xray false` =
    磨砂卡片背后的**实时窗口**（真毛玻璃）；`xray true` = 只磨砂壁纸。
  - `^omarchy-blurwallpaper$` → `place-within-backdrop true`（overview 模糊壁纸插件，§8 第 10 条）。
  - `^omarchy-bar$` → `background-effect { xray false }`（**只设 xray**，同 keyboard-panel；用户明确不要 xray）。
    浮栏得**半透明**才有霜面可看：`shell.toml [bar] background-alpha 0.45` 喂 `Color.bar.background`，而浮栏插件
    的 `Bar.qml` 不再把该 alpha 强制成 1（niri 补丁第 5 处，§8.11）。
    **圆角区域由客户端下发**：补丁给 bar 的 `PanelWindow` 挂
    `BackgroundEffect.blurRegion: Region { item: barBackground; radius: root.effectiveCornerRadius }`（第 4 处），
    niri 于是只糊 bar 那块**圆角矩形**——这才是"四角亮晕"的正解（niri 采样合成画面、把 bar 自己的填充糊出圆角，
    Hyprland 的 `ignore_alpha` 无等价物，niri issue #1554 未修）。早先（同日早些时候）只是把该 namespace 从
    layer-rule 里摘掉来回避，代价是 bar 没有霜面。
    **实测**：角上 `(17,17)`/`(20,20)` 与不磨砂时**逐像素相同**（无晕）；栏内 `(25,17,20) → (97,95,109)`
    （真透出背后并被模糊）；blur 开/关平均差 3.68、最大 26，同一状态连拍两次差仅 0.07（可复现）。
    透明度是唯一的手感旋钮：`shell.toml [bar] background-alpha`（0.45 现值；调高更暗更清晰、调低更透更糊）。
- `~/.config/omarchy/shell.toml`：`[bar]` background-alpha 0.45、`[popups]` 0.65（原 0.8，
  只为透出磨砂；越低越糊、越高字越清晰）、`[menu]` 0.7、`[notifications]` 0.85、`[tooltip]` 0.85。
  这些喂给 `Color.*.background`（`Color.qml` 的 `composed(...-alpha...)`）。

**热重载**：niri `blur`/layer-rule 经 `niri msg action load-config-file`（热）；QML 改动需重启
quickshell：`pkill -x quickshell && niri msg action spawn -- quickshell -n -p $OMARCHY_PATH/shell`。
`effects.kdl`/`shell.toml` 是 Layer-1，上游 `git pull` 动不到，天然抗更新。

**注意**：`xray false` 是 niri 实验特性——窗口开/关动画、拖拽平铺窗口时磨砂会短暂消失（已知特性，
非 bug）。要稳定（只磨壁纸）就把 `omarchy-keyboard-panel` 那条 layer-rule 的 `xray` 改 `true`。

**验证**：面板开/关截图，屏幕底部清晰度 on/off ≈ 0.995（一致）→ 确认无全屏霜化；仅卡片区域变化。

---

---

32. **吐司"一来通知整屏变糊"：全屏 surface 撞上 niri 侧 `blur true`（2026-09-20，用户 "我的吐司通知,
    现在有blur全屏故障. 我一直没修. 你看看"）**：吐司窗口是**全屏**透明 `PanelWindow`
    （`shell/plugins/notifications/Service.qml`，注释写明"像 OSD 覆盖层那样固定尺寸，免得增删吐司时
    surface 变尺寸、把卡片短暂拉伸"），而 `~/.config/niri/effects.kdl` 里那条
    `background-effect { blur true }` 是 `^omarchy-osd$` 与 `^omarchy-notifications$` **共用**的——
    `blur true` = "整面 surface 都糊"，只有在**卡片大小**的 surface 上才等价于"只糊卡片"。OSD 早先已改成
    卡片大小（§8.8），吐司没有，于是每来一条通知 niri 就把**整屏**霜化。按 §8.8 的老规矩"让客户端下发区域"修：
    ① `effects.kdl` 把这条规则拆开——OSD 保留 `blur true`，通知独立一条**只设 `xray false`**；
    ② `Service.qml` 根 `PanelWindow` 加 `import Quickshell.Wayland._BackgroundEffect` +
    `BackgroundEffect.blurRegion: Region { item: popupColumn; radius: service.cornerRadius }`。
    实测（2560×1600，左下 40%×35% 区域的边缘能量；两次截图之间不产生终端输出以保内容不变，且用
    `~/.local/state/omarchy/notifications/*.json` 确认截图时吐司确实在屏）：修前 有吐司 **8.25** / 无吐司 ~11.8–12.9
    （整屏被糊）→ 修后 有吐司 **14.48** / 无吐司 **14.62**（差 1%，远处不受影响）。
    `niri.patch` 20 文件/36 hunk → **21 文件 / 38 hunk**（重生成务必限路径，§8.7；**新增文件要显式补进
    路径表**，否则下次重放会漏）。回退：`Service.qml.bak-20260920-notifblur` +
    `effects.kdl.bak-20260920-blurnotif` + `niri-port/niri.patch.bak-20260920-notifblur`。
    配置是 Layer-1（改完 `niri validate` 即热加载），仓库内 QML 改完要 `omarchy-restart-shell`。
    两个已知残余：① 区域是**一个矩形**包住整列吐司，所以同时叠两条以上时卡片之间那 8px 缝隙也会被糊到
    （很轻；quickshell 的 `blurRegion` 只收一个矩形）；② §8.8 记过 niri 上 region 几何跟踪会放大
    （OSD 那次实测约 2.6 倍，疑似源于该 surface 会变尺寸）——吐司 surface 固定尺寸，本机实测远处无影响，
    但若卡片周围出现肉眼可见的外溢，最省的回退是把通知那条规则整条删掉（卡片
    `[notifications] background-alpha 0.85`，几乎不透明，霜面本就看不出）。
    排查顺带否掉两个错误猜想（都不是这次的原因）：通知吐司本身是**图层表面**（`PanelWindow`），
    结构上造不出 `xdg_popup must have parent before mapping`；锁屏期间吐司照收照 map，只是 niri 不渲染
    非锁面所以看不见。

---

27. **不透明 app 的磨砂：只写 `background-effect { blur true }` 是看不见的（2026-09-20，用户要求「微信加上 blur，
    我写那个不生效」）**：
    - **根因（官方说法）**：niri wiki 的 Window Effects 页开篇就是「**The window needs to be semitransparent for you to
      see the background effect**（否则被不透明窗口完全盖住）」。微信 Linux 版是 **XWayland** 客户端
      （跑在 `xwayland-satellite` 下、niri 报的 pid 就是 satellite），自己画的是不透明底 —— 所以用户原来那条规则
      （跟 zen 共用一条、带 `background-effect { xray false; blur true }`）**一直在应用，只是没有东西透过来**。
    - **修法**：给窗口压 alpha —— `opacity 0.85`。niri 的 `opacity` 是**动态属性**、**逐 surface** 作用在窗口自身
      不透明度之上（wiki：`Opacity is applied to every surface of the window individually`），客户端自己不肯透明的 app
      只能靠它。顺手把原先与 zen 共用的那条规则拆成两条（zen 照旧 `open-maximized` + blur，不加透明度），微信单独：
      `match app-id="^wechat"` + `open-maximized true` + `opacity 0.85` + `background-effect { xray false; blur true }`。
    - **实测**（`grim` 全屏 → numpy 裁微信窗口内部 1190×1400 物理像素；微信当时占屏幕右半，物理 x 1260..2531）：
      不透明时 `mean=225.3`；加 `opacity` 后 `mean=213.5`、**79.9% 的像素变化 >8**、`平均|Δ|=16.3` → alpha 确实压在
      XWayland 窗口上（反推透出来的背景均值 ≈147，符合壁纸）。模糊是否真起作用：同 opacity 下 blur on/off 对比 →
      `平均|Δ|=4.82`、16.6% 像素 >8，高频能量 `7.33 → 6.76`（模糊后透出来的背景更平滑）。`blur false` 那次是临时改动、
      已恢复；最终配置 `niri validate` 通过、niri 自动重载、journal 无错。
    - **顺手排除一个怀疑**：niri 的 `match` 是 **OR**（wiki：「a window needs to match *any* of the `match` directives」），
      所以"一条规则里两个 `match app-id=`"不是错的，也不需要拆 —— 本次拆开只是为了给微信单独加 `opacity`。
    - **测量踩的坑**：用户当场在别的 workspace 上干活，微信所在工作区一旦不是"当前显示"的那个，截图里就只有壁纸
      （我第一次取到 `mean=70` 就是这种）。要测就先确认窗口真的在屏幕上（本机没装 xdotool/xwininfo，只能用
      「亮色 UI 掩码扫列」或先看 `niri msg workspaces` 的 `active`/`active_window_id`）。
    - 回退：`~/.config/niri/window-rules.kdl.bak-20260920-wechatblur`。另两条 niri 配置通用坑见 §8 第 26 条。

---

### 8.19 全桌面字号 / DPI 一致性：一切向 bar 的 Display 面板看齐（2026-09-20）

需求（原话「所有 APP DPI 和 Text size 都向 bar 上的 monitor 看齐」）：bar 右侧 `omarchy.monitor`
面板（Display：BRIGHTNESS / **TEXT SIZE 12px** / SCALE 2x）是字号与缩放的**唯一基准**，所有应用层对齐它。
用户确认了方向：**多数 app 比 bar 偏大**。

**根因**：官方 `omarchy-display-text-size` 只驱动三处（shell `[font] base-size`、GTK
`text-scaling-factor`、终端 `font-size`），**不管** GTK 的 `font-name` 点数、Qt、fcitx5、GTK2、XSETTINGS。
于是同屏两套量纲：bar 12px vs GTK 应用的 `SF Pro 12` = **16px**（Pango 按 96dpi 折算，12pt=16px）。

**改动全表**（每份配置都有 `.bak-20260920-consistency` 副本；dconf 原值 dump 在
`~/.config/gsettings-interface.backup-20260920.ini`）：

| 层 | 之前 | 之后 |
|---|---|---|
| shell / bar（基准）| `base-size = 12` | 12px（不动）|
| GTK `font-name`（dconf）| `SF Pro 11`（与 settings.ini 的 12 分叉 → 双源不一致）| `SF Pro 9` |
| GTK `settings.ini` ×2 | `SF Pro 12` | `SF Pro 9` |
| GTK2 `.gtkrc-2.0` | `Adwaita Sans 11` + `BreezeX-…-24` | `SF Pro 9` + `Bibata-Modern-Amber 30` |
| Qt（qt6ct）| `Noto Sans CJK SC,12` / `monospace,12` | `SF Pro,9` / `SFMono Nerd Font,9` |
| fcitx5（classicui）| `SF Pro Text 10` / `… 12` | 候选 / 菜单 / 托盘全 `9` |
| XSETTINGS | `~/.xsettingsd` 写死 `Xft/DPI 192`，与 xrdb 的 96 互相打脸 | 合并进 `~/.config/xsettingsd/xsettingsd.conf`（96 + `Gtk/FontName` + Bibata 光标），删掉 `~/.xsettingsd` |
| fontconfig | 没有 `monospace` 别名 → `fc-match monospace` = Noto Sans Mono | 别名 → `SFMono Nerd Font` / `Noto Sans Mono CJK SC` |
| 微信 wrapper | `QT_SCALE_FACTOR=1.25`（scale 2 下等效 0.625）| 删掉，跟随全局 scale 2 |

XWayland 那层**只做减法**：`Xft.dpi` 保持 96（= scale 2 下的逻辑 dpi），不引入 xsettingsd 连动。
（`xsettingsd` 服务在 Wayland 会话里本来也没连上 X root：`xprop -root _XSETTINGS_SETTINGS` 为空。）

**统一入口**：`~/bin/omarchy-display-text-size` 垫片。bar 的 Display 面板滑块是
`Process { command: ["omarchy-display-text-size", px] }`（`shell/plugins/panels/monitor/Panel.qml:336`，走 PATH），
而会话 PATH 第一项就是 `~/bin` → 垫片先接管，写完全部层再 `exec` 官方脚本。
垫片在 `~/bin`，官方包升级不覆盖。**局限**：CLI 路径 `omarchy display text size` 走
`$OMARCHY_PATH/bin` 的绝对路径、绕过垫片，仍只动官方那三处。

**关键坑（实测踩到，第一版垫片就栽在这）**：官方 `factor = round(f*px/12)/f` 里的 `f` 是它
**从 dconf 读到的** `font-name` 的 pt。所以这一层必须**固定钉在基准 9pt**，缩放全部交给 factor。
若把 `font-name` 写成"目标 pt"，`f`（进而量化基准）会跟着漂：滑块拖到 14px 时 GTK 应用会渲染成
`round(11*14/12) = 13pt = 17px`，档位越高越离谱。正确分工：

- **吃 factor 的层（恒 9pt）**：dconf `font-name`/`monospace-font-name`、`gtk-3.0/4.0 settings.ini`、
  XSETTINGS `Gtk/FontName`
- **没有 factor 机制的层（写目标 pt = `round(0.75*px)`）**：Qt、fcitx5、GTK2（`~/.gtkrc-2.0`）、终端（官方脚本）

逐档实测（`12/14/16/20/9/12` 往返）：GTK 侧恒 `SF Pro 9`，Qt/fcitx5 随 px 走 `9/11/12/15/7/9`，
终端 pt 与 shell `base-size` 同步；回到 12 时 `factor` 回到 1.0、终端回 9pt。

**调用留痕**：垫片把每次调用的时间、argv、算出的 pt 追加到
`$XDG_RUNTIME_DIR/omarchy-display-text-size-shim.log`。怀疑"拖了没反应"时先看它：
**有记录** = 面板确实调到了垫片、问题在下游；**没记录** = "滑块 → Process" 那一跳没走通
（面板的 keycatcher/`onReleased`、或 Process 的 PATH 解析）。

**验证**：`~/bin/omarchy-display-text-size` 逐档往返（`12/14/16/20/9/12`）—— shell `base-size` 与终端 pt 同步、
Qt/fcitx5 走目标 pt、GTK 侧恒 9pt 由 factor 承接；回 12 时 factor 1.0 / 终端 9pt。
链路侧另有两处硬证据：① 用 bar 进程自己的 PATH 解析裸命令
（`env -i PATH="$(tr '\0' '\n' < /proc/<qs-pid>/environ | sed -n 's/^PATH=//p')" sh -c 'command -v omarchy-display-text-size'`）
→ 命中 `~/bin` 那份；② `fc-match monospace` = SFMono Nerd Font、`xrdb -query` = 96。
GTK/Qt 应用**重启后才生效**（截图核对：Nautilus 与 bar 文字同档）。
**未做**：真实鼠标拖动/面板键盘导航的端到端复现——`wtype` 在这套 niri 上送不进面板
（发键后 shim 日志为空），面板的 IPC 又只暴露 brightness/state/open/close/toggle，所以"滑块 → Process"
那一跳只能靠上面的日志留痕在真人拖动时核对。

**回退**：恢复各 `.bak-20260920-consistency` + `dconf load /org/gnome/desktop/interface/ < ~/.config/gsettings-interface.backup-20260920.ini` + 删 `~/bin/omarchy-display-text-size`。

**2026-09-20 下半场补记（bar 自身的字号档）**：上面管的是"全局字号向 bar 看齐"，bar **自己**的档位也能调了 ——
上游 `Style.qml` 的 `[bar]` 分支只认两个 size 键，补全后 `shell.toml` 写 `[bar] icon-font = 12` 即可让内置部件的
图标+数字跟纯文本同档（本机现状，整条 bar 都是 12）。详见 §8 第 31 条。

---

---

31. **`[bar]` 段只认 3 个键 → 让 `shell.toml` 能覆盖全部 bar 整型令牌（2026-09-20，起因："bar 上字体是不是有的大有的小" →
    "能不能打补丁似的一样大"）**：起点是实测确有大小不一 —— 左组 `meviusisback.ai-subs` 的 bar 文字硬写
    `Style.font.caption`(10)，比内置部件的数字小一档多（字形高 14–17 vs 19–20 物理像素）；先把它的 5 处提到
    `Style.font.body`(12)（用户先要 13，试完说"太大了，再小点"→ 定 12，详见 `docs/plugins.md` §5.1），
    再让它跟内置部件真正同档：往 `~/.config/omarchy/shell.toml` 写 `[bar] icon-font = 12` —— **不生效**。
    根因在 `shell/Commons/Style.qml` 的 `applyShellValues()`：`[font]`/`[spacing]`/`[controls]` 都接受任意键
    （`fontOut[key] = v`），唯独 `[bar]` 只认 `scale-with-font` + `size-horizontal`/`size-vertical`，
    **其余键静默丢弃** —— 可 `Style.bar` 的 token 本来就是 `barToken(key, fallback)` 从 `barOverrides[key]`
    按名取的，这个字面量白名单纯属漏写。补丁：扩成 `Style.bar` 里全部整型 token（`size-horizontal`/`size-vertical`/
    `icon-slot`/`icon-canvas`/`icon-font`/`status-slot`）→ 以后 `[bar] icon-slot = 30` 之类也能用 shell.toml 热改。
    实测（同一张截图内对比，scale 2 物理像素）：内置部件数字/图标 19–20 / 21–24 → **17–19 / 19–22**（电量 `80%`
    由 19–20 降到 18–19、天气图标 24 → 22），时钟 18–19、ai-subs 17–18 → **全 bar 同一档 12**；残余 ±1 物理 px 是
    "图标字体（`BarIconButton`）vs UI 字体（`WidgetButton`/插件）"的字形度量差，不是档位差。
    ⚠ **别拿不同部件的高度差反推字号**：我自己就用这条把时钟误判成 13 档（其实它一直是 `WidgetButton.fontSize`
    = `Style.font.body` = 12），同档不同字体面就会差 1–2 物理 px。
    `niri.patch` 因此 19 文件/35 hunk → **20 文件 / 36 hunk**（重生成务必限路径，见 §8.7；`--reverse --check` 通过、
    `omarchy-niri-repatch` 幂等）。仓库内 QML 改动要 `omarchy-restart-shell`。
    回退：`shell/Commons/Style.qml.bak-20260920-bartoken` + `niri-port/niri.patch.bak-20260920-bartoken`，
    再把 `shell.toml` 里那行 `icon-font` 撤掉（bar 回到 13 档）。
    排查途中另捡到两件事（都与本条无关但会让人误判"部件坏了"）：① `~/.config/omarchy/shell.json` 里 ai-subs 的
    `barDisplay` 被从 `Data` 切成了 `Icon`（面板底部那个 Icon/Data 开关，点一下就会写回 shell.json），
    bar 上就只剩一个图标、没有用量数字 —— 已按文档恢复 `Data`，快照 `shell.json.bak-20260920-bardisplay`；
    ② 该插件的取数 `Timer` 只在 `refreshIntervalSec`（900s）**到点后**才首次触发，所以**每次重启壳层后 bar 上
    要空最多 15 分钟**才出数字（不是坏了）—— 想立刻要数据用
    `qs -p ~/.local/share/omarchy/shell ipc call meviusisback.ai-subs refresh`（`open`/`close`/`toggle` 同理；
    顺带一提，`qs ipc` 不带 `-p` 会报 "Could not find default config directory"，因为这套壳层的配置不在
    `~/.config/quickshell/`）。

---

28. **bar 的内联部件设置：电量百分比与摘掉 `omarchy.system-update`（2026-09-20，用户 "bar的电池加百分比, 去掉中间的
    omarchy 更新"）**：bar 部件的参数**写在 `shell.json` 的 entry 自己身上**（不是插件目录），电量百分比就是
    `omarchy.power` 加 `"showPercentage": true` —— `panels/power/Panel.qml` 读 `setting("showPercentage", false)`，
    右键点部件图标是同一个开关；`layout.center` 把 `omarchy.system-update` 这条删掉即整块消失（该部件本来就只在
    **有待更新包**时才画东西，平时隐形 —— "看不见它"不等于没生效）。**`shell.json` 是热监听**
    （`shell.qml` 的 `userConfigFile`，`watchChanges: true` + `onFileChanged: reload()`），存盘即生效，
    不必 `omarchy-restart-shell`。实测（bar 条内笔画像素）：最右端 684 → 939（多出电量数字）、中间带 1371 → 1213
    （更新部件消失 + 居中组位移）。回退：`~/.config/omarchy/shell.json.bak-20260920-bar`。
    **同日追加（用户 "百分比放最右边视觉效果更好"）**：上游 `panels/power/Panel.qml` 的 `text` 本来是
    `Math.round(fraction*100) + "% " + batteryIcon()` —— **数字在左、图标在右**（这就是 Omarchy 的默认样子，
    所以 bar 最右那格是电池图标）。改成 `root.batteryIcon() + " " + Math.round(...) + "%"` → 数字落到最右端。
    这是**仓库内文件**，因此 `niri.patch` 从 18 文件/34 hunk 变为 **19 文件/35 hunk**（重生成务必限路径，
    见 §8.7；裸 `git diff` 会把 238 条主题删除一起写进去）；QML 改动要 `omarchy-restart-shell` 才加载。
    （2026-09-20 晚再补 `[bar]` 令牌后为 **20 文件/36 hunk**，见第 31 条。）
    验收用**字形高度指纹**：电池图标比数字高一档（墨高 23 vs 19 物理像素）——改前 h23 块在 x 2493..2515（右端），
    改后落到 x 2431..2454（左端），右端只剩三个 h19 块（`5`/`0`/`%`）。
    回退：`shell/plugins/panels/power/Panel.qml.bak-20260920-pctorder` + `niri-port/niri.patch.bak-20260920-pctorder`。

---

30. **菜单卡片"过于黑"：底色 = 主题 `[menu] background`（2026-09-20，用户 "omarchy menu过于黑了"）**：卡片底色不是
    菜单代码里的常量，而是 `Commons/Color.qml` 从主题 `shell.toml` 的 `[menu] background` 取（模板
    `default/themed/shell.toml.tpl` 里 = `{{ background }}`，本主题即 `colors.toml` 的 `background = #14140c`），
    再乘用户层的 `background-alpha`（现 0.7）。所以"黑"是**底色本身近黑**，跟模糊没关系。改法：在
    `~/.config/omarchy/shell.toml` 覆盖 `[menu] background = "#2a2a22"`（本主题的 `lighter_background`）——
    卡片中位色**（45,38,38）→（60,53,54）**，与模型吻合（0.7×底色 + 0.3×背后模糊壁纸，反推出背后 ≈ (103,80,98)）。
    **这个文件同样是热监听**（`userShellFile` `watchChanges: true` → `reload()`），存盘即变色。
    两个坑：① **颜色 token 只认 `foreground` / `background` / `accent` / `urgent` / `muted` / `text` / `transparent`
    和 shell.toml 里的 `section.key`**（如 `hyprland.active-border-foreground`）—— `colors.toml` 的
    `lighter_background` 之类**不在解析表里**（`loadColors` 只提取 foreground/background/accent/muted/colorN），
    所以这里只能写字面值，而写了字面值**就不再随主题变**（换主题/换壁纸重取色后要回来改）；想要"跟着主题走"就得改
    模板 `shell.toml.tpl` 的 `[menu] background` 为 `{{ lighter_background }}`（会进 patch，需重新生成主题）；
    ② 打开菜单时**整屏变暗来自 `menu.scrim`**（`scrim = {{ background }}` + `scrim-alpha 0.5`：亮壁纸区
    220 → 120，正好压掉一半亮度）——嫌"菜单一开整屏黑"就调 `[menu] scrim-alpha`，别去动卡片底色。
    回退：`~/.config/omarchy/shell.toml.bak-20260920-menu`。

---

29. **窗口缝隙 16 → 8（2026-09-20，用户 "窗口缝隙过大调小些"）**：`~/.config/niri/layout.kdl` 的 `gaps`（逻辑像素，
    内缝与外缝共用一个值；这里没有单独的 `window-gaps`）。实测：窗口**上缘物理 112 → 96**（= 逻辑 56 → 48 =
    32 bar + 8 floatGap + 8 gaps）、**右缘 +16 物理**、整屏 22.6% 像素重排（niri 重载配置即重排，不用重启）。
    `niri msg --json windows` 的 `tile_size` 616×728 → 628×744、`window_size` 612×724 → 624×740。
    **坑：`window_size` 是"减过窗口边框"的数**（`window_offset_in_tile [2,2]` → 每边 2 逻辑），别拿它直接套
    "屏幕 − 2×gaps" 的公式；对几何起疑时以**像素边缘**为准（本机 `tile_pos_in_workspace_view` 恒为 null）。
    `gaps` 只存在于 `layout.kdl` 且不随主题重写（`omarchy-niri-apply-theme` 只插 `focus-ring`/`border` 的颜色块）。
    回退：`~/.config/niri/layout.kdl.bak-20260920-gaps`。

---

18. **弹窗未给浮栏让位（TODO，下次修）**：toast（`shell/plugins/notifications/Service.qml` 的
    `barClearance`）与 `KeyboardPanel` 家族面板（`shell/Ui/KeyboardPanel.qml` 的 `gap`）按固定 bar
    高度算边距、**不计入 `floatGap`**，浮栏（§8.11）启用后这些弹窗的顶边会压住 bar 底缘约 8px。
    首选修法：在这两处各加一个 `barEdgeMargin` 项（`KeyboardPanel.qml` 已在 `niri.patch` 内，
    会让 patch 从 19 个文件涨到 21 个）。零仓库改动的替代：让垫片把 `Style.gapsOut` 报得更大，
    代价是面板间距一起变大。验证：打开托盘面板，量顶边是否 ≥ bar 底缘（物理 y ≈ 80）。

---

### 8.10 主题动态取色（tonal-spot / matugen / materal-update）

需求：换壁纸 → 整个 Omarchy 配色（bar / 菜单 / 终端 / 窗口边框）跟着壁纸走。参考对象是
`github.com/jianlongliu/omarchy-like-niri` 里的 `tonal-spot` 主题（matugen 跑 Material 3 的
tonal-spot 方案），**下放**到本机、不是照抄那台机器。全部落在用户层，`omarchy update` 碰不到。

**四件组成**

| 件 | 路径 | 作用 |
|---|---|---|
| 主题 | `~/.config/omarchy/themes/tonal-spot/` | `matugen.toml`（`scheme="tonal-spot"`、`mode="dark"`）+ `colors.toml` + `backgrounds/` + shell/alacritty 模板 |
| 生成器 | `~/bin/materal-update` | 跑 matugen、映射调色板、重套主题 |
| 钩子 | `~/.config/omarchy/hooks/theme-set.d/20-materal` | 换 theme 后重新取色 |
| 单元 | `~/.config/systemd/user/materal-recolor.{path,service}` | 盯壁纸文件，换壁纸自动重取色 |
| 仓库副本 | `port-bin/materal-update`、`hooks/theme-set.d/20-materal` | 随 INSTALL 第 2/5 步安装；那对 systemd 单元只在本机，未随仓库分发 |

- 主题的 `backgrounds/` 是我们用 `magick … -quality 90` 从上游 `backgrounds.default/*.png` 生成的
  `.webp`（上游只发 `.default` 变体，不生成则主题没有可用壁纸）。
- **ANSI 16（含 orange/brown）保持静态**（抄上游 catppuccin），刻意不跟随壁纸——终端可读性优先。
- 用户主题不被 `omarchy-theme-set` 的"来自仓库"检查过滤（`~/.config/omarchy` 不是 git 仓库 → 走
  `cp -r …/*` 分支），所以 `matugen.toml` 能进 staged 目录。

**命令**

```sh
materal-update            # 按当前壁纸取色并重套主题（幂等）
materal-update <slug>     # 指定主题 slug
materal-update --force    # 忽略"已匹配"判断
materal-update --no-apply # 只写 colors.toml，不重套主题
materal-update --print    # 只打印推导出的调色板
```

**matugen M3 → omarchy `colors.toml` 的映射**（从参考主题反推，无官方文档）

| colors.toml 键 | matugen 来源 |
|---|---|
| `accent` | `primary` |
| `selection` | `primary_container` |
| `muted` | `on_surface_variant` |
| `background` | `surface` |
| `dark_background` | `surface_container_lowest`（精确命中） |
| `darker_background` | `surface_container_lowest` × 0.82 |
| `lighter_background` | `surface_container_high` |
| `foreground` / `light_foreground` / `bright_foreground` | `on_surface` |
| `dark_foreground` | `on_surface_variant` |
| `hyprland_inactive_border` | `outline` + `aa` |
| `hyprland_active_border` | `primary→tertiary→primary_container` 45deg 渐变（`shell.toml.tpl` 也吃这个 token 当 shell 的 active-border） |

交叉验证：同一张壁纸下我们算出 `primary #98ccf9`，参考主题里提交的是 `#97ccf8`——差 1–2 个色阶。

**四个必须知道的坑**

1. **systemd 用户单元的 PATH 极简**：`omarchy theme set` 用**裸名**调用兄弟脚本
   （`omarchy-theme-set-templates`、`omarchy-hook`、`omarchy-restart-*`），而移植的 helper 在 `~/bin`。
   PATH 不全时主题"应用成功"，但 staged 目录里只有主题自带的文件——**没有生成的 `shell.toml` /
   `hyprland.lua` / `alacritty.toml`，钩子也不跑**，全程静默。故 `materal-update` 自己拼 PATH
   （omarchy bin + `~/bin` + `~/.local/bin` + 继承值）并设 `OMARCHY_PATH`。
2. **`PathChanged=<符号链接>` 跟随目标**：改写图片会触发，**改链接指向不会**（`/tmp` 隔离实验确认）。
   所以 path 单元要同时盯 `…/current/` 和 `…/current/background` 两条。
3. **`omarchy theme set` 默认把壁纸推进到主题的下一张**，于是"重取色 → 重套主题 → 又换壁纸"永远追不上，
   生成器描述的总是一张旧图。`materal-update` 用 `OMARCHY_THEME_SKIP_BACKGROUND=1` 关掉这个行为。
4. **幂等判据必须是壁纸的 sha256，不能看 mtime**：staging 会重拷主题背景，时间戳每次都变。

**验证（2026-09-19 实跑）**：`omarchy theme bg next` → path 单元触发 → 服务运行 → staged `colors.toml`
与推导一致、`shell.toml` 已生成、`focus-ring` 已更新、state 文件写入、无残留 guard；重复运行输出
"already matches"（no-op）；`omarchy theme set catppuccin` → `omarchy theme set Tonal-Spot` 钩子同样生效。
像素抽查：近黑壁纸下 bar 填充 (16,19,24) vs 壁纸 (18,20,27)、logo 峰值 (226,226,232)（B−R = 6，中性）。

---

### 8.12 共享壁纸库（omarchy-wallpaper-aio）

需求：不想"切个主题就回到那几张自带图"，而是**所有主题共用一套自己的壁纸库**。参考仓库
`github.com/jianlongliu/omarchy-wallpaper-aio`（2026-09-19 由私有转公开；我们克隆在
`~/omarchy-wallpaper-aio`）：只有 `setup.sh` + README，**不含图、不取色**，只做接线。

**机制**：换壁纸时 Omarchy 合并两处（`omarchy-theme-set` 的 `choose_staged_theme_background`、
`omarchy-theme-bg-next`，都用 `find -L <用户层> <主题层> -maxdepth 1 -type f` + 扩展名过滤）：

1. `~/.local/state/omarchy/current/theme/backgrounds/` —— 当前主题自带；
2. `~/.config/omarchy/backgrounds/<当前主题名>/` —— 用户层。

把 (2) 建成**软链**指向壁纸库，于是切到任何主题翻到的都是同一个库（`find -L` 跟随软链）；
往库里丢图即自动出现，不必重跑脚本、不必重建主题。

**本机接法**

```sh
~/omarchy-wallpaper-aio/setup.sh /data/Pictures/Wallpapers                    # 遍历 ~/.config/omarchy/themes/*
ln -sfn /data/Pictures/Wallpapers ~/.config/omarchy/backgrounds/catppuccin    # 仓库层主题，脚本不管
```

| 主题 | 所在层 | 接线方式 |
|---|---|---|
| `tonal-spot` | 用户层 `~/.config/omarchy/themes/` | `setup.sh` 自动建 |
| `catppuccin` | 仓库层 `~/.local/share/omarchy/themes/` | 手工 `ln -s`（脚本只认用户层主题，其 README 亦注明） |

- **库**：`/data/Pictures/Wallpapers`（71 张，全 png/jpg，无子目录）。路径**大小写敏感**
  （`Pictures/Wallpapers`，不是 `pictures/wallpaper`）。该目录归主账户所有、位于共享数据卷
  `/data`，我们只**读**不写，故不触犯 §1。
- **验证**：用上游同款 `find -L` 合并两个来源 → **75 = 71（库）+ 4（主题自带）**，且库与主题自带
  无同名文件（有重名会让轮换里出现重复项）。
- **还原**：`find ~/.config/omarchy/backgrounds -maxdepth 1 -type l -delete`（只删软链，图不动）。
- **与取色链路的关系**：换图 → path 单元触发 → `materal-update` 重取色（§8.10）。注意
  `materal-update` 把 `current/background` 指向的文件**直接**喂给 matugen、不筛扩展名：库里现在全是图
  没问题；若以后放视频（选择器认 `.mp4/.webm/.mkv` 等），换到视频那次 matugen 会失败、服务非零退出、
  配色停在上一次结果——失败路径**不写 guard**（guard 只在成功写盘后落），不会卡住后续运行。

---

---

### 8.15 overview 模糊壁纸延迟（500ms 轮询 + 每次重解码）（2026-09-19）

**症状**：`Mod+O` / `Mod+Tab` 打开总览时，深色背板先出来，模糊壁纸要"等一下"才补上，观感像掉帧；
关闭时桌面壁纸同样晚一拍。

**测量方法**（`/tmp/ov_lat.py`）：`grim -g "64,495 350x260" -t ppm` 连拍屏幕左下背板区（逻辑坐标 ——
输出 scale 2.0，`grim -g` 吃逻辑像素，写物理坐标会报 "supplied geometry did not intersect"），
判据取**区域亮度均值**：桌面态恒为 ~33，overview 稳定态 ~110，阈值 90。原因是窗口缩略图不在该区，
背板在"模糊壁纸未到位"时是 niri 画的深色垫层（均值 20–40），只有模糊壁纸真的画上去才会变亮。
（早期用"标准差/锐度"当判据都不行：开启动画与壁纸本身的光滑度都会污染，见 §8.15 备注。）

| | 第 1 次 | 第 2 次 | 第 3 次 | 说明 |
| --- | --- | --- | --- | --- |
| 修复前 | 552 ms | 402 ms | 281 ms | 离散 0–500ms = **轮询抖动** |
| 修复后 | 152 ms | 153 ms | 124 ms | 抖动消失 = 事件驱动 |

**成因两条**：

1. `Niri.qml` 每 500ms 轮询 `niri msg -j overview-state`，`Niri.overviewOpen` 最多晚 500ms 翻转，
   `BlurWallpaper.qml` 的图层随之晚映射 → 上表的离散抖动。
2. 该图层关闭时 unmapped，且 `Image { cache: false }`，每次打开都要**重新解码 + 上传**整屏壁纸
   （4K 源图 → 2560×1600）。

**修复**：

- `Niri.qml` 改为**事件流驱动**（细节见 §6）：常驻一个 `niri msg -j event-stream`（`SplitParser` 逐行解析），
  `OverviewOpenedOrClosed` 直接翻转 `overviewOpen`；workspace/window 类事件触发一次去抖 40ms 的全量查询。
  附带收益：空载时不再每 500ms 起 ~6 个 `niri msg` 进程。
- `BlurWallpaper.qml`：`cache: false` → `cache: true`，解码结果留在共享 pixmap cache，重新映射时只做上传。

**A/B：图层要不要常驻映射**（`/tmp/ov_ab_layer.py`，两种状态各一次 14s 采样）：

| 状态 | 打开延迟 | quickshell CPU | niri CPU | 电池功耗 |
| --- | --- | --- | --- | --- |
| 常驻映射（`visible: true`，用 `Image.opacity` 开关） | 118–138 ms | 0.21% | 11.86% | 13.45 W |
| 关闭时不映射（`visible: Niri.overviewOpen`） | 152–163 ms | 0.07% | 9.57% | 13.46 W |

当时的结论是"保守方案"——常驻映射只快 ~40ms，却让 niri 多烧 ~2% 核、功耗无差别，于是让 surface 依旧随
overview 出现/消失。**该结论已被 §8.16 推翻**：延迟判据只量"亮起来要多久"，量不到"背板与窗口动画的先后
顺序反了"；改成常驻映射后两者同步，代价仍是 ~2% 核、功耗无差别。

**备注（判据的坑）**：`标准差` 判据会在开启动画期间从 24 渐升到 64，看起来像"模糊 183–543ms 才到位"，
其实测的是动画结束；用"合成模糊壁纸"做参考图也不可靠（`MultiEffect` 的 blurMax 24–32 + brightness 0.15
与 PIL 的 `GaussianBlur(24)` 不等价，平均差 53–68 分不开）。最终用**亮度均值**这一单调解即可。

---

### 8.16 overview 背板与窗口动画错位（"壁纸和窗口是反的"）（2026-09-19）

**症状**（用户肉眼）：打开总览时窗口先动、模糊壁纸后到；关闭时壁纸先消失，缩略图周围露出一圈暗带，
窗口再慢慢展开。

**测量方法**（这次要看的是"**先后顺序**"，不是"延迟"）：

- 密集采样用 `grim -g "<逻辑坐标>" -t ppm`：**ppm 比 png 快约 10 倍**（~30ms/帧 vs 200–300ms/帧）。
- overview 打开期间整屏 `grim` 本身要 ~300ms/帧，所以先把 niri 动画整体放慢再研究顺序：
  `~/.config/niri/config.kdl` 的 `animations { slowdown 12.0 }` + `niri msg action load-config-file`
  （**不必重启壳层**），测完恢复注释状态 `// slowdown 3.0`。
- 判据用 **1/4 全屏截图（`grim -s 0.25`）的平均亮度**：桌面 110.4、我们的背板 127.3、niri 原生暗背板压到 ~55。
- 坑：工作区是动态的，`niri msg action focus-workspace 3` 可能指向根本不存在的号；工作区上有窗口时整屏均值
  被窗口内容带偏（曾因此整轮复测作废）。改层前后对比务必同场次采集。

| | 打开 | 关闭 |
| --- | --- | --- |
| 每次开关都 map/unmap（原实现） | 背板 60–220ms 后才出现，且**一帧内 +48/+49**（硬闪） | 切换后 ~25ms 背板即不见，露出 niri 自己的暗背板 → 缩略图周围一圈暗带；均值 55.4 起步，随缩略图展开 3.3s 才回到 110 |
| 图层常驻映射（现在） | 平滑 +4.4 / +6.7 / +1.6 / +0.8 … → 127.3 | 平滑 127.3 / 125.0 / 122.9 / 121.3 / 117.2 / 114.2 … → 110.4 |

正速（未放慢）复测同一区域 350×260：打开 `33 → 56 → 82 → 87 → 89 → 91 → 93`（2–3 帧淡入，不再是单帧 +48），
关闭 `92 → 77 → 45 → 33`（平滑落回桌面，中间不出现暗背板值 43）。

**成因**：图层按开关 map/unmap。niri 只在 overview 期间合成 backdrop，映射那一帧要重新渲染整屏模糊并提交，
所以打开时晚到、而且是整块出现；关闭时图层立刻消失，而 niri 仍在画自己的暗背板并展开缩略图 —— 于是出现
"窗口还在动、壁纸已经走了"的反向观感。

**修复**：`plugins/blurwallpaper/BlurWallpaper.qml` 里 `visible: Niri.overviewOpen` → `visible: true`。
niri 只在 overview 内合成 `place-within-backdrop` 的图层，所以桌面**逐像素不变**（实测平均差 0.00、最大 0），
时序完全交还给 niri 自己的动画；`Image { cache: true }` 与 `brightness: 0.15` 都不必动。

**代价与副作用**：overview 关闭时 niri 多约 2% 单核（见 §8.15 的 A/B 表，功耗无差异）；`Niri.overviewOpen`
现在只用于"每次打开时重新解析壁纸软链"，换主题后仍能跟上（路径没变是空操作）。

---

---

10. **overview 背景与桌面不一致（需求，2026-09-03 已修）**：niri 总览（`Mod+O` / `Mod+Tab` 触发
    `toggle-overview`）的背景原本是**不透明深色**，与桌面壁纸不一致。
    - **根因**：overview 开启时 `niri msg layers` 只有 `omarchy-background` + `omarchy-bar`，没有其它
      填充层；把 `config.kdl` 的 `layout { background-color "#ff00ff" }` 设成品红并 `load-config-file`
      后 overview 背景仍是深色——说明深色垫层由 niri 合成器自行绘制、压在 layer-shell 壁纸之上，
      **不吃 `background-color`**，无法靠配置复用桌面壁纸。
    - **修复**：改由移植自有插件在 overview 期间自绘背景 —— `shell/plugins/blurwallpaper/`
      （id `omarchy.blurwallpaper`，kind `service`）渲染强模糊壁纸；该图层**常驻映射**（`visible: true`），
      由 niri 只在 overview 内合成，时序因此和窗口动画一致（§8.16）。`effects.kdl` 给该 namespace 配
      `place-within-backdrop true`；`Niri.overviewOpen`（2026-09-19 起由事件流推送，见 §8.15）现仅用于
      打开时重解析壁纸软链。

---

13. **Ghostty 磨砂模糊（2026-08-26 已修）**：见 §5.8。niri 侧 `background-effect {xray true; blur true}`
   给 `com.mitchellh.ghostty` frost 壁纸（niri 不实现 KDE blur 协议，故 ghostty 自带
   `background-blur-radius` 在 niri 上无效、且关掉避免双层模糊）。根因坑：niri 默认把焦点环画在
   窗口**背后**的实心矩形，半透明窗口会把它透出来，且**只有聚焦窗口有焦点环** → 只有选中窗口
   "诡异"。`draw-border-with-background false` 让焦点环画在窗口周围解决。ghostty
   `background-opacity = 0.85` 提供半透明载体。
   **这一处对应的文件 2026-09-20 才进仓库**：`local-config/ghostty/config`（+ 它 `theme = dankcolors`
   指向的 `local-config/ghostty/themes/dankcolors`）。此前仓库 `config/ghostty/config` 是上游默认，
   于是"磨砂五处"里 ghostty 这处整个缺失 —— 别人照旧仓库装只会得到"有装饰、无磨砂"。

---

4. **显示器缩放 SCALE 生效**：`omarchy-hyprland-monitor-scaling` → `hyprctl eval hl.monitor(...)` 被
   `_eval_monitor` 处理。原实现把 `mode`+`scale`+`position` 塞进**一次** `niri msg output`，而 niri
   一次只能接受一个 action，导致整条命令失败、scale 不生效（字体大小走 shell 内部所以正常）。
   现拆成独立多次 `niri msg output` 调用，并**跳过 `mode`**（Omarchy 重发当前 `WxH@Hz` 会被 niri 拒绝，
   且输出本就在该模式上）。验证：1.5→1.6 生效。

---

1. **CLI 依赖已装**：`jq` / `satty` / `inotify-tools` 已用 `pkexec pacman -S --needed jq satty inotify-tools` 装好
   `wl-clipboard`（`wl-copy`/`wl-paste`）系统自带，`swappy`（可选截图编辑器）仍缺，非核心。
   Omarchy 的 `bin/` CLI 脚本（截图、剪贴板等）此前因缺 jq 报错，现已正常。
   另装 **`qt6-imageformats`**（`pkexec pacman -S --needed qt6-imageformats`）：提供 Qt 的 webp
   图像插件（`libqwebp.so`）。此前缺它，Qt Quick 无法解码 Omarchy 的 `.webp` 壁纸 → 桌面背景全黑，
   bar 用 QML 渲染所以正常。这是"没有壁纸"的真正根因。

---

1b. **壁纸/背景已修**（2026-08-24）：除装 `qt6-imageformats` 外，两处代码改动——
   - `shell/plugins/background/Background.qml`：`readlinkProc` 回调改用 `transitionBackground("",p,p,true,true)`
     （force+instant）。避免切换主题时 `currentBackground` 已等于链接目标、而 `displayedBackground`
     还停在已删除的过渡快照上被短路卡死；强制让实时背景链接始终覆盖。
   - `bin/omarchy-theme-set`：`set_theme_background` 的 `background themeTransition` 改为传**实际背景文件**
     （old/new），不再传会被 `sleep 3`+`rm` 提前删除的 `next-/previous-*.webp` 快照，消除异步加载竞争。
   - 验证：`grim` 截图底部条带出现波纹高光像素（壁纸已显示）。
