local Config = require("todo-comments.config")
local Highlight = require("todo-comments.highlight")
local Util = require("todo-comments.util")

local M = {}

--- Validates whether cb_s is a valid task checkbox position in line
---@param line string
---@param cb_s integer 1-indexed start position of checkbox
---@param kw_start integer? 1-indexed start of preceding keyword
---@param kw_finish integer? 1-indexed finish of preceding keyword
---@return boolean
function M.is_valid_checkbox_pos(line, cb_s, kw_start, kw_finish)
  if not line or not cb_s or cb_s < 1 or cb_s > #line then
    return false
  end

  local before = line:sub(1, cb_s - 1)

  -- Reject cases where cb_s is part of identifier or type (e.g. T[ ] or any[])
  if before:match("[%w_]$") then
    return false
  end

  -- Reject cases where cb_s is inside a string literal in code (e.g. assert(x == "-- TODO: [ ]"))
  if Util.is_inside_string(before) then
    return false
  end

  -- Detect keyword prior to cb_s if kw_finish not provided or >= cb_s
  if not kw_finish or kw_finish >= cb_s then
    local ok, m_s, m_f = pcall(Highlight.match, line)
    if ok and m_s and m_f and m_s < cb_s then
      kw_start = m_s
      kw_finish = m_f
    else
      kw_finish = nil
    end
  end

  if kw_finish and kw_finish < cb_s then
    local slice = line:sub(kw_finish, cb_s - 1):gsub("^%s*:%s*", "")
    local trimmed = vim.trim(slice)
    if trimmed == "" or trimmed:match("^[%-%*%+]%s*$") or trimmed:match("^%d+%.%s*$") then
      return true
    end
    return false
  end

  -- No keyword precedes cb_s (continuation line)
  -- Extract comment leader characters up to cb_s - 1
  local rest = before:match('.*[%#%/%*%-;"%%!]+%s*(.*)$')
  if not rest then
    return false
  end

  local trimmed = vim.trim(rest)
  if trimmed == "" or trimmed:match("^[%-%*%+]%s*$") or trimmed:match("^%d+%.%s*$") then
    return true
  end

  return false
end

--- Finds a valid checkbox on line according to tasks configuration
---@param line string
---@param kw_start integer? 1-indexed start of preceding keyword
---@param kw_finish integer? 1-indexed finish of preceding keyword
---@return string? state "todo"|"doing"|"done"
---@return integer? cb_s 1-indexed start
---@return integer? cb_e 1-indexed end
function M.find_checkbox(line, kw_start, kw_finish)
  if not line then
    return nil
  end
  local tasks_opts = Config.options.tasks
  if not tasks_opts or not tasks_opts.checkboxes then
    return nil
  end
  for state, cb_cfg in pairs(tasks_opts.checkboxes) do
    if cb_cfg.pattern then
      local init = 1
      while init <= #line do
        local cb_s, cb_e = line:find(cb_cfg.pattern, init)
        if not cb_s then
          break
        end
        if M.is_valid_checkbox_pos(line, cb_s, kw_start, kw_finish) then
          return state, cb_s, cb_e
        end
        init = cb_s + 1
      end
    end
  end
  return nil
end

--- Checks whether a line is a valid continuation comment of a block
---@param line string The line content to check
---@param header_prefix string? Leading text of the block's header prior to keyword
---@param buf integer Buffer number (-1 if unloaded)
---@param row integer 0-indexed row number
---@param col integer? 0-indexed column number
---@return boolean
local function is_continuation_comment(line, header_prefix, buf, row, col)
  if not line or line:match("^%s*$") then
    return false
  end

  -- 1. If buffer has treesitter / syntax highlighting active, check it
  if buf and buf ~= -1 and vim.api.nvim_buf_is_valid(buf) then
    local ok_c, is_c = pcall(Highlight.is_comment, buf, row, col or 0)
    if ok_c and is_c ~= nil then
      return is_c
    end
  end

  -- 2. If header had a specific comment leader (e.g. "#", "--", "//", "/*", "*", ";", '"', "%")
  if header_prefix and header_prefix ~= "" then
    if Util.is_inside_string(header_prefix) then
      return false
    end
    local lead_char = header_prefix:match('([%#%/%*%-;"%%!]+)%s*$')
    if lead_char == '"' and not header_prefix:match('^%s*"') then
      lead_char = nil
    end
    if lead_char then
      local escaped = lead_char:gsub("([%^%$%(%)%%%[%]%*%+%-%?])", "%%%1")
      if line:match("^%s*" .. escaped) or line:find(lead_char, 1, true) then
        return true
      end
    else
      return false
    end
  end

  -- 3. Universal comment prefixes across languages
  if
    line:match("^%s*[%#]") -- Python, Ruby, Shell, YAML, etc.
    or line:match("^%s*%-%-") -- Lua, SQL, Haskell, etc.
    or line:match("^%s*//") -- JS, TS, C, C++, Java, Go, Rust, etc.
    or line:match("^%s*%*") -- C block comment lines: ' * subtask'
    or line:match("^%s*<!--") -- HTML, XML, Markdown
    or line:match("^%s*;") -- Lisp, Clojure, INI, Assembly
    or line:match('^%s*"') -- Vimscript
    or line:match("^%s*%%") -- LaTeX, Erlang, Matlab
  then
    return true
  end

  return false
