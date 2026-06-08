# strudel-types.nvim

Real completion + hover (and **no** false "undefined global" diagnostics) for
[Strudel](https://strudel.cc) `.str`/`.std` files in Neovim, via `ts_ls`/`vtsls`.

It feeds tsserver an ambient `declare global` typedef of Strudel's whole API,
auto-generated from Strudel's own JSDoc — so you get `note`, `s`, `jux`, `stack`,
`gain`, … as known globals with parameter hints, descriptions and `@example`s on
hover, and method-chaining completion (`s("bd").gain(.5).slow(2)`).

Companion to [`gruvw/strudel.nvim`](https://github.com/gruvw/strudel.nvim), which
sets `.str`/`.std` files to `filetype=javascript`.

## Why this exists

Strudel runs your code with every function dumped onto `globalThis` (no imports),
so a `.str` file is full of bare globals tsserver doesn't know — it either says
nothing useful, or (with `checkJs`) floods the buffer with `Cannot find name`.
A plain `jsconfig.json` can't fix it: **tsserver refuses to add `.str` files to a
project** because it doesn't recognise the extension. The trick that works: pin
the TS server's `root_dir` for `.str`/`.std` buffers (and for this typedef) to one
fixed directory, and load the typedef as a hidden buffer — the two then share an
inferred project and the ambient globals resolve, with **zero edits to your patches
and nothing dropped in your music folder**.

## Install (lazy.nvim)

```lua
{
  'Ovsiankina/strudel-types.nvim',
  dependencies = { 'gruvw/strudel.nvim' },
  lazy = false, -- tiny; just registers an autocmd + commands so root_dir helpers exist
  config = function()
    require('strudel-types').setup({
      -- preview_progress_min_ms = 0, -- show the <Tab> progress bar only for sounds
      --                              -- at least N ms long; 0 (default) = always show
    })
  end,
}
```

Then add the **root_dir pin** to your `ts_ls`/`vtsls` config so Strudel buffers and
the typedef land in one project (this is a tsserver setting, so it lives in your LSP
config, not here):

```lua
root_dir = function(bufnr, on_dir)
  local ok, st = pcall(require, 'strudel-types')
  if ok and st.is_strudel_root(bufnr) then
    on_dir(st.types_dir())
    return
  end
  on_dir(
    vim.fs.root(bufnr, { 'tsconfig.json', 'jsconfig.json', 'package.json', '.git' })
      or vim.fs.dirname(vim.api.nvim_buf_get_name(bufnr))
  )
end,
```

Recommended: run a single TS server on `.str` buffers (don't let both `ts_ls` and
`vtsls` attach), or you'll see doubled completions/diagnostics.

## Usage

Open a `.str` file → completion and hover work immediately (the typedef is loaded
lazily on the first `.str`/`.std` buffer, so there's no startup cost). Prefer to be
asked first? `setup({ prompt = true })`.

Mini-notation works as a method receiver too: the pattern methods are mirrored onto
`String`/`Number`, so `"<0 1>".pickRestart([...])` and `"bd*4".s().fast(2)` type-check
just like `mini("<0 1>")...`. Your own `register('name', ...)` methods don't break the
chain either (an index signature keeps them typed as `Pattern`), though they won't
have real hover/param docs since they're defined at runtime in the patch.

### Sound picker

`<leader>mf` (buffer-local to `.str`/`.std`) — or `:StrudelSounds` — opens a fuzzy
picker of every Strudel sound (synths + GM soundfonts + default samples) and inserts
the chosen name at your cursor (put it inside `s("…")`). Uses telescope if available,
otherwise `vim.ui.select`.

**Imported sounds** declared in the buffer via `samples(...)` are resolved and listed
**first, labelled with their source** — e.g. `swpad ‹switchangel/pad›`. Works for
`github:user/repo` and `strudel.json` URLs. A running local **`@strudel/sampler`**
(`config.sampler_urls`, default `http://localhost:5432`) is **auto-detected** even with
no `samples()` call in the buffer, and **each of its files is listed individually**
(`samples:0  Abr-chiptune1 ‹localhost:5432›`, …) so you can fuzzy-find and preview each
— re-scanned every open, so new files show up. Bundled defaults follow with no label
(no label = the default Strudel bank). Imported sounds preview too.

> To actually *play* a local-sampler sound in a pattern you still need the
> `samples('http://localhost:5432')` call in your file — the picker shows/auditions
> them regardless.

In the telescope picker, **`<Tab>` previews** the highlighted sound (cached after the
first fetch), played via `mpv`/`ffplay`/`pw-play`/`paplay` (first found). A loading
**spinner** shows while it fetches, then a **progress bar** for the sound's duration
(needs `ffprobe`; gate it with `preview_progress_min_ms`). What previews:
- **samples** (~373, incl. your imports) play their first sample file;
- **GM soundfonts** (`gm_*`, ~125) are decoded from their webaudiofont preset by
  `scripts/preview-soundfont.mjs` (needs `node`) — a single mid-range note;
- the ~26 **built-in synths** (sine, sawtooth, …) are generated in the browser, so
  there's nothing to fetch — they report "no preview".

The list is bundled (`lua/strudel-types/sounds.lua`, ~520 sounds + 137 drum-machine
banks + preview URLs); `:StrudelSoundsUpdate` (or `scripts/gen-sounds.sh`) regenerates
it from Strudel's sound registrations and prebaked sample maps.

- `:StrudelTypesUpdate` — regenerate the typedef from the latest Strudel JSDoc.
- `:StrudelTypesEnable` / `:StrudelTypesDisable` — toggle for the session.

## Regenerating the types

`types/strudel.d.ts` is generated and committed. To refresh when Strudel's API
moves, run `:StrudelTypesUpdate` (or `scripts/gen-types.sh`). It shallow-clones
Strudel, runs its `jsdoc -> doc.json` step, and emits the `.d.ts` via
`scripts/emit.mjs`. Hot functions get hand-tuned signatures in `scripts/overrides.mjs`.

Requires `git`, `node`, `npm` and network access.
