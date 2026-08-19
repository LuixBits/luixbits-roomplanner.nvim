# Documentation media

The GIFs in this directory are rendered from real RoomPlan sessions. The
showcase image is the final thumbnail for the RoomPlan walkthrough. Source
recordings and working files stay in the private LuixBits video archive and
are not part of this repository.

| Asset | Source capture | Cut | Output SHA-256 |
| --- | --- | --- | --- |
| `roomplan-overview.gif` | `roomplan/test-tour.mkv` | `0.0s` to `6.9s` | `5d3d4c459344f7e300927ff1d76de86ff65a7781a3538c90bfb27cb8a9378420` |
| `roomplan-add-align.gif` | `roomplan/02-01-add-and-align.mkv` | `1.1s` to `13.0s` | `db9640d2840dcb4cfee6b997f7cfe8d4a61fc00a46fcbfad7b00f2973297c48e` |
| `roomplan-sun-study.gif` | `roomplan/chapter01/02-sun-study.mkv` | `4.5s` to `14.5s` | `2de409a374172be4defa5e0ea958623e9ff2afa94b14ce410e799e60e30f8735` |
| [`roomplan-showcase.png`](roomplan-showcase.png) | `roomplan-nvim-thumbnail-v2.png` | Final thumbnail | `825bfd079bd2744f817f2488dd209e66fc49229d1f8cd4c4c23ab3da728504e5` |

Source capture checksums:

- `roomplan/test-tour.mkv`: `47204c20cba0d06783450882c3d99a51b2cd6dfe56808708b4510b9761087e6c`
- `roomplan/02-01-add-and-align.mkv`: `187288173d9ec25480b40e16185a358c0e6f1754cea20b292f5144946d93d3cc`
- `roomplan/chapter01/02-sun-study.mkv`: `7071dd65d2cce66a6771913da539842e20eca49ba472501238aae9055c77a57a`

## Rendering

The current files are 1600 pixels wide, 12 frames per second, and use a
128-colour palette without dithering. They contain no audio.

```sh
ffmpeg -ss "$start" -t "$duration" -i "$source" \
  -filter_complex \
  "[0:v]fps=12,scale=1600:-2:flags=lanczos,split[v1][v2];[v1]palettegen=max_colors=128:stats_mode=diff[p];[v2][p]paletteuse=dither=none:diff_mode=rectangle" \
  -an -loop 0 "$output"
```

Review every rebuilt file for private paths, coordinates, notifications, and
recording artefacts before committing it.
