# ink-stain —— kitty 墨痕

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

## 注意

订阅 `cursor-trail-move` 之后，kitty 内置的拖尾绘制会被完全抑制（shader 接管）。
想让它回来共存，把 pipeline 第一组的 `animation_start` 改成只留 `user-activity`。
