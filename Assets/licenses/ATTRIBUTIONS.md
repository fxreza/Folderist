# Third-Party Asset Attributions

This file summarizes the openly-licensed vector asset sets bundled in
`Assets/` for the Folderist app. All sets permit commercial redistribution;
attribution requirements are noted per set. Retain the corresponding
`*-LICENSE*.txt` file in this directory alongside any redistribution of
these assets.

Assets were fetched 2026-08-29 via `git clone --depth 1` of each project's
default branch, at the commit noted below.

---

## Twemoji (fork by jdecked)

- **Location in repo:** `Assets/emoji/` (4009 SVG files, flat)
- **Source:** https://github.com/jdecked/twemoji
- **Commit:** `b6b55fef1e8636b540a6d016a4729ca8cdf2e60b` (2026-06-01), package.json version `17.0.3`
- **License (graphics):** CC BY 4.0 (Creative Commons Attribution 4.0 International)
  — see `twemoji-LICENSE-GRAPHICS-CC-BY-4.0.txt`
- **License (code, not bundled):** MIT — see `twemoji-LICENSE-CODE.txt` (kept for
  completeness; only the SVG graphics were copied into this app, not the JS/build code)
- **Attribution requirement:** CC BY 4.0 requires attribution. Suggested credit:
  "Emoji graphics licensed under CC-BY 4.0 from Twemoji
  (https://github.com/jdecked/twemoji)". Include this credit in the app's
  About/Acknowledgments screen or documentation.
- **Notes:** `jdecked/twemoji` is the actively maintained community fork of the
  original `twitter/twemoji` project (Twitter's original repo is unmaintained
  since 2023). Only files under `assets/svg/` were copied; no PNG/composite
  assets were pulled in.

---

## Lucide

- **Location in repo:** `Assets/icons/lucide/` (1790 SVG files, flat)
- **Source:** https://github.com/lucide-icons/lucide
- **Commit:** `796dad298f8d78c5da204c3e62a5ed93c2bfcd1e` (2026-08-29), package.json version `17.0.3`
- **License:** ISC License — see `lucide-LICENSE.txt`
- **Attribution requirement:** ISC requires the copyright notice and
  permission notice to be retained (satisfied by keeping `lucide-LICENSE.txt`
  bundled with the app). No runtime/UI credit is legally required, but
  crediting Lucide in an Acknowledgments screen is good practice.
- **Notes:** Lucide is a community-maintained fork/continuation of Feather
  Icons. Its LICENSE file also carries a note that some icons are derived
  from the Feather project (also ISC/MIT-compatible) — see the full text in
  `lucide-LICENSE.txt` for details. Only files under `icons/` (the flat SVG
  set) were copied, not the React/Vue/etc. framework wrapper packages.

---

## Phosphor Icons

- **Location in repo:** `Assets/icons/phosphor/regular/` (1512 SVG files) and
  `Assets/icons/phosphor/fill/` (1512 SVG files)
- **Source:** https://github.com/phosphor-icons/core
- **Commit:** `2b75f3ad12b420c9504ef05df8d2564a28f8500e` (2026-01-06), package.json version `2.1.1`
- **License:** MIT License — see `phosphor-LICENSE.txt`
- **Attribution requirement:** MIT requires the copyright notice and
  permission notice to be retained (satisfied by keeping
  `phosphor-LICENSE.txt` bundled with the app). No runtime/UI credit legally
  required; crediting Phosphor in an Acknowledgments screen is good practice.
- **Notes:** Phosphor ships six weights (thin, light, regular, bold, fill,
  duotone). Only `regular` and `fill` were copied per the asset-gathering
  task scope; `thin`, `light`, `bold`, and `duotone` were left in the
  scratch clone and are not bundled. All weights carry the same MIT license
  and can be added later from the same source if needed.

---

## Material Design Icons (community package, marella/material-design-icons)

- **Location in repo:** `Assets/symbols/material/` (2122 SVG files, flat,
  "filled" style only)
- **Source:** https://github.com/marella/material-design-icons
- **Commit:** `feb03a5898eedb2f140fdc483d5887a492a1a663` (2025-02-12),
  `svg/package.json` version `0.14.15`
- **License:** Apache License 2.0 — see `material-design-icons-LICENSE.txt`
- **Attribution requirement:** Apache 2.0 requires retaining the copyright
  and license notice (satisfied by keeping `material-design-icons-LICENSE.txt`
  bundled). No runtime/UI credit legally required.
- **Notes:** This is a repackaging of Google's Material Symbols/Icons project
  as flat, framework-free SVG files. The upstream repo ships five styles
  (filled, outlined, round, sharp, two-tone); only `svg/filled/` was copied
  per task scope, since these are solid single-color silhouettes suitable
  for embossing. Google's original Material Design Icons project (and this
  repackaging of it) is Apache 2.0 licensed.

