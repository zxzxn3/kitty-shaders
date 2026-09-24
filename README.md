# kitty 自定义 shader

四个效果，随便挑。都不使用命名纹理——没有 `persist`、没有临时纹理、没有跨帧状态。

| pipeline | 做什么 | 额外需要的 kitty 选项 |
| --- | --- | --- |
| `ink-stroke` | 光标移动时留下一道柔和的白色笔触 | `cursor_trail`、`cursor_trail_start_threshold 1` |
| `layout-fade` | 当前窗口里没聚焦的分屏，颜色往黑白去 | 无 |
| `window-fade` | 失去焦点的那个 OS 窗口，整窗颜色往黑白去 | 无 |
| `focus-pulse` | 窗口获得焦点时内容区边缘有一次很轻的呼吸 | 无 |

## 四个效果互相独立，按需挑

它们各写各的 backbuffer 输出，不共享状态或资源；每条管线的最后一组都写回
backbuffer，满足 kitty 对「最后一条管线最后一组」的要求。所以：

* 任意子集、任意顺序都能加载——把不想要的名字从 `custom_shaders` 里去掉即可
* 每条管线单独也能加载（只留 `focus-pulse` 也行）
* 组数是相加：1 + 1 + 1 + 1 = 4（上限 16）

这不是推断：**15 种组合**（4 个单条 + 6 个两两 + 4 个三三 + 1 个全部）全部编译验证过。

`layout-fade` 和 `window-fade` 是两个独立管线，但共用同一个 shader 文件
`fade.slang`，靠组内变量 `WHOLE_WINDOW` 区分行为——kitty 按「组 + shader」分别编译，
所以那是两份独立特化，不是运行时分支。

## 参数放在哪

**每个效果的旋钮都写在它自己的 `.pipeline` 里**，用 `var` 覆盖 shader 的默认值。

有一条必须遵守的规则：**写在组内（group-level），不要写在管线顶层**。管线级 `var`
是全局按名字正则替换的，两个效果如果用了同名常量，后一条管线的值会静默覆盖前一条。
`layout-fade` 和 `window-fade` 共用 `fade.slang`、常量名完全相同（`FADE_*`），所以
两边的值都必须写在各自的组里，否则会互相覆盖。

其余效果的参数名也按效果加了前缀（`INK_` / `PULSE_`），理由相同。

## 启用

`~/.config/kitty/kitty.conf`：

```conf
custom_shaders ink-stroke layout-fade window-fade focus-pulse
# 笔触的坐标只能从拖尾几何里拿。默认阈值 2 会更晚起拖尾，打字时笔触更少。
cursor_trail_start_threshold 1
```

多条 pipeline 按声明顺序串联执行。

## 改完怎么生效

kitty 重载配置时会重新编译 shader，不用重启。但注意：**`auto_reload_config` 只监听
配置文件本身，不监听 `shaders/` 目录**——只改 shader 文件不会自动生效。所以
`kitty.conf` 里放了一个 `shader-rev` 计数，改 shader 时顺手把它 +1，自动重载就会
被触发。也可以手动：`kill -SIGUSR1 $KITTY_PID`，或者按 `ctrl+shift+f5`。

（顺带一提：每次重载 kitty 都会重新跑一遍 `slangc`，实测量级约 1 秒，和效果数量
关系不大——固定的几步占据了大部分时间。）

---

## ink-stroke —— 白色笔触

光标移动时留下一道柔和的白色笔触，只压在背景像素上，字一个像素都不碰。

单组、事件驱动、无状态：从 `cursor-trail-move` 到 `cursor-trail-stop`，每帧按当前
的拖尾几何（上一笔中心 → 这一笔中心）画一道软边笔尖。淡出交给 kitty 自己的拖尾
衰减，所以这里没有任何时间参数。

### 两处已知的取舍

* **墨不会留在屏幕上。** 淡出速度由 `cursor_trail_decay` 决定（默认 0.1–0.4 秒）。
  想让笔触留久一点就调它，例如 `cursor_trail_decay 0.3 0.8`——那是 kitty 原生
  选项，不是 shader 代码。
* **起笔是立即的，没有渐入**，而且光标只移动一格时可能不起拖尾
  （`cursor_trail_start_threshold` 的比较用的是 `<=`，所以阈值 1 实际要求移动 2 格；
  打字时连续几笔会累积到这个距离，所以第一笔可能没有笔触）。自带的那几个拖尾
  shader 也是这个行为。

### 可调参数

都在 `ink-stroke.pipeline` 的组内：

| 参数 | 作用 |
| --- | --- |
| `INK_STRENGTH` | 最浓时往墨色混多少，0.12 约等于原来墨痕刚落笔时那一档 |
| `INK_COLOR` | 墨色，默认纯白；写法 `float3(r, g, b)` |

笔尖半径、软边比例、背景容差是 `ink-stroke.slang` 里的实现细节，一般不用动。

---

## layout-fade / window-fade —— 不活跃的部分颜色变淡

两个维度，一个 shader（`fade.slang`），两组参数：

* **`window-fade`**：这个 OS 窗口失去焦点 → 整窗去饱和
* **`layout-fade`**：当前窗口里没聚焦的分屏 → 那些分屏去饱和（活动分屏照常）

