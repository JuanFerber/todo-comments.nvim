-- tests/test_tasks.lua
vim.cmd([[set runtimepath=$VIMRUNTIME]])
vim.opt.runtimepath:append(vim.fn.getcwd())
vim.opt.swapfile = false
vim.opt.termguicolors = true
vim.cmd([[syntax on]])

local todo = require("todo-comments")
todo.setup()

local buf = vim.api.nvim_create_buf(true, false)
vim.bo[buf].filetype = "lua"
vim.api.nvim_set_current_buf(buf)

-- Insert sample lines
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "-- TODO: Sample task block",
  "-- [ ] Step 1",
  "-- [/] Step 2",
  "-- [x] Step 3",
})

local Tasks = require("todo-comments.tasks")

print("\n--- TEST 1: Toggle from [ ] to [/] ---")
vim.api.nvim_win_set_cursor(0, { 2, 3 }) -- Line 2
Tasks.toggle()
local line2 = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
print("Result:", line2)
assert(line2:find("%[%/%]"), "Error: Expected [/]")

print("\n--- TEST 2: Toggle from [/] to [x] ---")
Tasks.toggle()
line2 = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
print("Result:", line2)
assert(line2:find("%[x%]"), "Error: Expected [x]")

print("\n--- TEST 3: Toggle from [x] to [ ] ---")
Tasks.toggle()
line2 = vim.api.nvim_buf_get_lines(buf, 1, 2, false)[1]
print("Result:", line2)
assert(line2:find("%[%s+%]"), "Error: Expected [ ]")

print("\n--- TEST 4: Comment Block Detection for Folding ---")
local block = Tasks.get_block_at(buf, 0)
print("Detected block:", vim.inspect(block))
assert(block and block.header_lnum == 0 and block.end_lnum == 3, "Error in block detection")

print("\n--- TEST 5: Toggle inline comment task [ ] -> [/] -> [x] -> [ ] ---")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "local a = 1 -- TODO: [ ] inline task",
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
Tasks.toggle()
local l_inline = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
print("Result:", l_inline)
assert(l_inline == "local a = 1 -- TODO: [/] inline task", "Expected [/], got: " .. tostring(l_inline))
Tasks.toggle()
l_inline = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
print("Result:", l_inline)
assert(l_inline == "local a = 1 -- TODO: [x] inline task", "Expected [x], got: " .. tostring(l_inline))
Tasks.toggle()
l_inline = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
print("Result:", l_inline)
assert(l_inline == "local a = 1 -- TODO: [ ] inline task", "Expected [ ], got: " .. tostring(l_inline))

print("\n--- TEST 6: Toggle header without checkbox (single space insertion) ---")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "-- TODO: foo",
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
Tasks.toggle()
local l_hdr = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
print("Result:", l_hdr)
assert(l_hdr == "-- TODO: [ ] foo", "Expected '-- TODO: [ ] foo' without double space, got: " .. tostring(l_hdr))

vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "-- TODO:foo",
})
vim.api.nvim_win_set_cursor(0, { 1, 0 })
Tasks.toggle()
local l_hdr2 = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1]
print("Result:", l_hdr2)
assert(l_hdr2 == "-- TODO: [ ] foo", "Expected '-- TODO: [ ] foo', got: " .. tostring(l_hdr2))

print("\n--- TEST 7: Block detection with inline header and shorter continuation lines ---")
vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
  "local a = 1 -- TODO: Inline header with long prefix",
  "-- [ ] subtask 1",
  "-- [x] subtask 2",
})
local inline_block = Tasks.get_block_at(buf, 0)
print("Detected inline block:", vim.inspect(inline_block))
assert(
  inline_block and inline_block.header_lnum == 0 and inline_block.end_lnum == 2,
  "Expected inline block to span lines 0 to 2, got: " .. vim.inspect(inline_block)
)
print("✨ ALL STEP 3 TASK TESTS PASSED SUCCESSFULLY ✨\n")