---

## Remix Icon

- **Location in repo:** `Assets/symbols/remix/` (1539 SVG files, flat,
  `*-fill.svg` variants only, flattened from the upstream category folders)
- **Source:** https://github.com/Remix-Design/RemixIcon
- **Commit:** `9fb7967c0a4c09910161192bde99efd3df09f5eb` (2026-04-28),
  package.json version `4.9.1`
- **License:** **Remix Icon License v1.0** (custom, source-available) — see
  `remix-LICENSE.txt`. **This is a deviation from the task's assumption that
  Remix Icon is Apache 2.0** — as of this version the project ships its own
  custom license, not Apache 2.0. It is still free to use commercially, but
  with restrictions beyond a standard permissive license:
  - Permits commercial/client use, modification, and bundling as a
    functional/decorative part of a larger product (Folderist's use case).
  - **Prohibits** reselling the icons as a standalone icon pack/library, or
    using them to build a competing icon library.
  - **Prohibits** using any Remix icon, modified or not, as a logo,
    trademark, or primary brand identity — relevant if Folderist ever
    considers a Remix icon for its own app icon or wordmark; only fine as
    in-app UI/content, not as the product's identity.
  - Since a *substantial portion* of the library is bundled here, §5 of the
    license requires keeping a copy of the license text (done, see
    `remix-LICENSE.txt`) alongside the assets. Attribution is optional/
    appreciated, not required, for this kind of bundling.
- **Notes:** Only the `*-fill.svg` (solid) variant of each icon was copied,
  per task scope; the outline "line" variants were left in the scratch
  clone. Flattening from the upstream `icons/<Category>/*.svg` folders
  produced no filename collisions.

---

## Bootstrap Icons

- **Location in repo:** `Assets/symbols/bootstrap/` (670 SVG files, flat,
  `*-fill.svg` variants only)
- **Source:** https://github.com/twbs/icons
- **Commit:** `6945b7006285d444cc17ff2e22c7691719229526` (2026-08-07),
  package.json version `1.13.1`
- **License:** MIT License — see `bootstrap-icons-LICENSE.txt`
- **Attribution requirement:** MIT requires the copyright and permission
  notice to be retained (satisfied by keeping `bootstrap-icons-LICENSE.txt`
  bundled). No runtime/UI credit legally required.
- **Notes:** Only the solid `*-fill.svg` variants were copied from the flat
  `icons/` directory (which also contains outline-only icons without a
  `-fill` suffix, e.g. many single-weight glyphs — those were left out per
  task scope, which asked for fill variants only).

---

## Heroicons

- **Location in repo:** `Assets/symbols/heroicons/` (324 SVG files, flat,
  24px "solid" set)
- **Source:** https://github.com/tailwindlabs/heroicons
- **Commit:** `616b7a4dbbf3d011760af8066262cd5c6b3868f3` (2026-05-12),
  package.json version `2.2.0`
- **License:** MIT License — see `heroicons-LICENSE.txt`
- **Attribution requirement:** MIT requires the copyright and permission
  notice to be retained (satisfied by keeping `heroicons-LICENSE.txt`
  bundled). No runtime/UI credit legally required.
- **Notes:** Copied from `optimized/24/solid/` (the minified/published
  build output — `fill="currentColor"`, clean single-path markup), not
  `src/24/solid/` (the unminified authoring source with `fill="none"`).
  Both directories contain the same 324 icons. The 16px and 20px sizes and
  the "outline"/"mini" styles were left out per task scope.

---

## Hero Patterns

- **Location in repo:** `Assets/textures/heropatterns/` (87 SVG files, flat,
  seamless monochrome background patterns)
- **Source:** https://github.com/sschoger/hero-patterns (official repo for
  https://heropatterns.com, by Steve Schoger) — the task's suggested mirror
  `danielmpetrov/hero-patterns` does not exist (404); this is the real
  upstream instead.
- **Commit:** `6a2ed74a6910a8b1095d15dd31f7f3f0188517ad` (2021-11-11, last
  update to this repo)
- **License:** CC BY 4.0 (Creative Commons Attribution 4.0 International) —
  declared in the site/repo's own footer (links to
  `https://creativecommons.org/licenses/by/4.0/`); see
  `heropatterns-LICENSE.txt` for the assembled license text and summary
  (the source repo does not ship its own LICENSE file).
