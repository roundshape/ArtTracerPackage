**English** | [日本語](README.md)

# ArtTracer

A **template data-merge plugin** for Adobe Illustrator. Save Illustrator artwork as `.artx` (template XML), and merge CSV data to generate many variations at once.

`.artx` is a human-readable text XML format designed so that AI (LLMs) can generate it directly. This enables a workflow of **"ask ChatGPT / Claude for a design → merge it into Illustrator with ArtTracer."**

> 📖 New here? Check out the **[User Guide (MANUAL.en.md)](MANUAL.en.md)**.

---

## Features

### 1. Save and reuse templates

Save artwork created in Illustrator as `.artx`. Recall the same template later and draw it anywhere with a single click.

### 2. Batch variation generation via CSV merge

Embed **placeholders** such as `{shop_name}` or `{phone}` in your text and save the `.artx`. Then just pass a CSV to expand multiple variations with each row's data substituted in one shot.

**Example uses**: per-store shop cards / per-product price tags / individual business cards / per-course flyers / seasonal promotion variants, and more.

### 3. Built-in AI chat for direct design generation ★NEW

Without going back and forth to external chat services, you can **ask the AI directly inside the Illustrator panel**. When you make a request, the AI generates `.artx` and draws it straight into Illustrator as artwork.

- Choose your provider from **Claude / OpenAI**
- Responses stream in (you watch the generation in real time)
- Have the AI read an existing template (`read_artx`) and create a derivative with changed colors, fonts, or layout on the spot
- Local commands: `/clear` (clear history), `/model` (switch model), `/retry` (regenerate), `/help`

This is the shortest route when you want to "finish without leaving Illustrator." You can always retouch by hand afterward, so it's fine even if the AI isn't perfect.

> For external agent integration (Claude Code CLI, etc.), you can also use **JS inbox watching**, which automatically runs `.js` files placed in a designated folder (see `ai_docs/ArtTracer_quickjs_reference.md`).

### 4. Generate .artx with an external LLM (ChatGPT / Claude, etc.) ★

The `.artx` specification (`ai_docs/artx-format.md`) is designed so that **an LLM can read it and output `.artx` directly**. This is the workflow for generating with your favorite external LLM instead of the built-in chat (section 3).

#### Typical workflow

1. Paste (or attach) `ai_docs/artx-format.md` into a chat with an LLM such as ChatGPT / Claude / Gemini
2. Make a request like "**Create an A6 hair-salon shop card. Include the placeholders `{name}` `{phone}` `{address}`.**"
3. The LLM outputs `mycard.artx` → save it to any folder
4. In Illustrator, open the panel from **Window → ArtTracer** and select `mycard.artx`
5. Load a CSV (store list) from the panel
6. Click with the draw tool, and cards with each row's data merged in are drawn one after another

---

## Supported elements

### Art elements
- Paths (open / closed), compound paths
- Groups
- Text (point, area, on-path)
  - Character attributes: font, size, color, tracking, horizontal / vertical scale, baseline shift, kerning, leading
  - **Overflow auto-fit** for area text
- Placed images (PNG / JPEG)

### Fills & strokes
- Solid color (RGB / CMYK / Gray)
- Linear / radial gradients
- Stroke width, dash patterns

### Other
- Clipping masks (path, compound path)
- **Repeat mode** for the draw tool (exit with Esc / Option)
- In-panel CSV pager (cycle through rows with `<` `>`)

---

## Finder integration

Copy the bundled **`ArtTracerHelper.app`** to `/Applications`, and `.artx` files are handled in Finder as follows:

- Custom icon display
- Thumbnail images (the PNG preview embedded when the `.artx` is saved)
- Quick Look preview (full-size preview with the space key)

---

## Installation

**Supported platform**: macOS only (Adobe Illustrator 2022 or later). A Windows version is not currently provided.

See **`Install Guide.md`** inside the dmg.

In short:

1. Drag `ArtTracerHelper.app` to `/Applications`
2. Copy `ArtTracer.aip` into Illustrator's `Plug-ins.localized/` folder
3. Restart Illustrator

---

## File format specification

The complete `.artx` specification is in **[`ai_docs/artx-format.md`](ai_docs/artx-format.md)**. It can also be handed to an AI.

---

## Versions

Each artifact has its own independent version. See [`CHANGELOG.md`](CHANGELOG.md) for details.

## Contact

For bug reports, feature requests, and other questions, please contact:

**arttracer.roundshape@gmail.com**

## License

The software included in this package (ArtTracer.aip / ArtTracerHelper.app) is freeware.

- **Free to use.** There is no charge whatsoever — for individuals or businesses, including use in commercial production work.
- Copyright and all other rights are retained by Roundshape.
- Please do not redistribute (repost or re-upload to other sites). Distribution is done only through this repository's Releases.
- Please do not decompile, modify, or create derivative redistributions.
- **No warranty.** The author assumes no responsibility for any damage (document corruption, data loss, etc.) arising from the use of this software. Please back up important data before use.
- These terms may change in future versions (changes apply from the new version onward).
