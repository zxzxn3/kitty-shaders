# kitty 自定义 shader

两个效果：

| pipeline | 做什么 | 跨帧状态 |
| --- | --- | --- |
| `ink-stain` | 光标走过的地方洇开白色水痕，慢慢干掉 | `persist.r` = 墨量 |
| `inactive-fade` | 失去焦点的窗口、没聚焦的分屏，压暗并褪成没有颜色 | `persist.g` = 褪色程度 |

`persist.a` 是 1.0 哨兵，用来分辨「我们写过这块像素」和「显存里是没初始化的垃圾」，
否则管线载入的第一帧可能闪一下。`persist.b` 空着留给下一个效果。

**每个 writer 只能更新自己的通道**，其余通道要从 `persist` 原样带走——两条 pipeline
写的是同一块纹理，谁也不能整块覆盖。中转用的 scratch：`ink-stain` 用 `a`，
`inactive-fade` 用 `b`。

## 启用

`~/.config/kitty/kitty.conf`：

```conf
custom_shaders ink-stain inactive-fade
# 墨的坐标只能从拖尾几何里拿。默认阈值 2 会跳过单格移动，打字就不出墨。
cursor_trail_start_threshold 1
```

多条 pipeline 按声明顺序串联执行。

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

## inactive-fade —— 不活跃的窗口和分屏会褪色

两个维度，共用同一个「褪色程度」（`persist.g`）：

* **窗口维度**：这个 OS 窗口失去焦点 → 整个窗口褪色
* **分屏维度**：当前窗口里没聚焦的分屏 → 那些分屏褪色（活动分屏始终正常）

两者都遵循同一套观感：**马上压暗**（亮度降到 0.68），然后在 5 秒里越来越淡，
最后完全没有颜色（去饱和 1.0、亮度 0.50）。回到焦点立刻恢复正常。

为什么必须压暗：白色没有色相，把白字去饱和算出来还是白字。只有当屏幕上真有彩色
内容（`ls` 的颜色、语法高亮、彩色提示符）时去饱和才看得出来，所以「马上能看出来」
靠的是压暗。

### 五个组在做什么

| 组 | 触发 | 做什么 |
| --- | --- | --- |
| `inactive-fade-window` | 失焦 | 整窗褪色程度 = 动画进度，5 秒推到 1 |
| `inactive-fade-commit` | attach | 并回 `persist.g` |
| `inactive-fade-panes` | 分屏获得焦点、窗口重新获得焦点 | 活动分屏内清零，其余按真实时间继续累积 |
| `inactive-fade-commit` | attach | 并回 `persist.g` |
| `inactive-fade-apply` | 每帧（`animation_step 0`） | 按褪色程度压暗 + 去饱和 |

窗口维度和分屏维度是互斥的：各自把对方的触发条件当作自己的停止条件
（失焦时停止分屏那组，重新聚焦或超时后停止窗口那组），所以它们不会同时写同一块
scratch，也不会在同一个像素上叠加两次。

最后的 `apply` 只有一个，永远只上色一次，这是"两个维度同时存在也不会加深一倍"
的原因。

### 为什么窗口那组用 animation_progress，分屏那组用 dt 累加

失焦的窗口可能很少被重绘，如果按帧累加，褪色会卡在半路——所以窗口那组直接
用动画进度反推真实经过的时间（`animation_progress` 来自 kitty 的时钟）。

分屏那组相反：它是逐个像素累加的，所以 3 个以上分屏来回切时，早就淡下去的
分屏不会因为「重新开始计时」被拉回来重来一遍。活动窗口里帧一直都有，累加不会卡。

边界用 `fwidth` 换算成像素、在 1.5 像素内平滑过渡，过渡带上的像素最终只褪到
对应的比例，所以分屏交界处没有生硬的直线。

### 可调参数

`inactive-fade-apply.slang`：

| 参数 | 作用 |
| --- | --- |
| `DESAT_START` / `DESAT_END` | 刚开始褪色时、褪到底时分别去掉多少饱和 |
| `DIM_START` / `DIM_END` | 开始和最终保留多少亮度 |

`inactive-fade-panes.slang`：`FADE_TIME`（几秒褪到底）、`EDGE_FEATHER_PX`（边界羽化）、
`MAX_STEP`（单帧最多算多少秒，防止空闲后的第一帧一步到位）。

`FADE_TIME` 要和 pipeline 里的 `animation_stop 5000` 保持一致。

---

## 历史

* `sleep-wake`（失焦渐变入睡 + 醒来过冲 + persist 状态机）在提交 `0c4af9c`
* `pane-fade`（只有分屏维度）在提交 `fed46a9`

两版都可以 `git show <哈希>` 翻回来看。
