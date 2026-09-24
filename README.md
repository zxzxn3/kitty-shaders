# kitty 自定义 shader

| pipeline | 做什么 | 用掉的资源 | 额外需要的 kitty 选项 |
| --- | --- | --- | --- |
| `ink-stain` | 光标走过的地方洇开白色水痕，慢慢干掉 | `persist.r` `.a`、scratch `a` | `cursor_trail`、`cursor_trail_start_threshold 1` |
| `inactive-fade` | 失去焦点的窗口、没聚焦的分屏，颜色往黑白去 | 无 | 无 |
| `focus-pulse` | 窗口获得焦点时内容区边缘有一次很轻的呼吸 | 无 | 无 |

## 三个效果是独立的，可以按需挑

它们互不依赖：`ink-stain` 用了 `persist` 的 `.r` 和 `.a`（`.a` 是 1.0 哨兵，用来
分辨「我们写过这块像素」和「显存里是没初始化的垃圾」），另外两个**完全不碰
persist**，也没有共用 scratch。每条管线的最后一组都写回 backbuffer，满足 kitty 对
「最后一条管线最后一组」的要求，所以：

* 任意子集、任意顺序都能加载（把不要的从 `custom_shaders` 里去掉即可）
* 每条管线单独也能加载
* 想同时用几个就写几个，组数是它们相加（墨 3 + 淡 2 + 脉动 1 = 6，上限 16）

这不是推断：7 种组合（3 个单条 + 3 个两两 + 1 个全部）全部编译验证过。

## 参数放在哪

约定：**每个效果的日常旋钮都写在它自己的 `.pipeline` 里**（用 `var` 覆盖），
`.slang` 里保留默认值和实现细节。这样调参只要开一个文件，而且像「变干时间和动画
窗口必须配套」这种跨文件的耦合，现在两个数就在隔壁。

参数名按效果加了前缀（`INK_` / `FADE_` / `PULSE_`），这不是洁癖：**管线级 `var`
是全局按名字正则替换的**，两个效果如果用了同名常量，后一条管线的值会覆盖前一条，
而且不会有任何提示。

## 启用

`~/.config/kitty/kitty.conf`：

```conf
custom_shaders ink-stain inactive-fade focus-pulse
# 墨的坐标只能从拖尾几何里拿。默认阈值 2 会跳过单格移动，打字就不出墨。
cursor_trail_start_threshold 1
```

多条 pipeline 按声明顺序串联执行。上面三个全开时是 6 个组。

## 改完怎么生效

kitty 重载配置时会重新编译 shader，不用重启。但注意：**`auto_reload_config` 只监听
配置文件本身，不监听 `shaders/` 目录**——只改 shader 文件不会自动生效。所以
`kitty.conf` 里放了一个 `shader-rev` 计数，改 shader 时顺手把它 +1，自动重载就会
被触发。也可以手动：`kill -SIGUSR1 $KITTY_PID`，或者按 `ctrl+shift+f5`。

---

## inactive-fade —— 不活跃的部分颜色变淡

就这么多：没有渐变、没有计时、没有跨帧状态，因此也没有「时间参数必须和动画窗口
配套」这类耦合。两个组互斥，各自只在对应状态下活跃，所以永远只上色一次：

* 失焦期间 → 整个窗口去饱和
* 有焦点期间 → 没聚焦的分屏去饱和（活动分屏照常）

### 只有一个 shader 文件

`inactive-fade.slang` 被两个组复用，区别只有一个 `WHOLE_WINDOW` 开关，在 pipeline
里按组覆盖：

```
var bool WHOLE_WINDOW true      # 只写在失焦那一组里
```

组级 `var` 会覆盖管线级，而且 kitty 是**按「组 + shader」组合分别编译**的，所以
失焦那组的特化里遮罩代码会被死代码消除掉。可以直接在编译产物里看到：

```bash
grep -A3 'fragment_main_3_0_0' ~/.cache/kitty/shaders/*/glsl/end.frag.glsl
```

### 为什么用事件而不是时长

两个组都只写 `animation_start` / `animation_stop` 的事件，不写时长——没有时长就
没有「窗口比动画短/长」这类问题。`animation_step 0` 的含义是不申请周期性帧
（kitty 内部把它转成 `MONOTONIC_T_MAX`），所以它只在别的原因触发重绘时跟着走；
焦点变化本身就会触发重绘，效果立刻出现，空闲时零开销。

### 可调参数

都在 `inactive-fade.pipeline` 顶部的 `var` 里（shader 里是默认值）：

| 参数 | 作用 |
| --- | --- |
| `FADE_DIM` | 亮度系数，1.0 = 完全不动亮度（当前）；想额外压暗就往下调 |
| `FADE_DESAT` | 去多少饱和，0.0 = 不动，1.0 = 彻底黑白。含义是保留 (1 - FADE_DESAT) 的色度 |
| `FADE_EDGE_PX` | 分屏边界羽化多少像素（只对分屏那组有意义） |

**这个效果对白字完全无效**：白色没有色相，去饱和算出来还是白色。所以只有当屏幕上
真有彩色内容（`ls` 的颜色、语法高亮、彩色提示符、图片）时才看得出来。如果你希望
失去焦点的窗口看起来更"退后"一点，把 `DIM` 设成 0.92 左右，那是一档几乎察觉不到
的压暗，但能让黑白内容也有反应。

### 已知边界

如果 kitty 启动时窗口本来就是失焦的，两个组都不会被触发（事件只在变化时发），
那个窗口会保持原色，直到你聚焦它再失焦一次。

---