end

--- Finds the multiline comment block containing line `lnum` (0-indexed)
---@param buf number
---@param lnum number (0-indexed)
---@return { header_lnum: integer, end_lnum: integer, kw: string }?
function M.get_block_at(buf, lnum)
  local line_count = vim.api.nvim_buf_line_count(buf)
  if lnum < 0 or lnum >= line_count then
    return nil
  end

  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1] or ""
  local ok, start, _, kw = pcall(Highlight.match, line)

  -- Case 1: Cursor is directly on the header line
  if ok and start and kw then
    kw = Config.keywords[kw] or kw
    local header_prefix = line:sub(1, start - 1)
    local end_lnum = lnum
    for next_l = lnum + 1, math.min(lnum + Config.options.highlight.multiline_context, line_count - 1) do
      local next_line = vim.api.nvim_buf_get_lines(buf, next_l, next_l + 1, false)[1] or ""
      local n_ok, n_start, _, n_kw = pcall(Highlight.match, next_line)
      if n_ok and n_start and n_kw then
        break -- found another header
      end
      if
        is_continuation_comment(next_line, header_prefix, buf, next_l, start - 1)
        and (
          next_line:find(Config.options.highlight.multiline_pattern, start)
          or next_line:find(Config.options.highlight.multiline_pattern, 1)
        )
      then
        end_lnum = next_l
      else
        break
      end
    end
    return { header_lnum = lnum, end_lnum = end_lnum, kw = kw }
  end

  -- Case 2: Cursor is on a continuation child line; scan backwards
  for prev_l = lnum - 1, math.max(0, lnum - Config.options.highlight.multiline_context), -1 do
    local prev_line = vim.api.nvim_buf_get_lines(buf, prev_l, prev_l + 1, false)[1] or ""
    local p_ok, p_start, _, p_kw = pcall(Highlight.match, prev_line)
    if p_ok and p_start and p_kw then
      local block = M.get_block_at(buf, prev_l)
      if block and block.end_lnum >= lnum then
        return block
      end
      break
    end
  end

  return nil
end

