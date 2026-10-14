# Third-party notices

This collection has no blanket license. The licenses below apply to the
specified third-party material and adaptations, not to unrelated files.
Original work outside these grants is not offered under an additional reuse
license. Making the repository public does not change that distinction.

## Magic Box

`magic-box.slang` adapts **Star Nest Fractal MRI 2** by **Good**:
https://www.shadertoy.com/view/Ml2yDw

The page credits **Magic Fractal** by **dgreensp**:
https://www.shadertoy.com/view/4ljGDd
and **Star Nest** by **Pablo Roman Andrioli (Kali)**.

The supplied saved page contains no explicit shader license. Under
[Shadertoy's terms](https://www.shadertoy.com/terms), shaders without a specified
license use **CC BY-NC-SA 3.0**. This adaptation is distributed under the same
license; see [the license text](LICENSES/CC-BY-NC-SA-3.0.txt).

Changes: GLSL-to-Slang port, background masking, reduced iterations, cool color
palette, flow and hue controls, and preservation of input alpha. The folding
recurrence and rotation matrix retain the source algorithm.

## Protean Clouds

`cloud-bg.slang` adapts **Protean Clouds** by **nimitz (@stormoid)**:
https://www.shadertoy.com/view/3l23Rh

The original source header declares **CC BY-NC-SA 3.0**. This adaptation is
released under that license; see [the license text](LICENSES/CC-BY-NC-SA-3.0.txt).

Changes: GLSL-to-Slang port, reduced marching and deformation work, sampled rows
with a separate interpolation pass, background masking, and pipeline controls.
`cloud-bg-apply.slang` and `cloud-bg.pipeline` are also distributed under
CC BY-NC-SA 3.0 as the supporting components of this adaptation.

## Star Nest

`star-nest.slang` includes the algorithm from **Star Nest** by
**Pablo Roman Andrioli (Kali)**:
https://www.shadertoy.com/view/XlfGRj

The original source explicitly declares the **MIT license**. Its copyright
and permission notice is retained in [Star-Nest-MIT.txt](LICENSES/Star-Nest-MIT.txt).
This notice covers the upstream material; it does not grant a blanket license
to all original work in this collection.

Changes: GLSL-to-Slang port, fewer iterations, background masking, black-level
and brightness controls, slow drift, and numerical guards.

## CRT warp

`crt-warp.slang` is adapted from Kitty's CRT shader by **Kovid Goyal**:
https://github.com/kovidgoyal/kitty/blob/master/kitty/shaders/custom/crt.slang

Copyright (C) 2026 Kovid Goyal. Kitty distributes that source under **GPLv3**;
this modified shader is distributed under GPLv3, with the full license retained
in [GPL-3.0.txt](LICENSES/GPL-3.0.txt).

Kitty's source additionally credits https://www.shadertoy.com/view/WsVSzV
as its original shader, under CC BY-NC-SA 3.0. That upstream attribution is
retained rather than treating the effect as original work.

Changes: retained curvature with separate axis controls, removed scanlines and
tint, preserved alpha, and used event-driven rendering. Modified in October 2026.
