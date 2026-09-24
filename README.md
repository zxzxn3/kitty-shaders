# kitty 自定义 shader

两个效果，都只动内容像素、不碰背景——背景是纯黑，压暗和去饱和在黑色上算出来
还是黑色，所以效果自然只落在文字和有颜色的内容上。

| pipeline | 做什么 | 跨帧状态 |
| --- | --- | --- |
| `ink-stain` | 光标走过的地方洇开白色水痕，慢慢干掉 | `persist.r` = 墨量 |
| `pane-fade` | 只有聚焦的分屏正常，其它分屏颜色变淡 | 无，纯无状态 |

## 启用

`~/.config/kitty/kitty.conf`：

```conf
custom_shaders ink-stain pane-fade
# 墨的坐标只能从拖尾几何里拿。默认阈值 2 会跳过单格移动，打字就不出墨。
cursor_trail_start_threshold 1
```

多条 pipeline 按声明顺序串联执行，共用一块 `persist` 纹理。目前只有 `ink-stain`
用它：`.r` 存墨量，`.a` 存 1.0 哨兵（用来分辨「我们写过这块像素」和「显存里是
没初始化的垃圾」，否则管线载入的第一帧可能闪一下）。

以后再加需要跨帧状态的效果，注意两件事：每个 writer 只更新自己的通道，其余通道
从 `persist` 原样带走；中转用的 scratch 也别撞车（`a` 被 ink-stain 占了）。

## 改完怎么生效

kitty 重载配置时会重新编译 shader，不用重启。重载方式：改一下 `kitty.conf` 让它
自动重载，或者 `kill -SIGUSR1 $KITTY_PID`，或者按 `ctrl+shift+f5`。

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

`ink-stain-accumulate.slang`：

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

`ink-stain-composite.slang`：

| 参数 | 作用 |
| --- | --- |
| `INK_COLOR` | 墨色，默认纯白 |
| `INK_STRENGTH` | 最浓时往墨色混多少，决定亮度 |
| `INK_ALPHA_BOOST` | 积墨处不透明度往 1 靠多少 |
| `BG_TOLERANCE` | 背景判定容差（线性 RGB） |

这些都可以不改 shader，直接在 pipeline 里覆盖：

```
var float INK_STRENGTH 0.15
var float3 INK_COLOR float3(0.8, 0.85, 1.0)
```

### 三档预设

| | 极淡 | 现在这档 | 明显 |
| --- | --- | --- | --- |
| `INK_STRENGTH` | 0.10 | 0.20 | 0.35 |
| `NIB_STRENGTH` | 0.35 | 0.55 | 0.75 |
| `INK_ALPHA_BOOST` | 0.20 | 0.40 | 0.70 |
| `DRY_TIME` | 0.55 | 0.85 | 1.20 |

### 变干时间和动画窗口是一对

`DRY_TIME` 是「墨多快干」，pipeline 里的 `animation_stop` 是「kitty 多快停止为这个
效果画帧」。墨只能在有帧的时候继续变干，所以

```
animation_stop ≈ 4 × DRY_TIME
```

窗口短了，最后一帧会留下没干完的墨，它会被冻在屏幕上不再变化，直到下次触发才
突然消失——看起来就像闪一下。改了 `DRY_TIME` 记得同步改 `animation_stop`。

### 注意

订阅 `cursor-trail-move` 之后，kitty 内置的拖尾绘制会被完全抑制（shader 接管）。
想让它回来共存，把 pipeline 第一组的 `animation_start` 改成只留 `user-activity`。

---

## pane-fade —— 其它分屏颜色变淡

聚焦在哪个分屏，哪个就正常显示；其余分屏去饱和。只有一个分屏时整屏都在活动窗口
里，等于不生效。

### 怎么做的

每帧读 `d.active_window_geometry`（活动分屏在 UV 里的位置和大小），判断当前像素在
不在里面：在里面原样输出，在外面按 `INACTIVE_DESAT` 去饱和。完全无状态，一个组
搞定，不用 persist 也不用事件。

`animation_step 0` 的含义是「不申请周期性帧」，只在别的原因触发重绘时跟着走；
切换分屏本身就会重绘，所以效果立刻跟上。自带的 `dim-inactive-windows` 用的是
同一个套路。

### 可调参数

`pane-fade.slang`：

| 参数 | 作用 |
| --- | --- |
| `INACTIVE_DESAT` | 非活动分屏去掉多少饱和度。1.0 = 完全变灰，0.0 = 不变 |
| `EDGE_FEATHER_PX` | 边界羽化宽度，像素，避免分屏交界处出现硬边 |

想去饱和得更狠就设 1.0。想连亮度也压一点，在返回前再乘一个系数即可。

### 关于 tab bar 和 padding

活动窗口几何只覆盖分屏的内容区，所以 tab bar 和窗口 padding 会被算作「外面」。
它们都是背景色，去饱和对黑色无效，所以看不出来。真想让 tab bar 保持正常，可以用
`d.central_area` 先把这部分排除掉。

---

## 历史

`sleep-wake`（失焦渐变入睡 + 醒来过冲，带 persist 状态机）那一版在提交 `0c4af9c`，
`git show 0c4af9c` 可以翻回来看。现在换成了无状态的 `pane-fade`。
