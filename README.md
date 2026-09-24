# kitty 自定义 shader

| pipeline | 做什么 | 跨帧状态 |
| --- | --- | --- |
| `ink-stain` | 光标走过的地方洇开白色水痕，慢慢干掉 | `persist.r` = 墨量 |
| `inactive-fade` | 失去焦点的窗口、没聚焦的分屏，颜色往黑白去 | 无，完全无状态 |

只有 `ink-stain` 用 `persist`，而且只用 `.r`（墨量）和 `.a`（1.0 哨兵，用来分辨
「我们写过这块像素」和「显存里是没初始化的垃圾」）。既然只有一个使用者，就不需要
什么通道分配协议。

## 启用

`~/.config/kitty/kitty.conf`：

```conf
custom_shaders ink-stain inactive-fade
# 墨的坐标只能从拖尾几何里拿。默认阈值 2 会跳过单格移动，打字就不出墨。
cursor_trail_start_threshold 1
```

多条 pipeline 按声明顺序串联执行，总共 5 个组。

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

`inactive-fade.slang`：

| 参数 | 作用 |
| --- | --- |
| `DIM` | 亮度系数，1.0 = 完全不动亮度（当前）；想额外压暗就往下调 |
| `DESAT` | 去多少饱和，0.0 = 不动，1.0 = 彻底黑白。含义是保留 (1 - DESAT) 的色度 |
| `EDGE_FEATHER_PX` | 分屏边界羽化多少像素（只对分屏那组有意义） |

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

`ink-stain-composite.slang`：`INK_COLOR`（墨色，默认纯白）、`INK_STRENGTH`
（最浓时往墨色混多少）、`INK_ALPHA_BOOST`（积墨处不透明度往 1 靠多少）、
`BG_TOLERANCE`（背景判定容差）。

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

## 历史

`inactive-fade` 前面试过三版，都留在 git 里，需要时可以翻：

| 提交 | 是什么 | 为什么放弃 |
| --- | --- | --- |
| `0c4af9c` | `sleep-wake`：失焦渐入睡 + 醒来过冲 | 为了一个简单的诉求引入了两段动画和状态机 |
| `fed46a9` | `pane-fade`：只按分屏判定，纯去饱和 | 白字去饱和等于没变；且完全没覆盖窗口维度 |
| `a341611` | `inactive-fade`：两个维度 + 5 秒渐变 | 渐变需要计时，计时需要跨帧状态，复杂度上来了 |

现在是 `a341611` 的简化版：保留两个维度，去掉渐变，于是也去掉了 persist、
commit 组、时长参数和通道协议。
