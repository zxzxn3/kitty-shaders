# kitty 自定义 shader

两个效果，共用一块 `persist` 纹理：

| pipeline | 做什么 | 占用 persist 通道 |
| --- | --- | --- |
| `ink-stain` | 光标走过的地方洇开白色水痕，慢慢干掉 | `.r` = 墨量 |
| `sleep-wake` | OS 窗口失焦时像睡着，回来时像醒来 | `.g` = 睡意 |

`.a` 是 1.0 哨兵，用来分辨「这块像素我们写过」和「显存里是没初始化的垃圾」。
`.b` 留着给下一个效果。

**每个 writer 只能更新自己的通道**，其余通道要从 `persist` 原样带走——两个 pipeline
写的是同一块纹理，谁也不能整块覆盖，否则会把对方的状态抹掉。中转用的 scratch 也各用各的：
`ink-stain` 用 `a`，`sleep-wake` 用 `b`。因此两条管线在 `custom_shaders` 里的先后顺序
目前不影响结果，但仍建议按效果顺序排列，便于阅读。

---

## ink-stain —— 墨痕

光标走过的地方洇开白色水痕，慢慢干掉。背景保持原样，墨只落在背景像素上，
字一个像素都不碰。

## 怎么启用

`~/.config/kitty/kitty.conf` 里加两行：

```conf
custom_shaders ink-stain
# 光标移动一格就允许起拖尾。墨的坐标只能从拖尾几何里拿，
# 默认值 2 会跳过单格移动，打字时就不会出墨。
cursor_trail_start_threshold 1
```

## 三个组在做什么

1. `ink-stain-accumulate` — 让已有的墨按真实经过的时间衰减，再把当前这一笔点到墨迹图上，
   结果写进临时纹理 `a`
2. `ink-stain-commit` — 把 `a` 搬回 `persist`
3. `ink-stain-composite` — 把墨洇进背景像素，写回 backbuffer

第 1、2 步必须分开：同一趟里既读又写同一个命名纹理时，kitty 会把输入换成 backbuffer，
墨迹图就永远不更新，而且不会报错。

三组全部挂在事件上（第一组订阅 `cursor-trail-move | user-activity`，后两组 `attach`），
所以空闲时整个管线不运行。没有 `animation_start` 的组会被 kitty 当成常驻活动，
会让它一直重绘，这里刻意避免了。

## 可调参数

在 `ink-stain-accumulate.slang` 里：

| 参数 | 作用 |
| --- | --- |
| `DRY_TIME` | 变干的时间常数，秒。越小收得越快 |
| `NIB_RADIUS` | 笔尖半径，像素 |
| `NIB_CORE` | 笔尖中心实心部分占半径的比例，越小越柔 |
| `NIB_STRENGTH` | 一笔的墨量 |
| `DRY_EPSILON` | 低于它就当干了，防止残影 |
| `DRAIN_PER_SECOND` | 指数衰减之外每秒线性刮掉多少 |
| `SOAK_TIME` | 墨洇上来的时间常数，越大起笔越软（0 = 啪地出现） |
| `MOVING_WINDOW` | 「笔还在动」的判定窗口，秒 |

在 `ink-stain-composite.slang` 里：

| 参数 | 作用 |
| --- | --- |
| `INK_COLOR` | 墨色，默认纯白 |
| `INK_STRENGTH` | 最浓时往墨色混多少，决定墨的亮度 |
| `INK_ALPHA_BOOST` | 积墨处不透明度往 1 靠多少 |
| `BG_TOLERANCE` | 背景判定容差（线性 RGB） |

这些都可以不改 shader，直接在 pipeline 里覆盖：

```
var float INK_STRENGTH 0.15
var float3 INK_COLOR float3(0.8, 0.85, 1.0)
```

## 改完怎么生效

kitty 重载配置时会重新编译 shader（重载路径最后会调 `shaders.slang.clear_caches()`），
所以不用重启 kitty。重载方式：改一下 `kitty.conf` 让它自动重载，或者
`kill -SIGUSR1 $KITTY_PID`，或者按 `ctrl+shift+f5`。

## 三档预设

觉得当前这档不合适，照这个表换数字：

| | 极淡 | 现在这档 | 明显 |
| --- | --- | --- | --- |
| `INK_STRENGTH` | 0.10 | 0.20 | 0.35 |
| `NIB_STRENGTH` | 0.35 | 0.55 | 0.75 |
| `INK_ALPHA_BOOST` | 0.20 | 0.40 | 0.70 |
| `DRY_TIME` | 0.55 | 0.85 | 1.20 |

## 变干时间和动画窗口是一对

`DRY_TIME` 是「墨多快干」，pipeline 里的 `animation_stop` 是「kitty 多快停止为这个效果画帧」。
两者必须配套：墨只能在有帧的时候继续变干，所以

```
animation_stop ≈ 4 × DRY_TIME
```

窗口短了，最后一帧会留下没干完的墨，它会被冻在屏幕上不再变化，直到下次触发才突然消失——
看起来就像闪一下。改了 `DRY_TIME` 记得同步改 `animation_stop`。

### 注意

订阅 `cursor-trail-move` 之后，kitty 内置的拖尾绘制会被完全抑制（shader 接管）。
想让它回来共存，把 pipeline 第一组的 `animation_start` 改成只留 `user-activity`。

---

## sleep-wake —— 睡着与醒来

OS 窗口失焦时，文字在 0.85 秒里慢慢退掉颜色、暗下来；回到窗口时 0.38 秒恢复，
末尾还有一记很轻的过冲（那段曲线故意让 `cubic-bezier` 的 y 超过 1，睡意短暂变负，
apply 把负值解释成「亮一点点」）。

背景一个像素都不动——你的背景是纯黑，压暗去饱和都看不出变化，效果全在文字上。

### 四个组在做什么

1. `sleep-wake-dim` — 失焦后 0.85 秒把睡意推到 1，写进临时纹理 `b`
2. `sleep-wake-commit` — 把 `b.g` 并回 `persist`，另外两个通道原样保留
3. `sleep-wake-rise` — 聚焦后 0.38 秒把睡意拉回 0，过冲时变负
4. `sleep-wake-apply` — 应用睡意，**常驻**但 `animation_step 0`

`animation_step 0` 的含义是「不申请周期性帧」：kitty 内部会把这个值转成
`MONOTONIC_T_MAX`，所以这个常驻组只在别的重绘发生时跟着走，空闲时不会自己空转。
自带的 `dim-inactive-windows` 用的就是同一个套路。

### 可调参数

在 `sleep-wake-apply.slang` 里：

| 参数 | 作用 |
| --- | --- |
| `SLEEP_DIM` | 睡着时内容保留多少亮度，0.80 |
| `SLEEP_DESAT` | 睡着时去掉多少饱和度，0.55 |
| `SLEEP_TINT` | 睡着时的色偏，默认极轻的冷调 |
| `WAKE_GAIN` | 醒来那记过冲的强度，设 0 就关掉 |

时间在 pipeline 里：`animation_stop 850`（入睡）、`animation_stop 380`（醒来），
曲线紧跟其后。想让入睡更慢就一起调大这两个数。

### 一个已知的小瑕疵

kitty 在管线载入时会补发一次 `os-window-focus-in`，所以刚载入时会有一次极轻微的提亮
（约 1%，几十毫秒，只作用在文字上）。不想要就把 `WAKE_GAIN` 设成 0。
