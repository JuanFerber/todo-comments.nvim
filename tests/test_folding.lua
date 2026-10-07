-- tests/test_folding.lua
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.cmd([[syntax on]])

local todo = require("todo-comments")
todo.setup()

local buf = vim.fn.bufadd("tests/sample.lua")
vim.fn.bufload(buf)
vim.bo[buf].filetype = "lua"
vim.api.nvim_set_current_buf(buf)

local Tasks = require("todo-comments.tasks")
local Highlight = require("todo-comments.highlight")
local ns = require("todo-comments.config").ns

print("\n--- TEST 1: MULTILINE FOLDING & ARROW ROTATION ---")
-- 1. Initial State: Unfolded / Open
Highlight.highlight(buf, 0, vim.api.nvim_buf_line_count(buf))
local marks_open = vim.api.nvim_buf_get_extmarks(buf, ns, { 18, 0 }, { 18, -1 }, { details = true })
local vt_open = marks_open[1] and marks_open[1][4].virt_text or {}
print("Unfolded State (Line 19):", vim.inspect(vt_open))
assert(vt_open[1][1] == "▼ ", "Expected down arrow icon ▼ in open state")

-- 2. Fold block at line 19 (TODO: 2FA)
vim.api.nvim_win_set_cursor(0, { 19, 0 })
Tasks.toggle_fold()

local marks_closed = vim.api.nvim_buf_get_extmarks(buf, ns, { 18, 0 }, { 18, -1 }, { details = true })
local vt_closed = marks_closed[1] and marks_closed[1][4].virt_text or {}
print("Folded State (Line 19):", vim.inspect(vt_closed))
assert(vt_closed[1][1] == "▶ ", "Expected right arrow icon ▶ in folded state")

-- Verify that in folded state, the (+4 lines) indicator is displayed
local has_lines_text = false
for _, chunk in ipairs(vt_closed) do
  if chunk[1]:find("%(%+4 lines%)") then
    has_lines_text = true
  end
end
assert(has_lines_text, "Expected (+4 lines) text in folded state")

-- 3. Re-open / Unfold
Tasks.toggle_fold()
local marks_reopened = vim.api.nvim_buf_get_extmarks(buf, ns, { 18, 0 }, { 18, -1 }, { details = true })
local vt_reopened = marks_reopened[1] and marks_reopened[1][4].virt_text or {}
print("Reopened State (Line 19):", vim.inspect(vt_reopened))
assert(vt_reopened[1][1] == "▼ ", "Expected down arrow icon ▼ after reopening")

-- 4. Test 1-line context folding (regression test for foldminlines)
print("\n--- TEST 2: SINGLE-LINE CONTEXT FOLDING (foldminlines regression) ---")
Highlight.highlight(buf, 0, vim.api.nvim_buf_line_count(buf))
-- Line 67 in sample.lua is: "  -- NOTE: Single context line block"
vim.api.nvim_win_set_cursor(0, { 67, 4 })
Tasks.toggle_fold()

local marks_1l_closed = vim.api.nvim_buf_get_extmarks(buf, ns, { 66, 0 }, { 66, -1 }, { details = true })
local vt_1l_closed = marks_1l_closed[1] and marks_1l_closed[1][4].virt_text or {}
print("1-Line Folded State (Line 67):", vim.inspect(vt_1l_closed))
assert(vt_1l_closed[1][1] == "▶ ", "Expected ▶ on 1-line folded comment")
local has_1l_text = false
for _, chunk in ipairs(vt_1l_closed) do
  if chunk[1]:find("%(%+1 lines%)") then
    has_1l_text = true
  end
end
assert(has_1l_text, "Expected (+1 lines) text in 1-line folded state")

-- Reopen 1-line fold
Tasks.toggle_fold()
local marks_1l_reopened = vim.api.nvim_buf_get_extmarks(buf, ns, { 66, 0 }, { 66, -1 }, { details = true })
local vt_1l_reopened = marks_1l_reopened[1] and marks_1l_reopened[1][4].virt_text or {}
print("1-Line Reopened State (Line 67):", vim.inspect(vt_1l_reopened))
assert(vt_1l_reopened[1][1] == "▼ ", "Expected ▼ on 1-line reopened comment")

-- 5. Regression test: Verify that folding Line 9 does not slice neighboring blocks (Lines 19, 26, 32, 43)
print("\n--- TEST 3: MULTI-BLOCK ATOMICITY UNDER FOLDING AND VIEWPORT INVALIDATION ---")
local function get_mark_text(line_num)
  local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { line_num - 1, 0 }, { line_num - 1, -1 }, { details = true })
  for _, m in ipairs(marks) do
    local vt = m[4].virt_text
    if vt then
      local str = ""
      for _, c in ipairs(vt) do str = str .. c[1] end
      return str
    end
  end
  return "NONE"
end

-- Fold Line 9 (WARN)
vim.api.nvim_win_set_cursor(0, { 9, 0 })
Tasks.toggle_fold()
Highlight._update()

assert(get_mark_text(9):find("%(%+3 lines%)"), "Line 9 must show (+3 lines)")
assert(get_mark_text(19):find("2/4"), "Line 19 must stay 2/4 (not truncated to 2/3)")
assert(get_mark_text(26):find("3/3"), "Line 26 must stay 3/3 (not disappear)")
assert(get_mark_text(32):find("1/4"), "Line 32 must stay 1/4 (not truncated to 1/1)")
assert(get_mark_text(43):find("1/4"), "Line 43 must stay 1/4 (not truncated to 1/1)")

-- Re-open Line 9
Tasks.toggle_fold()
Highlight._update()
assert(get_mark_text(19):find("2/4"), "Line 19 must stay 2/4 after re-opening line 9")
print("Multi-block stability: Line 19 (2/4), Line 26 (3/3), Line 32 (1/4), Line 43 (1/4) all maintained!")
print("\n✨ ALL FOLDING AND ARROW ROTATION TESTS PASSED SUCCESSFULLY ✨\n")
