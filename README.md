# Kitty shaders

当前启用组合见 `../kitty.conf` 的 `custom_shaders`。调参见各 `.pipeline` / `.slang`；
修改 shader 后递增 `kitty.conf` 中的 `shader-rev` 以触发重载，Kitty 不直接监听 shader 文件。

## 效果与组合

| 效果 | 用途 |
| --- | --- |
| ink-stroke-classic | 经典光标笔触 |
| ink-stroke | 短余像笔触；TRAIL_LENGTH、RIM_STRENGTH、HALO_STRENGTH、INK_STRENGTH 控制长度、高光、软晕和主体 |
| pearl | 静态石墨珠光背景；PEARL_STRENGTH 控制强度 |
| vellum / contour | 暖灰纸面 / 细等高线材质；共用 surface.slang，STRENGTH 控制强度 |
| edge-light | 聚焦后 240ms 边缘亮光，结束后停止主动重绘 |
| focus-pulse | 聚焦时边缘脉动 |
| layout-fade / window-fade | 分屏 / 窗口失焦时去饱和，共用 fade.slang |
| star-hash / magic-box / star-nest / cloud-bg | 动态背景，四选一 |
| crt-warp | 整屏桶形畸变 |

组合顺序：笔触 → 背景 → layout-fade → window-fade → 聚焦效果 → crt-warp。
背景只开一个，位移效果最后执行；试用 edge-light 时放在材质前面。
移除背景项即恢复原背景，笔触可在 ink-stroke 与 ink-stroke-classic 之间替换。

背景与笔触按背景色比色，保留 alpha；图片中近背景色的区域也可能受影响，
并非按字符语义识别的遮罩。静态材质没有持续计时器，但光标动画仍可能触发重绘；
实际 GPU 开销未测。

## 修改约束

- 依赖 `d.timestamp` 的动画需要非零 `animation_step`；0 只随其他重绘运行。
- Slang 的 `fmod` 是截断余数；GLSL 的 floor 语义应写作 `x - y*floor(x/y)`。
  矩阵字面量为行主序，移植 GLSL 时核对转置和 `mul` 顺序。
- 同一趟不能读写同一张命名纹理，否则 Kitty 会回退到 backbuffer。
- pipeline 顶层 `var` 全局按名称替换；需隔离的参数放进 `startgroup` / `endgroup`。
- cloud-bg 热重载若遮住文字，调整窗口尺寸或换屏；`SIGUSR1` 无效。
  各背景保留 `textures a` 以减少该问题。

## 仓库与安装

本仓库仅管理 shader；`kitty.conf` 由 cfg 管理。安装位置为
`~/.config/kitty/shaders/`，也可通过 cfg 的 submodule 部署。
仓库目前私有，克隆需要 GitHub 认证。

```sh
git clone https://github.com/zxzxn3/kitty-shaders.git ~/.config/kitty/shaders
```

修改后先在此库提交并推送，再提交 cfg 中的子模块版本引用。
`git submodule update` 通常检出 detached HEAD；编辑并创建新提交前
请切回 `main` 分支。