两个组互斥，各自只在对应的状态下活跃，所以同时启用也永远只上色一次：

| pipeline | 触发 | 停止 |
| --- | --- | --- |
| `window-fade` | `os-window-focus-out` | `os-window-focus-in` |
| `layout-fade` | `os-window-focus-in` | `os-window-focus-out` |

两者都只用事件、不写时长。`animation_step 0` = 不申请周期性帧（kitty 内部把它转成
`MONOTONIC_T_MAX`），只在别的原因触发重绘时跟着走；焦点变化本身就会触发重绘，
所以效果立刻出现，空闲时零开销。

`window-fade` 那组把 `WHOLE_WINDOW` 覆盖成 `true`，于是完全不需要遮罩；`layout-fade`
那组用 `d.active_window_geometry` 判断像素在不在活动分屏里，边界用 `fwidth` 换算成
像素、按 `FADE_EDGE_PX` 羽化，所以交界处没有硬边。只有一个分屏时整屏都在活动窗口
里，`layout-fade` 等于不生效。

### 可调参数（两组各写各的）

| 参数 | 作用 |
| --- | --- |
| `FADE_DESAT` | 去多少饱和，0.0 = 不动，1.0 = 彻底黑白。含义是保留 (1 - FADE_DESAT) 的色度。当前 0.45 |
| `FADE_DIM` | 亮度系数，1.0 = 完全不动亮度（当前）；想额外压暗就往下调 |
| `FADE_EDGE_PX` | 分屏边界羽化多少像素（只有 `layout-fade` 用得到） |

因为写在组内，两个维度可以分别调——比如让分屏淡得更狠、整窗淡得轻一点。

### 对白字完全无效

白色没有色相，去饱和算出来还是白色。所以只有当屏幕上真有彩色内容（`ls` 的颜色、
语法高亮、彩色提示符、图片）时才看得出来。如果你希望失去焦点的窗口看起来更"退后"
一点，把 `FADE_DIM` 设成 0.92 左右——那一档几乎察觉不到，但能让黑白内容也有反应。

### 一个已知边界

如果 kitty 启动时窗口本来就是失焦的，两个组都不会被触发（事件只在变化时发），
那个窗口会保持原色，直到你聚焦它再失焦一次。

---

## focus-pulse —— 获得焦点时边缘的呼吸

一个窗口获得焦点时，内容区（不含标签栏那一条）边缘浮起一条很淡的光带，约 700ms
起落一次。

单组、事件驱动、无状态：`animation_start os-window-focus-in` 配 `animation_stop 600`，
强度按「到边缘的像素距离」衰减成 `PULSE_BAND_PX` 宽的一条带，envelope 是
`(1 - p) * smoothstep(0, PULSE_ATTACK, p)`——平滑起手约 70ms，然后落下。

**判据为什么是 `os-window-focus-in`**：它只在「这个 OS 窗口获得键盘焦点」时触发，
而且触发在获得焦点的那个窗口上。所以脉动出现在新窗口——旧窗口收到的是
`os-window-focus-out`。（一开始用的是 `user-activity`，那是"这个窗口收到了键盘或
鼠标输入"，于是点别的窗口时脉动落在旧窗口、打字时又一路触发。判据用错，症状就是
这两条。）

`animation_step 16` 只在动画那 600ms 里要帧，其余时间这个组不活跃，所以开销为零。

kitty 在管线载入后的第一帧也会补发一次 `os-window-focus-in`，所以每次重载配置时
当前窗口也会脉动一下。当成"shader 已经重新加载"的信号挺好用的，不用管它。

### 可调参数

都在 `focus-pulse.pipeline` 的组内：

| 参数 | 作用 |
| --- | --- |
| `PULSE_PEAK` | 最亮时叠多少，0.05 线性约等于 sRGB 0.24 |
| `PULSE_BAND_PX` | 光带宽度，像素 |
| `PULSE_ATTACK` | 起手用掉整段动画的比例，0.12 ≈ 70ms |

它是在当前颜色上做加法（不动 alpha），所以在纯黑背景上就是一层很淡的灰。嫌它吵就
把 `PULSE_PEAK` 降到 0.02，或者直接从 `custom_shaders` 里去掉这个名字。

想让它也在切换分屏时脉动，把 pipeline 里那行改成
`animation_start os-window-focus-in | window-focus-in` 即可。

---

## 历史

都是迭代出来的，旧版本留在 git 里：

| 提交 | 是什么 | 为什么换掉 |
| --- | --- | --- |
| `0c4af9c` | `sleep-wake`：失焦渐入睡 + 醒来过冲 | 为了一个简单诉求引入两段动画和状态机 |
| `fed46a9` | `pane-fade`：只按分屏判定，纯去饱和 | 白字去饱和等于没变；且完全没覆盖窗口维度 |
| `a341611` | `inactive-fade`：两维度 + 5 秒渐变 | 渐变需要计时，计时需要跨帧状态 |
| `c95a594` | `ink-stain`：三趟、persist 累积、慢慢干掉 | 占了全部代码的 58%，却只多出"留在屏上"这一个特性 |
| `503a09b` | `ink-stroke` + 合并的 `inactive-fade` | 两个维度没法单独开关，不符合"按需挑" |

现在这版：4 个独立效果、4 个组、零跨帧状态、没有任何命名纹理。