- **Attribution requirement:** CC BY 4.0 requires attribution. Suggested
  credit: "Background patterns by Hero Patterns (https://heropatterns.com),
  licensed under CC BY 4.0." Include this credit in the app's
  About/Acknowledgments screen or documentation.
- **Notes:** The repo does not ship the ~90 patterns as loose top-level SVG
  files — most are packaged as per-pattern `.zip` files under `svg/`
  (containing one SVG each), and the full pattern data (name + full SVG
  markup) is also embedded directly in `js/app.js` as a JS array backing
  the site's live color-picker demo. The 87 patterns bundled here were
  extracted programmatically from that `app.js` array (regex-parsed
  name/SVG pairs, one file per pattern, filenames slugified from the
  pattern's display name) rather than unzipped one by one — this is more
  reliable than unzipping ~90 archives and yields the same source SVG
  content. All patterns are single-color (`fill="#000"` or similar) and
  tile seamlessly. No dedicated LICENSE file exists upstream; the CC BY 4.0
  declaration comes from the repo's own `index.html` footer and the
  heropatterns.com site.

---

## Summary Table

| Set                  | Files | License                | Bundled path                              |
|-----------------------|-------|-------------------------|--------------------------------------------|
| Twemoji               | 4009  | CC BY 4.0               | `Assets/emoji/`                            |
| Lucide                | 1790  | ISC                     | `Assets/icons/lucide/`                     |
| Phosphor              | 3024  | MIT                     | `Assets/icons/phosphor/{regular,fill}/`    |
| Material Design Icons | 2122  | Apache 2.0              | `Assets/symbols/material/`                 |
| Remix Icon            | 1539  | Remix Icon License v1.0 (custom, not OSI-approved, see notes above) | `Assets/symbols/remix/` |
| Bootstrap Icons       | 670   | MIT                     | `Assets/symbols/bootstrap/`                |
| Heroicons             | 324   | MIT                     | `Assets/symbols/heroicons/`                |
| Hero Patterns         | 87    | CC BY 4.0               | `Assets/textures/heropatterns/`            |

ISC, MIT, Apache 2.0, and CC BY 4.0 all permit use in a commercial,
closed-source macOS app, provided the notices above are retained/displayed
as noted. Remix Icon's custom license also permits this app's use case
(icons as functional/decorative UI elements, not resold as a standalone
icon pack) but carries extra restrictions — see the Remix Icon section
above before using any Remix icon as a logo, brand mark, or app icon, or
before building any feature that packages/sells the icon set on its own.
