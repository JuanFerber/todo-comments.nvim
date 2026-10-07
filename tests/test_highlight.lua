-- tests/test_highlight.lua
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

-- Run buffer highlight engine
require("todo-comments.highlight").highlight(buf, 0, vim.api.nvim_buf_line_count(buf))

local ns = require("todo-comments.config").ns
local marks = vim.api.nvim_buf_get_extmarks(buf, ns, { 0, 0 }, { -1, -1 }, { details = true })

print("\n==================== GENERATED EXTMARKS & VIRTUAL TEXT ====================")
local found_progress = false
for _, m in ipairs(marks) do
  local row = m[2] + 1
  local col = m[3]
  local details = m[4] or {}
  local hl = details.hl_group or "None"
  local vt = details.virt_text

  if vt then
    local vt_str = ""
    for _, chunk in ipairs(vt) do
      vt_str = vt_str .. string.format("[%s (%s)] ", chunk[1], chunk[2])
    end
    print(string.format("Line %2d (col %2d) -> VIRT_TEXT: %s", row, col, vt_str))
    if vt_str:find("TodoProgressRatio") then
      found_progress = true
    end
  elseif hl:find("TodoCheckbox") then
    print(string.format("Line %2d (col %2d-%2d) -> CHECKBOX HL: %s", row, col, details.end_col or col, hl))
  end
end
print("===========================================================================\n")

assert(found_progress, "Error: Progress ratio virtual text was not found")

-- Verify inline comment task highlights and virtual text on Line 74
local found_inline_checkbox = false
local found_inline_progress = false
for _, m in ipairs(marks) do
  local row = m[2] + 1
  local details = m[4] or {}
  local hl = details.hl_group or ""
  local vt = details.virt_text
  if row == 74 then
    if hl == "TodoCheckboxTodo" then
      found_inline_checkbox = true
    end
    if vt then
      for _, chunk in ipairs(vt) do
        if chunk[2] == "TodoProgressRatio" and chunk[1]:find("0/1") then
          found_inline_progress = true
        end
      end
    end
  end
end
assert(found_inline_checkbox, "Line 74 must have TodoCheckboxTodo highlight")
assert(found_inline_progress, "Line 74 must have TodoProgressRatio virtual text")

-- Verify signs
print("\n==================== PLACED SIGNS ====================")
local placed_signs = {}
local sign_list = vim.fn.sign_getplaced(buf, { group = "todo-signs" })
for _, s in ipairs((sign_list[1] and sign_list[1].signs) or {}) do
  placed_signs[s.lnum] = s.name
  print(string.format("Line %2d -> SIGN: %s", s.lnum, s.name))
end
print("======================================================\n")

-- Line 39 has a single-line task with checkbox [ ]: must have todo-sign-task-todo
assert(
  placed_signs[39] == "todo-sign-task-todo",
  "Line 39 must have task sign todo-sign-task-todo, found: " .. tostring(placed_signs[39])
)

-- Line 74 has an inline task with checkbox [ ]: must have todo-sign-task-todo
assert(
  placed_signs[74] == "todo-sign-task-todo",
  "Line 74 must have task sign todo-sign-task-todo, found: " .. tostring(placed_signs[74])
)

-- Line 80 is a single-line TODO without checkbox: must have todo-sign-TODO
assert(
  placed_signs[80] == "todo-sign-TODO",
  "Line 80 must have keyword sign todo-sign-TODO, found: " .. tostring(placed_signs[80])
)

print("✨ ALL STEP 2 HIGHLIGHT TESTS PASSED SUCCESSFULLY ✨\n")
