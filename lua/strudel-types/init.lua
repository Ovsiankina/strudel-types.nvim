-- strudel-types.nvim
--
-- Gives ts_ls/vtsls real completion + hover for Strudel `.str`/`.std` files and
-- stops false "undefined global" diagnostics, by feeding tsserver an ambient
-- `declare global` typedef of Strudel's API (types/strudel.d.ts).
--
-- How it works (see README): tsserver won't add a `.str` file to a jsconfig
-- project (unknown extension), but two loose files sharing a project root land in
-- the same inferred project. So we (1) pin the TS server's root_dir for `.str`/
-- `.std` buffers AND for our bundled typedef to one fixed dir (this plugin's
-- types/ dir), and (2) load the typedef as a hidden buffer when you open a `.str`
-- file. The ambient globals then resolve in the patch with zero edits to it.
--
-- The root_dir pin lives in YOUR LSP config (it's a tsserver setting); this module
-- provides the helpers it calls. See README for the snippet.

local M = {}

-- Plugin root, derived from this file's location (.../lua/strudel-types/init.lua).
local function plugin_root()
  local src = debug.getinfo(1, 'S').source:gsub('^@', '')
  return vim.fn.fnamemodify(src, ':h:h:h')
end

local ROOT = plugin_root()

--- Directory that must be the tsserver root for Strudel buffers.
function M.types_dir()
  return ROOT .. '/types'
end

--- Absolute path of the generated ambient typedef.
function M.dts_path()
  return M.types_dir() .. '/strudel.d.ts'
end

--- True if `bufnr` is a Strudel source file or our bundled typedef. Used by the
--- vtsls/ts_ls `root_dir` function in your config to pin them to one project.
function M.is_strudel_root(bufnr)
  local name = vim.api.nvim_buf_get_name(bufnr or 0)
  if name == '' then return false end
  if name:match('%.str$') or name:match('%.std$') then return true end
  return name == M.dts_path()
end

-- Session state: nil = ask, true = on, false = off.
local enabled = nil

--- Load the typedef as a hidden buffer so tsserver pulls it into the shared
--- inferred project. Idempotent.
local function load_typedef()
  local dts = M.dts_path()
  if vim.fn.filereadable(dts) == 0 then
    vim.notify(
      '[strudel-types] typedef not generated yet:\n' .. dts .. '\nRun :StrudelTypesUpdate',
      vim.log.levels.WARN
    )
    return false
  end
  local b = vim.fn.bufadd(dts)
  vim.fn.bufload(b)
  vim.bo[b].buflisted = false
  if vim.bo[b].filetype ~= 'typescript' then
    vim.bo[b].filetype = 'typescript' -- triggers vtsls/ts_ls attach
  end
  return true
end

--- Turn type support on for this session and load the typedef now.
function M.enable()
  enabled = true
  return load_typedef()
end

--- Turn type support off for this session.
function M.disable()
  enabled = false
end

local function on_strudel_buf()
  if enabled == false then return end
  if enabled == true then
    load_typedef()
    return
  end
  -- enabled == nil: ask once (uses your vim.ui.select UI, e.g. noice/telescope).
  vim.ui.select(
    { 'Yes', 'Not now', 'No (this session)' },
    { prompt = 'Strudel: enable completion/hover for .str files?' },
    function(choice)
      if choice == 'Yes' then
        M.enable()
      elseif choice == 'No (this session)' then
        M.disable()
      end
      -- 'Not now' / cancelled: leave state nil, ask again on the next .str file.
    end
  )
end

--- Regenerate types/strudel.d.ts from Strudel's JSDoc (async).
function M.update()
  local script = ROOT .. '/scripts/gen-types.sh'
  if vim.fn.filereadable(script) == 0 then
    vim.notify('[strudel-types] missing ' .. script, vim.log.levels.ERROR)
    return
  end
  vim.notify('[strudel-types] regenerating types… (clones Strudel, ~1 min)')
  vim.system({ 'bash', script }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        vim.notify('[strudel-types] types updated.')
        local b = vim.fn.bufnr(M.dts_path())
        if b ~= -1 then
          pcall(vim.cmd, 'checktime ' .. b) -- reload the typedef buffer if open
        end
      else
        vim.notify('[strudel-types] update failed:\n' .. (res.stderr or '?'), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- Regenerate the sound list (scripts/gen-sounds.sh) (async).
function M.update_sounds()
  local script = ROOT .. '/scripts/gen-sounds.sh'
  if vim.fn.filereadable(script) == 0 then
    vim.notify('[strudel-types] missing ' .. script, vim.log.levels.ERROR)
    return
  end
  vim.notify('[strudel-types] regenerating sound list…')
  vim.system({ 'bash', script }, { text = true }, function(res)
    vim.schedule(function()
      if res.code == 0 then
        vim.notify('[strudel-types] sound list updated.')
      else
        vim.notify('[strudel-types] sound update failed:\n' .. (res.stderr or '?'), vim.log.levels.ERROR)
      end
    end)
  end)
end

--- The list of Strudel sound names (generated; see scripts/gen-sounds.sh).
function M.sounds()
  package.loaded['strudel-types.sounds'] = nil -- always read the current data
  local ok, data = pcall(require, 'strudel-types.sounds')
  if not ok or type(data) ~= 'table' then return {} end
  return data.sounds or data -- {sounds=...,banks=...} or a flat list
end

-- Runtime config (see M.setup).
M.config = {
  -- Show the playback progress bar only for sounds at least this long, in ms.
  -- 0 = always show (default). Needs ffprobe to know the duration.
  preview_progress_min_ms = 0,
  -- Local sampler servers to auto-detect in the picker (e.g. a running
  -- `npx @strudel/sampler`), even when the buffer has no samples() call for them.
  -- Probed on every picker open; if the server is down it's silently skipped.
  -- Set to {} to disable.
  sampler_urls = { 'http://localhost:5432' },
}

-- ── preview HUD: a small bottom-right float for the loading spinner + bar ──────
local uv = vim.uv or vim.loop
local SPINNER = { '⠋', '⠙', '⠹', '⠸', '⠼', '⠴', '⠦', '⠧', '⠇', '⠏' }
local hud = { win = nil, buf = nil, timer = nil }

local function hud_close()
  if hud.timer then pcall(vim.fn.timer_stop, hud.timer) end
  hud.timer = nil
  if hud.win and vim.api.nvim_win_is_valid(hud.win) then pcall(vim.api.nvim_win_close, hud.win, true) end
  hud.win = nil
end

local function hud_show(text)
  if not (hud.buf and vim.api.nvim_buf_is_valid(hud.buf)) then
    hud.buf = vim.api.nvim_create_buf(false, true)
  end
  if not (hud.win and vim.api.nvim_win_is_valid(hud.win)) then
    hud.win = vim.api.nvim_open_win(hud.buf, false, {
      relative = 'editor', anchor = 'SE',
      row = vim.o.lines - 2, col = vim.o.columns - 1,
      width = 40, height = 1, style = 'minimal', border = 'rounded',
      focusable = false, noautocmd = true, zindex = 300,
    })
  end
  pcall(vim.api.nvim_buf_set_lines, hud.buf, 0, -1, false, { ' ' .. text })
end

local function hud_spinner(label)
  hud_close()
  local i = 0
  hud.timer = vim.fn.timer_start(80, function()
    i = i % #SPINNER + 1
    hud_show(SPINNER[i] .. ' ' .. label)
  end, { ['repeat'] = -1 })
  hud_show(SPINNER[1] .. ' ' .. label)
end

local function hud_progress(label, dur_ms)
  if hud.timer then pcall(vim.fn.timer_stop, hud.timer) end
  local W = 20
  local start = uv.now()
  local function tick()
    local frac = math.min(1, (uv.now() - start) / dur_ms)
    local n = math.floor(frac * W + 0.5)
    hud_show('▶ ' .. label .. ' ' .. string.rep('▰', n) .. string.rep('▱', W - n))
    if frac >= 1 then hud_close() end
  end
  hud.timer = vim.fn.timer_start(60, tick, { ['repeat'] = -1 })
  tick()
end

-- ── audio preview ─────────────────────────────────────────────────────────────
local PREVIEW_PLAYERS = {
  { 'mpv', '--no-video', '--really-quiet', '--no-terminal' },
  { 'ffplay', '-nodisp', '-autoexit', '-loglevel', 'quiet' },
  { 'pw-play' },
  { 'paplay' },
}
local preview_job
local preview_token = 0

local function find_player()
  for _, p in ipairs(PREVIEW_PLAYERS) do
    if vim.fn.executable(p[1]) == 1 then return p end
  end
end

--- Stop any running preview (kills the player + hides the HUD).
function M.stop_preview()
  preview_token = preview_token + 1
  if preview_job then pcall(function() preview_job:kill(9) end) end
  preview_job = nil
  hud_close()
end

--- Preview a sound. opts = { name, url?, preset?, source? }. A sample `url` plays
--- directly; a gm `preset` is decoded via scripts/preview-soundfont.mjs; otherwise
--- the name is looked up in the bundled data; built-in synths have no preview.
--- Shows a loading spinner, then a progress bar (if duration >= configured min).
function M.preview(opts)
  local name = opts.name
  if not name or name == '' then return end
  package.loaded['strudel-types.sounds'] = nil
  local ok, data = pcall(require, 'strudel-types.sounds')
  data = (ok and type(data) == 'table') and data or {}
  local url = opts.url or (data.urls and data.urls[name])
  local preset = opts.preset or (data.soundfonts and data.soundfonts[name])
  if not url and not preset then
    vim.notify('[strudel-types] no audio preview for "' .. name .. '" (built-in synth)', vim.log.levels.INFO)
    return
  end
  if not find_player() then
    vim.notify('[strudel-types] no audio player found (install mpv or ffplay)', vim.log.levels.WARN)
    return
  end

  preview_token = preview_token + 1
  local tok = preview_token
  local function current() return tok == preview_token end
  if preview_job then pcall(function() preview_job:kill(9) end) end
  preview_job = nil

  local label = opts.source and (name .. ' ‹' .. opts.source .. '›') or name
  hud_spinner(label)

  local key = ((opts.source and opts.source:gsub('[^%w]', '_') .. '_') or '') .. name:gsub('[^%w%-_]', '_')
  local dir = vim.fn.stdpath 'cache' .. '/strudel-types/sounds'
  vim.fn.mkdir(dir, 'p')

  local function play_file(file)
    if not current() then return end
    local player = find_player()
    if preview_job then pcall(function() preview_job:kill(9) end) end
    local cmd = vim.deepcopy(player)
    cmd[#cmd + 1] = file
    preview_job = vim.system(cmd, { text = true })
    if vim.fn.executable 'ffprobe' == 1 then
      vim.system(
        { 'ffprobe', '-v', 'quiet', '-show_entries', 'format=duration', '-of', 'csv=p=0', file },
        { text = true },
        function(r)
          vim.schedule(function()
            if not current() then return end
            local secs = tonumber((r.stdout or ''):match '%d+%.?%d*')
            local dur_ms = secs and secs * 1000 or nil
            if dur_ms and dur_ms >= (M.config.preview_progress_min_ms or 0) then
              hud_progress(label, dur_ms)
            else
              hud_close()
            end
          end)
        end
      )
    else
      hud_show('▶ ' .. label)
      vim.defer_fn(function() if current() then hud_close() end end, 1200)
    end
  end

  if url then
    local ext = url:match '%.(%w+)$' or 'wav'
    local file = dir .. '/' .. key .. '.' .. ext
    if vim.fn.filereadable(file) == 1 then
      play_file(file)
    else
      vim.system({ 'curl', '-fsSL', '--max-time', '20', '-o', file, url }, {}, function(r)
        vim.schedule(function()
          if not current() then return end
          if r.code == 0 and vim.fn.filereadable(file) == 1 then
            play_file(file)
          else
            hud_close()
            vim.notify('[strudel-types] preview download failed: ' .. name, vim.log.levels.WARN)
          end
        end)
      end)
    end
  else -- gm_* soundfont: decode a note from its webaudiofont preset
    local file = dir .. '/' .. key .. '.mp3'
    if vim.fn.filereadable(file) == 1 then
      play_file(file)
    elseif vim.fn.executable 'node' == 0 then
      hud_close()
      vim.notify('[strudel-types] node is required to preview soundfonts', vim.log.levels.WARN)
    else
      vim.system({ 'node', ROOT .. '/scripts/preview-soundfont.mjs', preset, file }, { text = true }, function(r)
        vim.schedule(function()
          if not current() then return end
          if r.code == 0 and vim.fn.filereadable(file) == 1 then
            play_file(file)
          else
            hud_close()
            vim.notify('[strudel-types] soundfont preview failed: ' .. name, vim.log.levels.WARN)
          end
        end)
      end)
    end
  end
end

--- Back-compat: preview a bundled sound by name.
function M.play_sound(name)
  M.preview { name = name }
end

-- ── imported sample banks: samples('github:user/repo') / samples('https://…') ──
local spec_cache = {} -- spec string -> { source=.., sounds={{name,url,source}} } | false

local function first_file(v)
  if type(v) == 'string' then return v end
  if type(v) == 'table' then
    for _, x in pairs(v) do
      local f = first_file(x)
      if f then return f end
    end
  end
  return nil
end

-- All sample files under a map value (array and/or note-object), in order.
local function all_files(v, acc)
  acc = acc or {}
  if type(v) == 'string' then
    acc[#acc + 1] = v
  elseif type(v) == 'table' then
    if v[1] ~= nil then
      for _, x in ipairs(v) do all_files(x, acc) end
    else
      for _, x in pairs(v) do all_files(x, acc) end
    end
  end
  return acc
end

-- "/foo/bar/Kick_01.wav" -> "Kick_01"
local function basename(p)
  return (p:gsub('%.%w+$', ''):match '([^/]+)$') or p
end

-- spec -> { candidate strudel.json URLs }, source label
local function spec_urls(spec)
  local gh = spec:match '^github:(.+)$'
  if gh then
    local segs = vim.split(gh, '/', { plain = true })
    local user, repo, branch = segs[1], segs[2], segs[3]
    if not user or user == '' or not repo or repo == '' then return nil end
    local source = user .. '/' .. repo
    if branch and branch ~= '' then
      return { ('https://raw.githubusercontent.com/%s/%s/%s/strudel.json'):format(user, repo, branch) }, source
    end
    return {
      ('https://raw.githubusercontent.com/%s/%s/main/strudel.json'):format(user, repo),
      ('https://raw.githubusercontent.com/%s/%s/master/strudel.json'):format(user, repo),
    }, source
  end
  if spec:match '^https?://' then
    local source = spec:gsub('^https?://', ''):gsub('/strudel%.json$', ''):gsub('/$', '')
    if spec:match '%.json$' then return { spec }, source end
    -- @strudel/sampler serves the map at the ROOT; static hosts may use /strudel.json
    local b = spec:gsub('/$', '')
    return { b, b .. '/strudel.json' }, source
  end
  return nil -- shabda:/local: etc unsupported
end

local function join_url(base, file)
  if file:match '^https?://' then return file end
  base = (base or ''):gsub('/$', '')
  if file:sub(1, 1) == '/' then return base .. file end
  return base .. '/' .. file
end

-- base dir for resolving relative sample files when the map has no _base
local function url_base(fetched)
  return (fetched or ''):gsub('/strudel%.json$', ''):gsub('/$', '')
end

-- Parse a strudel.json-style map into sound entries.
-- expand=true (local sampler) emits ONE entry per file (bank:index, with the
-- filename) so every sample is browsable; otherwise one entry per bank.
local function parse_map(json, source, fetched_url, expand)
  local ok, o = pcall(vim.json.decode, json)
  if not ok or type(o) ~= 'table' then return nil end
  local base = (o._base and o._base ~= '') and o._base or url_base(fetched_url)
  local out = {}
  for k, v in pairs(o) do
    if k ~= '_base' then
      if expand then
        local files = all_files(v)
        if #files <= 1 then
          out[#out + 1] = { name = k, url = files[1] and join_url(base, files[1]) or nil, source = source, file = files[1] and basename(files[1]) or nil }
        else
          for i, f in ipairs(files) do
            out[#out + 1] = { name = k .. ':' .. (i - 1), url = join_url(base, f), source = source, file = basename(f) }
          end
        end
      else
        local f = first_file(v)
        out[#out + 1] = { name = k, url = f and join_url(base, f) or nil, source = source }
      end
    end
  end
  return out
end

-- expand banks per-file only for configured local samplers (not big github banks)
local function is_sampler(spec)
  for _, u in ipairs(M.config.sampler_urls or {}) do
    if u == spec then return true end
  end
  return false
end

--- samples() specs declared in a buffer (deduped, in order).
function M.buffer_specs(bufnr)
  local specs, seen = {}, {}
  local pat = [[samples%s*%(%s*(['"])([^'"]*)%1]]
  for _, l in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for _, spec in l:gmatch(pat) do
      if not seen[spec] then
        seen[spec] = true
        specs[#specs + 1] = spec
      end
    end
  end
  return specs
end

-- All specs to resolve for a buffer: configured sampler URLs (auto-detected, e.g.
-- a running @strudel/sampler) + the buffer's own samples() calls, deduped.
local function all_specs(bufnr)
  local specs, seen = {}, {}
  for _, u in ipairs(M.config.sampler_urls or {}) do
    if u ~= '' and not seen[u] then
      seen[u] = true
      specs[#specs + 1] = u
    end
  end
  for _, s in ipairs(M.buffer_specs(bufnr)) do
    if not seen[s] then
      seen[s] = true
      specs[#specs + 1] = s
    end
  end
  return specs
end

--- Background-resolve a buffer's samples() imports so the picker opens warm.
function M.prefetch_imports(bufnr)
  for _, spec in ipairs(all_specs(bufnr)) do
    if spec_cache[spec] == nil then
      local tries, source = spec_urls(spec)
      if tries then
        local i = 0
        local function try()
          i = i + 1
          local u = tries[i]
          if not u then
            spec_cache[spec] = false
            return
          end
          vim.system({ 'curl', '-fsSL', '--max-time', '6', u }, { text = true }, function(r)
            vim.schedule(function()
              local sounds = (r.code == 0 and r.stdout ~= '') and parse_map(r.stdout, source, u, is_sampler(spec)) or nil
              if sounds then
                spec_cache[spec] = { source = source, sounds = sounds }
              else
                try()
              end
            end)
          end)
        end
        try()
      else
        spec_cache[spec] = false
      end
    end
  end
end

--- Sounds imported by the buffer's samples() calls: { {name,url,source}, ... }.
--- Resolves (and caches) any specs not already fetched (synchronously).
function M.imported_sounds(bufnr)
  local out = {}
  -- re-detect sampler URLs each call (a running sampler's files can change)
  for _, u in ipairs(M.config.sampler_urls or {}) do spec_cache[u] = nil end
  for _, spec in ipairs(all_specs(bufnr)) do
    local c = spec_cache[spec]
    if type(c) ~= 'table' then -- nil or false (failed/not-ready): try now
      local tries, source = spec_urls(spec)
      c = false
      if tries then
        for _, u in ipairs(tries) do
          local r = vim.system({ 'curl', '-fsSL', '--max-time', '6', u }, { text = true }):wait()
          if r.code == 0 and r.stdout and r.stdout ~= '' then
            local sounds = parse_map(r.stdout, source, u, is_sampler(spec))
            if sounds then
              c = { source = source, sounds = sounds }
              break
            end
          end
        end
      end
      spec_cache[spec] = c
    end
    if type(c) == 'table' then
      for _, s in ipairs(c.sounds) do
        out[#out + 1] = s
      end
    end
  end
  return out
end

--- Fuzzy-pick a Strudel sound and insert it at the cursor. Bound to <leader>mf in
--- .str/.std buffers. Imported sounds (from the buffer's samples() calls) appear
--- first, labelled with their source (e.g. "swpad ‹switchangel/pad›"); bundled
--- defaults follow unlabelled. <Tab> previews the highlighted sound (loading
--- spinner + progress bar), <CR> inserts the name. Uses telescope, else ui.select.
function M.sound_picker()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local pos = vim.api.nvim_win_get_cursor(win)

  local entries = {}
  for _, s in ipairs(M.imported_sounds(buf)) do
    -- Show the filename only when it adds info (multi-file banks use bank:index
    -- names, so the basename disambiguates; a named single-file bank doesn't).
    local extra = (s.file and s.file ~= s.name) and ('  ' .. s.file) or ''
    local label = s.name .. extra .. '  ‹' .. s.source .. '›'
    entries[#entries + 1] = { value = s.name, label = label, url = s.url, source = s.source }
  end
  for _, name in ipairs(M.sounds()) do
    entries[#entries + 1] = { value = name, label = name }
  end
  if #entries == 0 then
    vim.notify('[strudel-types] no sounds found. Run :StrudelSoundsUpdate', vim.log.levels.WARN)
    return
  end

  local function insert(e)
    if not e or not e.value then return end
    pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { e.value })
    pcall(vim.api.nvim_win_set_cursor, win, { pos[1], pos[2] + #e.value })
  end

  local ok_tel, pickers = pcall(require, 'telescope.pickers')
  if not ok_tel then
    vim.ui.select(entries, { prompt = 'Strudel sound', format_item = function(e) return e.label end }, insert)
    return
  end
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Strudel sounds  (<Tab> preview)',
      finder = finders.new_table {
        results = entries,
        entry_maker = function(e)
          return { value = e, display = e.label, ordinal = e.label }
        end,
      },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr, map)
        -- stop preview + hide HUD whenever the picker closes (select/esc/etc.)
        vim.api.nvim_create_autocmd('BufWipeout', {
          buffer = prompt_bufnr,
          once = true,
          callback = function() M.stop_preview() end,
        })
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          if entry then insert(entry.value) end
        end)
        local function preview()
          local entry = action_state.get_selected_entry()
          if entry and entry.value then
            M.preview { name = entry.value.value, url = entry.value.url, source = entry.value.source }
          end
        end
        map('i', '<Tab>', preview)
        map('n', '<Tab>', preview)
        return true
      end,
    })
    :find()
end

--- @param opts table|nil  { prompt = false }
---   Default: always-on for .str/.std (loads lazily on first such buffer, no prompt).
---   Set prompt=true to be asked once per session before enabling.
function M.setup(opts)
  opts = opts or {}
  if not opts.prompt then enabled = true end
  if opts.preview_progress_min_ms ~= nil then
    M.config.preview_progress_min_ms = opts.preview_progress_min_ms
  end
  if opts.sampler_urls ~= nil then
    M.config.sampler_urls = opts.sampler_urls
  end

  local grp = vim.api.nvim_create_augroup('StrudelTypes', { clear = true })
  vim.api.nvim_create_autocmd({ 'BufReadPost', 'BufNewFile' }, {
    group = grp,
    pattern = { '*.str', '*.std' },
    callback = function(ev)
      -- Buffer-local sound picker (scoped to .str/.std, never leaks to other files).
      vim.keymap.set('n', '<leader>mf', M.sound_picker, {
        buffer = ev.buf,
        desc = 'Strudel: find/insert sound',
      })
      -- warm the imported-sample cache so the picker opens instantly
      vim.schedule(function() pcall(M.prefetch_imports, ev.buf) end)
      -- defer so strudel.nvim's filetype=javascript autocmd and the LSP attach
      -- have run first.
      vim.schedule(on_strudel_buf)
    end,
  })

  vim.api.nvim_create_user_command('StrudelTypesUpdate', M.update, { desc = 'Regenerate Strudel typedefs' })
  vim.api.nvim_create_user_command('StrudelTypesEnable', function() M.enable() end, { desc = 'Enable Strudel type support (this session)' })
  vim.api.nvim_create_user_command('StrudelTypesDisable', M.disable, { desc = 'Disable Strudel type support (this session)' })
  vim.api.nvim_create_user_command('StrudelSounds', M.sound_picker, { desc = 'Pick a Strudel sound and insert it at the cursor' })
  vim.api.nvim_create_user_command('StrudelSoundsUpdate', M.update_sounds, { desc = 'Regenerate the Strudel sound list' })
end

return M
