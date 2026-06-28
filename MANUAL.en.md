**English** | [日本語](MANUAL.md)

# ArtTracer User Guide

ArtTracer is a plugin that saves Illustrator artwork as **templates (`.artx`)** and lets you generate variations all at once via **CSV data merge** or **AI**. This guide shows the quickest way to get value out of it.

> For installation, see [InstallGuide.md](InstallGuide.md).

---

## 1. What can it do?

- Turn your designs into **reusable templates** you can place with a single click
- Generate business cards, shop cards, price tags, and more **in bulk from a CSV** (one per person, per store, etc.)
- Just ask the **built-in AI chat** "make me a ___" and it generates the design
- Import `.artx` created with your favorite **ChatGPT / Claude**

From "one by one, by hand" to "all at once, from data." That's ArtTracer.

---

## 2. Get started (save a template → draw it)

1. Open the panel from **Window → ArtTracer**
2. Create some artwork in Illustrator and **select** it
3. **Save** it as `.artx` from the panel
   - In the save dialog you can look at the thumbnail and add **keywords** (season, event, etc.). This makes the template easier for the AI to find later.
4. Select the saved template and **click on the artboard with the draw tool** — the template is drawn at that spot
   - **Repeat mode**: keep clicking to place it repeatedly. Exit with **Esc / Option**.

---

## 3. Mass-produce with CSV ★

The trick is to write **placeholders** (wrapped in `{ }`, like `{name}` `{phone}`) into the template's text.

1. Put `{shop_name}` `{phone}` etc. in your text and save the `.artx`
2. **Load a CSV** from the panel (the CSV column names map to the placeholder names)
3. Click with the draw tool, and items with **each CSV row's data merged in** are drawn one after another
4. Use the panel's **`<` `>`** to move between rows

→ Per-store cards, per-product price tags, individual business cards — all produced at once from a single data file.

---

## 4. Let the AI make it (built-in chat) ★

Without going back and forth to external services, you can **ask the AI directly inside Illustrator**.

1. (First time) In **Settings**, choose an AI provider (**Claude / OpenAI**) and enter an API key
2. Ask the chat something like "**Make an A6 hair-salon card**"
3. The AI generates `.artx` and draws it straight into Illustrator (the generation streams in)
4. Using an existing template as a base, you can also ask "**change the color**" or "**make the heading bigger**"

Handy commands: `/clear` (clear history), `/model` (switch model), `/retry` (regenerate), `/help`

You can retouch by hand as much as you like afterward, so it's fine even if the AI isn't perfect.

---

## 5. Create .artx with an external LLM (ChatGPT / Claude)

You can also create `.artx` with your favorite LLM instead of the built-in chat.

1. Paste / attach **[`ai_docs/artx-format.md`](ai_docs/artx-format.md)** into a chat with the LLM
2. Ask something like "Make an A6 shop card with the placeholders `{name}` `{phone}`"
3. Save the output `.artx` → select it in the panel and draw it (CSV merge works too)

Because `.artx` is designed to be read and written by LLMs, **ArtTracer pairs well with AI** for design.

---

## 6. Finder integration (bonus)

Put the bundled **`ArtTracerHelper.app`** in `/Applications`, and `.artx` files in Finder will:

- Show a custom icon
- Show a **thumbnail** so you can see the contents at a glance
- Offer **Quick Look** preview with the space key

This helps a lot when managing many `.artx` files.

---

## 7. Troubleshooting (FAQ)

- **The panel doesn't appear** → Check that "ArtTracer" is in the Window menu. If not, check the installation and restart Illustrator ([InstallGuide.md](InstallGuide.md)).
- **CSV data isn't merged in** → Check that the placeholder names in the text (`{name}`, etc.) match the CSV column names.
- **The AI chat doesn't respond** → Check the API key and provider selection in Settings.
- **`.artx` thumbnails don't appear** → Put `ArtTracerHelper.app` in `/Applications`; logging out / restarting once sometimes makes it take effect.

---

For bug reports and feature requests, please contact **arttracer.roundshape@gmail.com**.
