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
      auto = false, -- false = ask once per session before enabling; true = always on
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

Open a `.str` file → accept the prompt (or set `auto = true`). Completion and hover
work immediately.

- `:StrudelTypesUpdate` — regenerate the typedef from the latest Strudel JSDoc.
- `:StrudelTypesEnable` / `:StrudelTypesDisable` — toggle for the session.

## Regenerating the types

`types/strudel.d.ts` is generated and committed. To refresh when Strudel's API
moves, run `:StrudelTypesUpdate` (or `scripts/gen-types.sh`). It shallow-clones
Strudel, runs its `jsdoc -> doc.json` step, and emits the `.d.ts` via
`scripts/emit.mjs`. Hot functions get hand-tuned signatures in `scripts/overrides.mjs`.

Requires `git`, `node`, `npm` and network access.
