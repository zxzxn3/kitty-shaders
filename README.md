# Kitty shaders

Custom Slang shaders for Kitty: cursor ink trails, focus cues, static surfaces,
animated backgrounds, and CRT distortion. Effects can be used individually or
combined through Kitty's `custom_shaders` setting.

## Requirements

Kitty 0.49.0 or newer with custom shader support. Used daily with Kitty 0.49.2;
all 13 pipelines and several effect combinations have passed compilation checks.
No background service or remote-control permission is required.

## Install

Clone into the `shaders` directory inside your Kitty configuration directory:

```sh
git clone https://github.com/zxzxn3/kitty-shaders.git ~/.config/kitty/shaders
```

If that directory already exists, install the files alongside your existing
shaders instead of replacing it. Keep each pipeline with the shader files it
references. For a non-default Kitty configuration directory, put the files in
its `shaders/` subdirectory.

Add a chain to your `kitty.conf`, then restart Kitty. A minimal cursor-trail
setup is:

```conf
cursor_trail 5
cursor_trail_start_threshold 1
custom_shaders ink-stroke-classic
```

Cursor-trail effects require a positive `cursor_trail` value. Subscribing to the
trail events replaces Kitty's built-in trail renderer. To disable these effects,
remove their names from `custom_shaders` and restart Kitty.

See [Kitty's custom shader documentation](https://sw.kovidgoyal.net/kitty/custom-shaders/)
for loading paths and the pipeline API.

## Effects

| Pipeline | Effect |
| --- | --- |
| `ink-stroke-classic` | Background-only cursor ink trail |
| `ink-stroke` | Short trail with rim and halo controls |
| `pearl` | Static graphite pearl surface |
| `contour` | Subtle contour-line surface |
| `edge-light` | Brief edge light when the window gains focus |
| `focus-pulse` | Edge pulse on focus |
| `layout-fade` | Desaturates inactive Kitty splits while the OS window is focused |
| `window-fade` | Desaturates the OS window when it loses focus |
| `star-hash` | Two-layer parallax starfield |
| `magic-box` | Cool-colored fractal filaments |
| `star-nest` | Deep-space fractal background |
| `cloud-bg` | Volumetric clouds with a two-pass sampling pipeline |
| `crt-warp` | Barrel distortion |

## Background previews

### Star hash

![Animated starfield](https://raw.githubusercontent.com/zxzxn3/kitty-shaders/main/assets/backgrounds/star-hash.gif)

### Clouds

![Animated clouds](https://raw.githubusercontent.com/zxzxn3/kitty-shaders/main/assets/backgrounds/cloud-bg.gif)

### Contour

![Contour-line surface](https://raw.githubusercontent.com/zxzxn3/kitty-shaders/main/assets/backgrounds/contour.png)

### Pearl

![Graphite pearl surface](https://raw.githubusercontent.com/zxzxn3/kitty-shaders/main/assets/backgrounds/pearl.png)

Animated previews show four seconds at the original speed. Captured in Kitty
with an opaque background and no terminal content.

## Combining effects

Keep one active `custom_shaders` chain in your configuration. For example:

```conf
# Cursor trail and focus cues.
custom_shaders ink-stroke-classic layout-fade window-fade focus-pulse

# Alternative: cursor trail with an animated starfield.
# custom_shaders ink-stroke star-hash layout-fade window-fade focus-pulse
```

For the trail examples, also keep the two `cursor_trail` settings from above.
Place the trail before the background, followed by fade effects and the focus
pulse. Put `crt-warp` last. When using `edge-light` with a surface effect, put
`edge-light` before the surface.

Use only one animated background: `star-hash`, `magic-box`, `star-nest`, or
`cloud-bg`. These effects identify the original background color; earlier
passes can change that color and prevent later passes from matching it.
Static surface effects are also easiest to tune individually.

## Tuning

Edit `var` values in the matching `.pipeline` file. Their inline comments
explain the controls; implementation details are documented in `.slang` files.
Restart Kitty after changing shader or pipeline sources so they are recompiled.

Useful controls include trail length and ink strength in `ink-stroke.pipeline`,
surface strength in the static surface pipelines, star density and drift in
`star-hash.pipeline`, and cloud sampling quality in `cloud-bg.pipeline`.

`animation_step 0` requests no periodic redraws: the shader still runs when
Kitty redraws for another reason. Time-based animation needs a positive step.
Setting a motion speed to zero alone does not disable its redraw timer.

## Limitations

- Background masks compare pixel colors rather than identifying text or images
  semantically. Image pixels close to the background color may also be affected.
- Static effects do not request periodic redraws, but cursor and other Kitty
  animations can still cause them to run. GPU cost has not been benchmarked.
- Cloud rendering can obscure text after a shader reload. Resizing the window
  or restarting Kitty is a workaround; the retained texture declarations reduce
  texture-set changes but are not a complete fix.

## Shader development

Group-level `var` settings keep shared shader parameters scoped to that group;
use them when combining `layout-fade` and `window-fade`. Do not read and write
the same named texture in one pass. When porting GLSL, account for Slang's
truncating `fmod` and row-major matrix representation.

## Attribution

Source headers preserve the authorship and available license notes for adapted
algorithms:

- `cloud-bg`: [Protean Clouds](https://www.shadertoy.com/view/3l23Rh) by nimitz.
- `star-nest`: [Star Nest](https://www.shadertoy.com/view/XlfGRj) by Pablo Roman Andrioli.
- `crt-warp`: Kitty's [CRT shader](https://github.com/kovidgoyal/kitty/blob/master/kitty/shaders/custom/crt.slang) by Kovid Goyal, with its upstream attribution.
- `magic-box`: adapted from [Star Nest Fractal MRI 2](https://www.shadertoy.com/view/Ml2yDw)
  by Good, whose page credits [Magic Fractal](https://www.shadertoy.com/view/4ljGDd)
  by dgreensp and Kali's Star Nest. Its fractal core is not claimed as original
  work. The adaptation follows Shadertoy's default CC BY-NC-SA 3.0 license.

This collection has no blanket license. See [third-party notices](THIRD-PARTY-NOTICES.md)
for the per-file licenses, retained notices, and descriptions of modifications.
