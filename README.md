# kitty 自定义 shader

代码是唯一事实来源：每个效果的旋钮都在它自己的 `.pipeline` / `.slang` 注释里。
这份文档只讲「有哪些效果、怎么开、怎么改生效、踩过哪些坑」。

## 组成

| 效果 | 文件 | 做什么 | 实测成本 |
|---|---|---|---|
| ink-stroke | `ink-stroke.*` | 光标移动时留一道白色笔触 | ≈0，事件驱动 |
| focus-pulse | `focus-pulse.*` | 获得焦点时边缘呼吸一次 | ≈0，只在 600ms 动画期要帧 |
| layout-fade | `fade.slang` + `layout-fade.pipeline` | 非活动分屏去饱和 | ≈0，事件驱动 |
| window-fade | `fade.slang` + `window-fade.pipeline` | 失焦的整个 OS 窗口去饱和 | ≈0，事件驱动 |
| star-hash | `star-hash.*` | 哈希星场，两层视差 | ~5 ns/px |
| magic-box | `magic-box.*` | 魔盒分形，冷色深海细丝 | ~6 ns/px |
| star-nest | `star-nest.*` | 分形星野 | ~50 ns/px |
| cloud-bg | `cloud-bg.*` + `cloud-bg-apply.*` | 体积云，两趟 | ~300 ns/px |

ns/px 是 llvmpipe 软件光栅、640×360 整屏当背景时的实测值，只用来比数量级：
三个小效果和空管线（1.7 ns/px）没有区别，四个背景之间差 10~60 倍。

## 顺序与互斥

四个背景（`star-hash` / `star-nest` / `cloud-bg` / `magic-box`，加上 `bg-drift` 分支上的
第五个）**同时只能开一个**：它们都靠「和 `d.background` 比色」认背景，先跑的那个会把背景
染色，后面的就认不出来了。`ink-stroke` 和两个 fade 用同一个判据，所以顺序必须是

    ink-stroke → 背景 → layout-fade → window-fade →（focus-pulse）

## 启用

改 `kitty.conf` 的 `custom_shaders` 那一行。文件里已经并列写好四种组合，留一行生效：

    custom_shaders ink-stroke star-hash layout-fade window-fade focus-pulse

## 改完怎么生效

kitty 的 `auto_reload_config` 只监听 `kitty.conf`，**不监听 `shaders/`**。所以改完 shader
要把 `kitty.conf` 里的 `shader-rev: N` 顺手 +1。改窗口尺寸、把它挪到别的屏幕也会触发重建，
调试时更快。

## 踩过的坑

* `animation_step 0` = 不申请周期帧，只在别的原因重绘时顺带跑一遍。**任何依赖
  `d.timestamp` 的效果都不能用 0**：那样「动没动」会被重绘频率绑架 —— TUI 里看着正常，
  空闲/失焦/滚屏时冻住，滚一格又跳一下。三个事件驱动的效果用 0 是对的。
* Slang 不是 GLSL：`mod` 只有截断语义的 `fmod`，GLSL 的 floor 语义要自己写
  `x - y*floor(x/y)`；矩阵字面量是行主序（GLSL 是列主序，照抄等于转置），
  GLSL 的 `p*m` 要写成 `mul(M, v)`。
* **同一趟里不能同时读写同一张命名纹理**，kitty 会静默换成 backbuffer。
* pipeline 级的 `var` 是全局按名字替换的，**必须写在 `startgroup`…`endgroup` 里**，
  否则同名常量互相覆盖（两个 fade 共用 `fade.slang` 就靠这个）。
* cloud-bg 热重载后可能整屏被云糊住、字看不见：`SIGUSR1` 重载无效，改一下窗口尺寸或
  挪到另一个屏幕就好。四个背景都写了 `textures a` 来规避，未彻底根治。