--- Reads context lines from disk or memory and calculates task and line stats:
--- { total = M, done = N, doing = P, lines = K }
---@param filename string
---@param lnum integer 1-indexed line number of the header
---@param start_col integer? 1-indexed column of the keyword in the header
---@param kw string? Keyword (e.g. "TODO", "WARN")
function M.get_block_stats(filename, lnum, start_col, kw)
  local stats = { total = 0, done = 0, doing = 0, lines = 0 }
  local max_context = (Config.options.highlight and Config.options.highlight.multiline_context) or 10

  local buf = vim.fn.bufnr(filename)
  local lines = {}
  local header_line = ""
  if buf ~= -1 and vim.api.nvim_buf_is_loaded(buf) then
    header_line = vim.api.nvim_buf_get_lines(buf, lnum - 1, lnum, false)[1] or ""
    lines = vim.api.nvim_buf_get_lines(buf, lnum, lnum + max_context, false)
  else
    if vim.fn.filereadable(filename) == 1 then
      local all_lines = vim.fn.readfile(filename, "", lnum + max_context)
      if #all_lines >= lnum then
        header_line = all_lines[lnum] or ""
        for i = lnum + 1, math.min(#all_lines, lnum + max_context) do
          table.insert(lines, all_lines[i])
        end
      end
    end
  end

  local header_prefix = ""
  if start_col and start_col > 1 and header_line ~= "" then
    header_prefix = header_line:sub(1, start_col - 1)
  else
    header_prefix = header_line:match('^(%s*[%#%/%*%-;"%%!]+)') or ""
  end
  -- If the header line is inside a string literal in code (e.g. print("TEST: ...")), ignore context
  if Util.is_inside_string(header_prefix) then
    return stats
  end

  -- If the header line itself is not a valid comment line (e.g. inside a print() string in code), ignore context
  if not is_continuation_comment(header_line, header_prefix, buf, lnum - 1, (start_col or 1) - 1) then
    return stats
  end

  local tasks_opts = Config.options.tasks
  if kw == "TODO" and tasks_opts and tasks_opts.enabled then
    local kw_finish = start_col and (start_col + #(kw or "") + 1)
    local state = M.find_checkbox(header_line, start_col, kw_finish)
    if state then
      stats.total = stats.total + 1
      if state == "done" then
        stats.done = stats.done + 1
      elseif state == "doing" then
        stats.doing = stats.doing + 1
      end
    end
  end

  for idx, line in ipairs(lines) do
    local ok, start, _, n_kw = pcall(Highlight.match, line)
    if ok and start and n_kw then
      break
    end

    local current_row = lnum + idx - 1
    if is_continuation_comment(line, header_prefix, buf, current_row, (start_col or 1) - 1) then
      local pattern = (Config.options.highlight and Config.options.highlight.multiline_pattern) or "^."
      if line:find(pattern, start_col or 1) or line:find(pattern, 1) then
        stats.lines = stats.lines + 1
        if kw == "TODO" and tasks_opts and tasks_opts.enabled then
          local state = M.find_checkbox(line)
          if state then
            stats.total = stats.total + 1
            if state == "done" then
              stats.done = stats.done + 1
            elseif state == "doing" then
              stats.doing = stats.doing + 1
            end
          end
        end
      else
        break
      end
    else
      break
    end
  end

  return stats
end

--- Cycles checkbox on current line: [ ] -> [/] -> [x] -> [ ]
function M.toggle()
  local tasks_opts = Config.options.tasks
  if tasks_opts and tasks_opts.enabled == false then
    Util.warn(
      "Task checkboxes are disabled. Enable them with 'tasks = { enabled = true }' or remove the :TodoToggle mapping."
    )
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  if not vim.bo[buf].modifiable or vim.bo[buf].readonly then
    return
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1
  local line = vim.api.nvim_buf_get_lines(buf, lnum, lnum + 1, false)[1]
  if not line then
    return
  end

  local new_line = nil
  local state, cb_s, cb_e = M.find_checkbox(line)
  if state and cb_s and cb_e then
    local next_state = { todo = "[/]", doing = "[x]", done = "[ ]" }
    local rep = next_state[state] or "[/]"
    new_line = line:sub(1, cb_s - 1) .. rep .. line:sub(cb_e + 1)
  else
    -- If line is inside a TODO block without a checkbox, insert [ ]
    local block = M.get_block_at(buf, lnum)
    if block and block.kw == "TODO" then
      if lnum == block.header_lnum then
        local start, finish = Highlight.match(line)
        if start and finish then
          local after = line:sub(finish + 1)
          if after:match("^%s") then
            new_line = line:sub(1, finish) .. " [ ]" .. after
          else
            new_line = line:sub(1, finish) .. " [ ] " .. after
          end
        end
      else
        local prefix, rest = line:match("^(%s*[%-%#%/%*]*%s*)(.*)$")
        if prefix and rest then
          new_line = prefix .. "[ ] " .. rest
        end
      end
    end
  end

  if new_line and new_line ~= line then
    local max_context = (Config.options.highlight and Config.options.highlight.multiline_context) or 10
    vim.api.nvim_buf_set_lines(buf, lnum, lnum + 1, false, { new_line })
    local h_start = math.max(0, lnum - max_context)
    local h_end = lnum + max_context
    Highlight.invalidate(buf, h_start, h_end)
    Highlight.highlight(buf, h_start, h_end)
    Highlight.update()
  end
end

--- Toggles folding for context lines under the current comment block
function M.toggle_fold()
  local hl_opts = Config.options.highlight
  if hl_opts and hl_opts.folding and hl_opts.folding.enabled == false then
    Util.warn(
      "Multiline folding is disabled. Enable it with 'highlight = { folding = { enabled = true } }' or remove the :TodoToggleFold mapping."
    )
    return
  end

  local buf = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local lnum = cursor[1] - 1
  local block = M.get_block_at(buf, lnum)
  if not block or block.end_lnum <= block.header_lnum then
    vim.notify("No multiline context lines to fold", vim.log.levels.INFO)
    return
  end

  local fold_start = block.header_lnum + 2 -- 1-indexed next line after header
  local fold_end = block.end_lnum + 1

  -- Ensure folding is enabled on window, allows 1-line folds, and permits manual fold creation.
  -- Using 'noautocmd setlocal' prevents Neovim's runtime Treesitter OptionSet handler
  -- from throwing errors if stale/invalid buffer IDs exist in its session cache.
  vim.wo.foldenable = true
  if vim.wo.foldminlines and vim.wo.foldminlines > 0 then
    pcall(vim.cmd, "noautocmd setlocal foldminlines=0")
  end
  if vim.wo.foldmethod ~= "manual" and vim.wo.foldmethod ~= "marker" then
    pcall(vim.cmd, "noautocmd setlocal foldmethod=manual")
  end

  local is_folded = vim.fn.foldclosed(fold_start) ~= -1
  if is_folded then
    pcall(vim.cmd, string.format("%d,%dfoldopen!", fold_start, fold_end))
  else
    pcall(vim.cmd, string.format("%d,%dfold", fold_start, fold_end))
  end

  Highlight.invalidate(buf, block.header_lnum, block.end_lnum)
  Highlight.highlight(buf, block.header_lnum, block.end_lnum)
  Highlight.update()
end

return M