## ink-stain —— 墨痕

光标走过的地方洇开白色水痕，慢慢干掉。墨只落在背景像素上，字一个像素都不碰。

### 三个组在做什么

1. `ink-stain-accumulate` — 让已有的墨按真实经过的时间衰减，再把当前这一笔点到
   墨迹图上，结果写进临时纹理 `a`
2. `ink-stain-commit` — 把 `a` 搬回 `persist`
3. `ink-stain-composite` — 把墨洇进背景像素，写回 backbuffer

第 1、2 步必须分开：同一趟里既读又写同一个命名纹理时，kitty 会把输入换成
backbuffer，墨迹图就永远不更新，而且不会报错。

三组全部挂在事件上（第一组订阅 `cursor-trail-move | user-activity`，后两组
`attach`），所以空闲时整个管线不运行。

### 可调参数

日常要动的三个都在 `ink-stain.pipeline` 顶部的 `var` 里：

| 参数 | 作用 |
| --- | --- |
| `INK_DRY_TIME` | 变干的时间常数，秒。越小收得越快。和同文件的 `animation_stop` 是一对 |
| `INK_STRENGTH` | 最浓时往墨色混多少 |
| `INK_COLOR` | 墨色，默认纯白 |

其余是实现细节，留在 `ink-stain-accumulate.slang` / `ink-stain-composite.slang`
里，一般不用动：

| 参数 | 作用 |
| --- | --- |
| `NIB_RADIUS` | 笔尖半径，像素 |
| `NIB_CORE` | 笔尖中心实心部分占半径的比例，越小越柔 |
| `NIB_STRENGTH` | 一笔的墨量 |
| `DRY_EPSILON` | 低于它就当干了，防止残影 |
| `DRAIN_PER_SECOND` | 指数衰减之外每秒线性刮掉多少 |
| `SOAK_TIME` | 墨洇上来的时间常数，越大起笔越软（0 = 啪地出现） |
| `SOAK_MAX_STEP` | 上升过程单帧最多算多少秒（防止空闲后第一帧一步到位） |
| `MOVING_WINDOW` | 「笔还在动」的判定窗口，秒 |
| `INK_ALPHA_BOOST` | 积墨处不透明度往 1 靠多少 |
| `BG_TOLERANCE` | 背景判定容差（线性 RGB） |

### 三档预设

| | 极淡 | 现在这档 | 明显 |
| --- | --- | --- | --- |
| `INK_STRENGTH` | 0.10 | 0.20 | 0.35 |
| `NIB_STRENGTH` | 0.35 | 0.55 | 0.75 |
| `INK_ALPHA_BOOST` | 0.20 | 0.40 | 0.70 |
| `INK_DRY_TIME` | 0.55 | 0.85 | 1.20 |

### 变干时间和动画窗口是一对

墨只能在有帧的时候继续变干，所以

```
animation_stop ≈ 4 × DRY_TIME
```

窗口短了，最后一帧会留下没干完的墨，它会被冻在屏幕上不再变化，直到下次触发才
突然消失——看起来就像闪一下。改了 `DRY_TIME` 记得同步改 `animation_stop`。

### 注意

订阅 `cursor-trail-move` 之后，kitty 内置的拖尾绘制会被完全抑制（shader 接管）。
想让它回来共存，把 pipeline 第一组的 `animation_start` 改成只留 `user-activity`。

---

## focus-pulse —— 获得焦点时边缘的呼吸

一个窗口获得焦点时，内容区（不含标签栏那一条）边缘浮起一条很淡的光带，
约 700ms 起落一次。

### 怎么做的

单组、事件驱动、无状态：`animation_start os-window-focus-in` 配 `animation_stop 600`，
强度按「到边缘的像素距离」衰减成 `BAND_PX` 宽的一条带，envelope 是
`(1 - p) * smoothstep(0, ATTACK, p)`——平滑起手约 70ms，然后落下。

**判据为什么是 `os-window-focus-in`**：它只在「这个 OS 窗口获得键盘焦点」时触发，
而且触发在获得焦点的那个窗口上。所以脉动出现在新窗口——旧窗口收到的是
`os-window-focus-out`。（一开始我用的是 `user-activity`，那是"这个窗口收到了键盘
或鼠标输入"，于是点别的窗口时脉动落在了旧窗口，打字时又一路触发。判据用错，症状
就是这两条。）

`animation_step 16` 只在动画那 600ms 里要帧，其余时间这个组不活跃，所以开销为零。

### 一个附带的已知行为

kitty 在管线载入后的第一帧也会补发一次 `os-window-focus-in`，所以每次重载配置时
当前窗口也会脉动一下。当成"shader 已经重新加载"的信号挺好用的，不用管它。

### 可调参数

都在 `focus-pulse.pipeline` 顶部的 `var` 里（shader 里是默认值）：

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

`inactive-fade` 前面试过三版，都留在 git 里，需要时可以翻：

| 提交 | 是什么 | 为什么放弃 |
| --- | --- | --- |
| `0c4af9c` | `sleep-wake`：失焦渐入睡 + 醒来过冲 | 为了一个简单的诉求引入了两段动画和状态机 |
| `fed46a9` | `pane-fade`：只按分屏判定，纯去饱和 | 白字去饱和等于没变；且完全没覆盖窗口维度 |
| `a341611` | `inactive-fade`：两个维度 + 5 秒渐变 | 渐变需要计时，计时需要跨帧状态，复杂度上来了 |

现在是 `a341611` 的简化版：保留两个维度，去掉渐变，于是也去掉了 persist、
commit 组、时长参数和通道协议。
