# Remote themes

Themes change how the remote looks: colours, button shape and size, the
D-pad, and an optional background image. A theme is a single JSON file you
can write by hand, share, and import into the app.

- **Apply or import:** Settings → **Remote theme**. Import from a file, or
  copy the theme text and use *Paste from clipboard*.
- **Start from an existing theme:** on any theme's ⋮ menu, choose *Save as
  file* or *Copy as text*, then edit it.
- **Examples:** the built-in themes in [`assets/themes/`](../assets/themes/)
  and [`docs/example-themes/`](example-themes/).
- **Editor support:** [`theme.schema.json`](theme.schema.json) is a JSON
  Schema. In VS Code, add
  `"$schema": "https://raw.githubusercontent.com/yourmomsbasement/Tv-Remote_Free/master/docs/theme.schema.json"`
  as the first key to get autocomplete and validation. The app ignores
  `$schema`.

## Smallest possible theme

```json
{
  "format": "tv-remote-free-theme",
  "version": 1,
  "name": "Forest",
  "colors": { "seed": "#2E7D32" }
}
```

Every colour you leave out is derived from `seed`, so one colour is enough
for a coherent look in both light and dark mode.

## Full reference

| Field | Required | Meaning |
|---|---|---|
| `format` | yes | Always `"tv-remote-free-theme"`. |
| `version` | yes | Format version. Currently `1`. Files with a newer version are refused rather than misread. |
| `name` | yes | Shown in the theme list. Up to 40 characters. |
| `id` | no | Lower-case letters, digits, `.`, `_`, `-`, up to 64 characters. Importing a theme with an existing id **replaces** it, which is how you update a theme you shared. Defaults to `user.<name>`. Ids starting with `builtin.` are reserved. |
| `author` | no | Up to 60 characters. |
| `description` | no | Up to 200 characters. |
| `modes` | no | `["light"]`, `["dark"]` or both (the default). A theme with only one mode **overrides** the app's light/dark setting. |
| `colors` | no | A palette used for both modes. |
| `light`, `dark` | no | Palettes for one mode. Their keys override `colors`. |
| `shape.button` | no | `"circle"` (default), `"rounded"` or `"square"`. |
| `shape.cornerRadius` | no | 0–40, default 16. Used by rounded buttons and a rounded D-pad. |
| `shape.dpad` | no | `"circle"` (default) or `"rounded"`. |
| `buttonScale` | no | 0.8–1.3, default 1. Makes the remote's buttons smaller or larger. |
| `background.image` | no | `data:image/png;base64,...` (PNG, JPEG or WebP), at most 2 MB once decoded. Shown behind the remote screen. |
| `background.fit` | no | `"cover"` (default), `"contain"` or `"fill"`. |
| `background.opacity` | no | 0–1, default 1. Lower values fade the image into `background`. |

Numbers outside their range are clamped. Unknown fields are ignored, so
newer themes stay importable where possible.

### Palette colours

Colours are `"#RGB"`, `"#RRGGBB"` or `"#AARRGGBB"` (alpha first).

| Key | Used for |
|---|---|
| `seed` | Generates every colour you don't set, plus the rest of the app (switches, sliders, dialogs). |
| `background` | Screen behind the remote. |
| `surface` | App bar, cards and sheets. |
| `button` / `buttonIcon` | Normal remote buttons and their icons. |
| `accentButton` / `accentButtonIcon` | Highlighted buttons such as Power. |
| `dpadRing` | The D-pad's base. |
| `ok` / `okText` | The centre OK button. |

## Accessibility

When you import a theme, the app warns about icon or text colours with a
contrast below 3:1 against their button. You can still use the theme, but
consider people with low vision before sharing it. The built-in **High
Contrast** theme is a good reference.

## Safety

Theme files contain only data. The app validates every field, caps file
and image sizes, checks that embedded images really are PNG, JPEG or WebP,
and never runs code or loads anything from the internet because of a theme.
