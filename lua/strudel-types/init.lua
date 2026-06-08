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

--- Fuzzy-pick a Strudel sound and insert it at the cursor. Bound to <leader>mf
--- in .str/.std buffers. Uses telescope if present, else vim.ui.select.
function M.sound_picker()
  local win = vim.api.nvim_get_current_win()
  local buf = vim.api.nvim_win_get_buf(win)
  local pos = vim.api.nvim_win_get_cursor(win) -- {row(1-based), col(0-based)}
  local sounds = M.sounds()
  if #sounds == 0 then
    vim.notify('[strudel-types] no sound list found. Run :StrudelSoundsUpdate', vim.log.levels.WARN)
    return
  end
  local function insert(name)
    if not name or name == '' then return end
    pcall(vim.api.nvim_buf_set_text, buf, pos[1] - 1, pos[2], pos[1] - 1, pos[2], { name })
    pcall(vim.api.nvim_win_set_cursor, win, { pos[1], pos[2] + #name })
  end

  local ok_tel, pickers = pcall(require, 'telescope.pickers')
  if not ok_tel then
    vim.ui.select(sounds, { prompt = 'Strudel sound' }, insert)
    return
  end
  local finders = require 'telescope.finders'
  local conf = require('telescope.config').values
  local actions = require 'telescope.actions'
  local action_state = require 'telescope.actions.state'
  pickers
    .new({}, {
      prompt_title = 'Strudel sounds',
      finder = finders.new_table { results = sounds },
      sorter = conf.generic_sorter {},
      attach_mappings = function(prompt_bufnr)
        actions.select_default:replace(function()
          local entry = action_state.get_selected_entry()
          actions.close(prompt_bufnr)
          insert(entry and (entry.value or entry[1]))
        end)
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
