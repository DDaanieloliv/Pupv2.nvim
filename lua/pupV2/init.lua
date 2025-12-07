--  ██████╗ ██████╗ ██╗   ██╗██████╗  ██████╗███████╗     ██████╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔═══██╗██║   ██║██╔══██╗██╔════╝██╔════╝    ██╔════╝██╔═══██╗██╔══██╗██╔════╝
-- ███████╗██║   ██║██║   ██║██████╔╝██║     █████╗      ██║     ██║   ██║██║  ██║█████╗
-- ╚════██║██║   ██║██║   ██║██╔══██╗██║     ██╔══╝      ██║     ██║   ██║██║  ██║██╔══╝
-- ███████║╚██████╔╝╚██████╔╝██║  ██║╚██████╗███████╗    ╚██████╗╚██████╔╝██████╔╝███████╗
-- ╚══════╝ ╚═════╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚══════╝     ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝


local M = {}


-- Default Configuration
local default_config = {
  enabled = true,
  cache_dir = vim.fn.stdpath("data") .. "/buffer_cache",
  grep_defaults = vim.fn.stdpath("data") .. "/buffer_cache",
  keymaps = {
    list_buffers = "<leader>ls",
    move_backward = "<leader>[",
    move_forward = "<leader>]",
    buffer_picker = "<leader>m",
    file_picker = "<leader>d",
    close_buffer = "<leader>q",
    clear_path = "<leader>x",
    remove_last = "<leader>r",
    pick_previous = "<leader>la",
    clear_cache = "<leader>cc"
  },
  ignore_patterns = {
    "TelescopePrompt", "TelescopeResults", "bufferlist", "neo%-tree", "NvimTree", "packer", "fugitive", "term://",
    "^no name"
  },
  style = {
    border           = 'rounded',
    background       = nil,
    cursor_line      = nil,
    border_color     = nil,
    title_color      = nil,
    color_symbol     = nil,
    match_highlight  = '#f3be7c',
    input_background = nil,
    input_text       = nil,
    prompt_symbol    = '',
    input_cursor     = '│ ',
    virt_text        = '>'
  },
  opt_feature = {
    buffers_trail = false
  }
}

M.config = vim.deepcopy(default_config)
local cache_file = nil
local ns_id = vim.api.nvim_create_namespace('PickBufferMatchHL')





------ Utility functios --------------------------------------------------------------------------------


--- Get the value of a specific buffer option.
--- @param bufnr integer Buffer number (ID)
--- @param option_name string Option name as we can se when ':set'
--- @return string|integer|boolean Option value
---
local function get_buf_option(bufnr, option_name)
  return vim.api.nvim_get_option_value(option_name, { buf = bufnr })
end




--- Find the buffer based on the path
--- @param path string Path realate to an buffer
--- @return integer | nil Return a List of buffer ids (ID) or nil
---
local function find_buffer_by_path(path)
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_get_name(buf) == path then
      return buf
    end
  end
  return nil
end



--- Check if the respective buffer is a valid buffer
--- @param buf integer  Buffer id (ID)
--- @return boolean Return true if the buffer name is diferent of "" and buftype == "" and filetype diferent of "" and the buf_name exists
---
---
local function is_valid_buffer(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local buftype = get_buf_option(buf, "buftype")
  local filetype = get_buf_option(buf, "filetype")
  return buf_name ~= "" and buftype == "" and filetype ~= nil and vim.fn.filereadable(buf_name) == 1
end



--- Check if the respective buffer is a buf related to a plugin
--- @param buf integer Buffer id, or 0 for current buffer
--- @return boolean True if one of these ignore_patterns
---
local function is_plugin_buffer(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  for _, pattern in ipairs(M.config.ignore_patterns) do
    if buf_name:match(pattern) then
      return true
    end
  end
  return false
end



--- Get the current path
--- @return string
---
local function get_current_path()
  return vim.fn.getcwd()
end




--- Check if buf is a telescope buffer
--- @return boolean
---
local function is_telescope_window()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_ft = get_buf_option(current_buf, "filetype")
  return current_ft == "TelescopePrompt"
end




--- Close every telescope window
--- Good for escape telescope windows with <leader>q
---
local function close_telescope_windows()
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    local buf = vim.api.nvim_win_get_buf(win)
    local ft = get_buf_option(buf, "filetype")
    if ft == "TelescopePrompt" or ft == "TelescopeResults" then
      pcall(vim.api.nvim_win_close, win, true)
    end
  end
end



--- Save the lau table
--- @param cache_data table<string, { name: string, path: string }[]> | {}
---
local function save_cache(cache_data)
  if not cache_file or cache_file == "" then
    vim.notify("Cache file path not set!", vim.log.levels.ERROR)
    return
  end

  --[[
  Open the cache_file and clean the content.
  ]]
  local file = io.open(cache_file, "w")
  if file then
    file:write("return " .. vim.inspect(cache_data))
    file:close()
  else
    vim.notify("Failed to open cache file: " .. cache_file, vim.log.levels.ERROR)
  end
end




--- Set the cache system by get the default cache_dir + cache file name
local function setup_cache()
  if vim.fn.isdirectory(M.config.cache_dir) == 0 then
    vim.fn.mkdir(M.config.cache_dir, "p")
  end
  cache_file = M.config.cache_dir .. "/buffers.lua"

  if vim.fn.filereadable(cache_file) == 0 then
    save_cache({})
  end
end










--- Load the cache file
--- @return table<string, { name: string, path: string }[]> | {}
---
local function load_cache()
  local ok, cache_data = pcall(dofile, cache_file)
  --[[ If ok == True @return cache_data or {} (empty table) in case of ok == False ]]
  return ok and cache_data or {}
end





--- Add the full  buffer name to your respectiv path on table cache_data
--- @param buf integer Buffer id, or 0 for current buffer
---
local function add_buffer_to_cache(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)
  if not is_valid_buffer(buf) then return end

  local current_path = get_current_path()
  local cache_data = load_cache()
  --[[
  Initialize a table to 'current_path', it create a empty table
  ]]
  cache_data[current_path] = cache_data[current_path] or {}

  local exists = false
  for _, item in ipairs(cache_data[current_path]) do
    if item.path == buf_name then
      exists = true
      break
    end
  end

  if not exists then
    --[[
    table.insert({table}, [{pos},] {value}), default {pos} >> n+1 >> where n = table.length
    ]]
    table.insert(cache_data[current_path], {     -- In Lua array are 1-based intead 0-based
      name = vim.fn.fnamemodify(buf_name, ":t"), -- :t >> tail >> last part of the path >> buffer name
      path = buf_name,
    })
    save_cache(cache_data)
  end
end



--- Check if a file path exists on the filesystem
--- @param file_path string The file path to check
--- @return boolean True if the file exists and is readable and not directory
---
local function is_existing_file(file_path)
  if type(file_path) ~= "string" or file_path == "" then
    return false
  end

  return vim.fn.filereadable(file_path) == 1 and vim.fn.isdirectory(file_path) == 0
end



--[[
Create a new Lua table 'result' to 'cache_data[current_path]' adding a number to each buffer and a status
It is what we see when open the float windown to navigate through the buffers
]]
--- @return table<integer, { number: integer, name: string, path: string, is_open: string}>
---
local function get_buffers_with_numbers()
  local current_path = get_current_path()
  local cache_data = load_cache()
  local buffers = cache_data[current_path] or {}

  local result = {}
  for i, item in ipairs(buffers) do
    table.insert(result, {
      number = i,
      name = item.name,
      path = item.path,
      is_open = find_buffer_by_path(item.path) ~= nil
    })
  end
  return result
end



function M.cleanup_nonexistent_buffers()
  local buffers = get_buffers_with_numbers()
  local valid_buffers = {}

  for _, buf in ipairs(buffers) do
    if buf then
      table.insert(valid_buffers, {
        name = buf.name,
        path = buf.path
      })
    end
  end

  -- Only save the valid buffers
  local current_path = get_current_path()
  local cache_data = load_cache()
  cache_data[current_path] = valid_buffers
  save_cache(cache_data)
end

--- Remove one buffer from cache.
--- @param path string Absolute path to remove buffer
--- @param force boolean|nil If true, force the removal even though it is the last buffer
--- @return boolean  Success or failure
---
local function remove_buffer_from_cache(path, force)
  local current_path = get_current_path()
  local cache_data = load_cache()

  if not cache_data[current_path] then
    return false
  end

  for i, item in ipairs(cache_data[current_path]) do
    if item.path == path then
      if #cache_data[current_path] == 1 and not force then
        vim.notify("Cannot remove the last buffer of the current path!", vim.log.levels.WARN)
        return false
      end

      table.remove(cache_data[current_path], i)
      save_cache(cache_data)
      return true
    end
  end
  return false
end





--- Loads cache_data, looks for last_buffer to remove it, unless it is the current buffer
---
local function remove_last_buffer_from_cache()
  local current_path = get_current_path()
  local current_buf_name = vim.api.nvim_buf_get_name(0)
  local cache_data = load_cache()

  if not cache_data[current_path] or #cache_data[current_path] == 0 then
    vim.notify("No buffers to remove on this path!", vim.log.levels.WARN)
    return
  end

  local last_buffer = cache_data[current_path][#cache_data[current_path]]
  if last_buffer.path == current_buf_name then
    vim.notify("Unsuccessful removal due to the last buffer being your current buffer", vim.log.levels.WARN)
    return
  end

  local buf_to_close = find_buffer_by_path(last_buffer.path)
  table.remove(cache_data[current_path])
  save_cache(cache_data)

  if buf_to_close and buf_to_close ~= vim.api.nvim_get_current_buf() then
    vim.api.nvim_buf_delete(buf_to_close, { force = true })
    vim.notify("Last buffer closed and removed from cache", vim.log.levels.INFO)
  else
    vim.notify("Last buffer removed from cache", vim.log.levels.INFO)
  end
end





--- Checke every path in 'cache_data table<string, { name: string, path: string }[]'
--- delete all register saving the "modified" buffers
---
local function clear_cache()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = get_current_path()
  local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
  -- [[ 'cache_data table<string, { name: string, path: string }[]' ]]
  local cache_data = load_cache()

  --[[
  For each path in cache_data, we check if each of the respective
  buffers is the current buffer, if it is not the current buffer, we remove each of them
  ]]
  for path, buffers in pairs(cache_data) do
    if path ~= current_path then
      for _, item in ipairs(buffers) do
        local buf = find_buffer_by_path(item.path)
        if buf and buf ~= current_buf then
          if get_buf_option(buf, "modified") then
            vim.api.nvim_buf_call(buf, function()
              vim.cmd("w")
            end)
          end
          vim.api.nvim_buf_delete(buf, { force = true })
        end
      end
    end
  end

  if cache_data[current_path] then
    for _, item in ipairs(cache_data[current_path]) do
      local buf = find_buffer_by_path(item.path)
      if buf and buf ~= current_buf then
        if get_buf_option(buf, "modified") then
          vim.api.nvim_buf_call(buf, function()
            vim.cmd("w")
          end)
        end
        vim.api.nvim_buf_delete(buf, { force = true })
      end
    end
  end

  --[[
  Create a new table<string { name: string, path: string }[]> with only the current_buf_name
  to the current_path and in case of the current buf name is "" and if is valid_buffer
  ]]
  local new_cache = {}
  if current_buf_name ~= "" and is_valid_buffer(current_buf) then
    new_cache[current_path] = {
      {
        name = vim.fn.fnamemodify(current_buf_name, ":t"),
        path = current_buf_name,
      },
    }
  end

  save_cache(new_cache)
  vim.notify("Cache clean! Only the current buffer was kept.", vim.log.levels.INFO)
end





--- "Clear the current_path" >> Create a new cache_data with buffers related to current_path erased
---
local function clear_current_path_buffers()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = get_current_path()
  local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
  local cache_data = load_cache()

  local new_cache = {}
  for path, buffers in pairs(cache_data) do
    if path ~= current_path then
      new_cache[path] = buffers
    end
  end

  --[[
  Check if the current_path exists in cache_data, check if each item in current_path exists and if is a current_buf
  and if it is a valid, if true make a insert on 'new_cache[current_path]' the tail name of the current_buf
  and the full_path, if false it save the buffer and close it
  ]]
  if cache_data[current_path] then
    new_cache[current_path] = {}
    for _, item in ipairs(cache_data[current_path]) do
      local buf = find_buffer_by_path(item.path)
      if buf then
        if buf == current_buf then
          if is_valid_buffer(current_buf) then
            table.insert(new_cache[current_path], {
              name = vim.fn.fnamemodify(current_buf_name, ":t"),
              path = current_buf_name,
            })
          end
        else
          if get_buf_option(buf, "modified") then
            local ok, err = pcall(vim.api.nvim_buf_call, buf, function()
              vim.cmd("silent w!")
            end)
            if not ok then
              vim.notify("Error when saving " .. item.path .. ": " .. err, vim.log.levels.ERROR)
            end
          end
          pcall(vim.api.nvim_buf_delete, buf, { force = true })
        end
      end
    end
  end

  save_cache(new_cache)
  pcall(vim.api.nvim_command, "silent! call clearmatches()")
  pcall(vim.api.nvim_command, "silent! call histdel('/', -1)")
  vim.notify("Current path buffers have been saved and closed", vim.log.levels.INFO)
end





--- Based on the index obtained from the buffer in the respective path we add
--- its position + 1 if it is not the buffer of the last position
---
local function move_buffer_forward()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = get_current_path()
  local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
  local cache_data = load_cache()

  if not cache_data[current_path] or #cache_data[current_path] < 2 then
    vim.notify("There are not enough buffers to move", vim.log.levels.WARN)
    return
  end

  local current_index = nil
  for i, item in ipairs(cache_data[current_path]) do
    if item.path == current_buf_name then
      current_index = i
      break
    end
  end

  if not current_index or current_index == #cache_data[current_path] then
    vim.notify("Buffer already in last position", vim.log.levels.INFO)
    return
  end

  cache_data[current_path][current_index], cache_data[current_path][current_index + 1] =
      cache_data[current_path][current_index + 1], cache_data[current_path][current_index]

  save_cache(cache_data)
  vim.notify(string.format("Buffer moved to position %d", current_index + 1), vim.log.levels.INFO)
end







--- Based on the index obtained from the buffer in the respective path we add
--- its position - 1 if it is not the buffer of the last position
---
local function move_buffer_backward()
  local current_buf = vim.api.nvim_get_current_buf()
  local current_path = get_current_path()
  local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
  local cache_data = load_cache()

  if not cache_data[current_path] or #cache_data[current_path] < 2 then
    vim.notify("There are not enough buffers to move", vim.log.levels.WARN)
    return
  end

  local current_index = nil
  for i, item in ipairs(cache_data[current_path]) do
    if item.path == current_buf_name then
      current_index = i
      break
    end
  end

  if not current_index or current_index == 1 then
    vim.notify("Buffer already on first position", vim.log.levels.INFO)
    return
  end

  cache_data[current_path][current_index], cache_data[current_path][current_index - 1] =
      cache_data[current_path][current_index - 1], cache_data[current_path][current_index]

  save_cache(cache_data)
  vim.notify(string.format("Buffer moved to position %d", current_index - 1), vim.log.levels.INFO)
end





--- Function to truncate the path with replacement of the home directory
--- comment
--- @param path string Respective path
--- @param max_width integer Total caracteres allowed
--- @return unknown
---
local function truncate_path(path, max_width)
  local filename = vim.fn.fnamemodify(path, ":t")
  local dir_path = vim.fn.fnamemodify(path, ":h")

  --- Somehow it push to home_dir var it '$HOME'
  local home_dir = vim.fn.expand("~")

  --- Checks if the subString of 'dir_path' that starts from the first characters
  --- to the characters defined by #home_dir( size string) it means that we check
  --- if 'home_dir' string are in 'dir_path'
  if dir_path:sub(1, #home_dir) == home_dir then
    -- dir_path = "~" .. dir_path:sub(#home_dir + 1)
    dir_path = dir_path:sub(#home_dir + 2) -- We change dir_path to start from the #home_dir(string size) + 2° characters after
  end

  if dir_path == "" or dir_path == "." then
    return filename
  end

  -- If the full path fits, return normal
  local full_path = dir_path .. "/" .. filename
  if #full_path <= max_width then
    return full_path
  end

  -- If the filename alone is already greater than the maximum, we truncate the filename
  if #filename >= max_width then
    return "…" .. filename:sub(-max_width + 1)
  end

  -- Calculates available space for the directory
  local available_width = max_width - #filename - 1 -- -1 for the separator

  -- If the directory is too long, we truncate it with an ellipsis in the middle.
  if #dir_path > available_width then
    local part_size = math.floor(available_width / 2) - 1
    local first_part = dir_path:sub(1, part_size)
    local last_part = dir_path:sub(-part_size)
    return first_part .. "…" .. last_part .. "/" .. filename
  end

  return dir_path .. "/" .. filename
end



local function count_line_buffers(buffers)
  local num_lines = 0
  if buffers then
    for i, _ in ipairs(buffers) do
      num_lines = i
    end
  end
  return num_lines
end



local function save_rg_config()
  local grep_defaults_dir = M.config.grep_defaults
  local rgignore_file = grep_defaults_dir .. "/.rgignore"

  local file = io.open(rgignore_file, "w")
  if file then
    file:write("!.config\n")
    file:write("!.local\n")
    file:write("!.shell\n")
    file:close()
    return true
  else
    vim.notify("Failed to open rg_config file: " .. rgignore_file, vim.log.levels.ERROR)
    return false
  end
end


local function setup_rg_defaults()
  local grep_defaults_dir = M.config.grep_defaults

  if vim.fn.isdirectory(grep_defaults_dir) == 0 then
    vim.fn.mkdir(grep_defaults_dir, "p")
  end

  local rgignore_file = grep_defaults_dir .. "/.rgignore"

  if vim.fn.filereadable(rgignore_file) == 0 then
    local file = io.open(rgignore_file, "w")
    if file then
      file:write("!.config\n")
      file:write("!.local\n")
      file:write("!.shell\n")
      file:close()
      vim.notify("Created rgignore file: " .. rgignore_file, vim.log.levels.INFO)
    else
      vim.notify("Failed to create rgignore file: " .. rgignore_file, vim.log.levels.ERROR)
    end
  end

  return rgignore_file
end

---------------------------------------------------------------------------------------------------------







------ M.table functios ---------------------------------------------------------------------------------


M.current_query = {}
M.flag_confirmation = nil


--- Based on the argument received(String) we searches for that string which is a number and shoud
--- match with one of thoses completions otherwise it return {} based on the return made by
--- 'get_buffers_with_numbers()']
--- @param arg_lead string Aragument type by the user
--- @return table<integer, string, string> | {} Return a buffer table with these numbered completions
---
-- function M.buffer_completion(arg_lead, cmd_line, cursor_pos)
function M.buffer_completion(arg_lead, _, _)
  local completions = {}
  local buffers = get_buffers_with_numbers()

  for _, buf in ipairs(buffers) do
    -- Shorten the path to show only the last 2-3 folders
    local short_path = vim.fn.fnamemodify(buf.path, ":~:")
    local completion_item = string.format("%d: %s", buf.number, short_path)
    table.insert(completions, completion_item)
  end

  if arg_lead ~= "" then
    return vim.tbl_filter(function(item)
      return item:lower():match('^' .. arg_lead:lower())
    end, completions)
  end

  return completions
end

--- Based on the @param, we check the table buffers
--- (table<integer, { number: integer, name: string, path: string, is_open: boolean }>)
--- and if any buffer matches, we switch to it.
--- @param args string | table<integer, { args: string }>
---
function M.buffer_command(args)
  -- Check if args is a string (when called via command)
  if type(args) == "string" then
    args = { args = args }
  end
  args = args or {}
  local target_arg = args.args or ""

  if target_arg == "" then
    M.pick_buffer_cache()
    return
  end

  --[[ table<integer, { number: integer, name: string, path: string, is_open: boolean }> ]]
  local buffers = get_buffers_with_numbers()


  local target = target_arg
  local num = tonumber(target)
  local found_buffer = nil

  --- If tonumber Return a number we checks if that number is equivalent to a index on this table
  --- table<integer, {number: integer, name: string, path: string, is_open: boolean}>
  ---
  if num and buffers[num] then
    found_buffer = buffers[num]
  else
    local number_part = target:match("^(%d+):")
    if number_part then
      num = tonumber(number_part)
      if num and buffers[num] then
        found_buffer = buffers[num]
      end
    else
      for _, buf in ipairs(buffers) do
        if target == buf.name then
          found_buffer = buf
          break
        end
      end
    end
  end

  if found_buffer then
    if vim.fn.filereadable(found_buffer.path) == 1 then
      local existing_buf = find_buffer_by_path(found_buffer.path)
      if existing_buf then
        vim.cmd('buffer ' .. existing_buf)
      else
        vim.cmd('edit ' .. vim.fn.fnameescape(found_buffer.path))
      end
    else
      vim.notify("File Not found: " .. found_buffer.path, vim.log.levels.ERROR)
      remove_buffer_from_cache(found_buffer.path, true)
    end
  else
    vim.notify("Buffer not found: " .. target, vim.log.levels.WARN)
  end
end

--- @param file_path string
--- @return boolean return true if that action is succeeds
---
function M.select_file(file_path)
  if not file_path or file_path == "" then
    vim.notify("File path is empty", vim.log.levels.WARN)
    return false
  end

  -- Verify if the file exists
  if vim.fn.filereadable(file_path) == 0 then
    vim.notify("File does not exist: " .. file_path, vim.log.levels.ERROR)
    return false
  end

  -- Open the file
  vim.cmd("edit " .. vim.fn.fnameescape(file_path))
  return true
end

--- @return table<integer, { number: integer, name: string, path: string, is_open: string }>
--- This table contains all buffers in cache that match whit the query_stack(M.current_query)
---
function M.updated_buffers_by_query()
  local buffers = get_buffers_with_numbers()
  local filtered_buffers = buffers
  local temp = {}

  for _, term in ipairs(M.current_query) do
    temp = {}
    for _, buf_item in ipairs(filtered_buffers) do
      if is_existing_file(buf_item.path) and
          (buf_item.name:lower():find(term, 1, true) or
            buf_item.path:lower():find(term, 1, true)) then
        table.insert(temp, buf_item)
      end
    end
    filtered_buffers = temp
  end
  return filtered_buffers
end

--- @param win integer Window (ID)
--- @param buf integer Buffer (ID)
--- Define each setting to the respective window and buffer
---
function M.config_window_buffer(win, buf)
  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'bufferlist', { buf = buf })
  ---
  vim.api.nvim_set_option_value('number', true, { win = win })
  vim.api.nvim_set_option_value('numberwidth', 1, { win = win })
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  vim.api.nvim_set_option_value('cursorlineopt', 'line', { win = win })
  vim.api.nvim_set_option_value('winhighlight', 'CursorLine:PmenuSel', { win = win })
end

--- @param style table
--- Defines the highlights to each namespace, using the defaults if some colors
--- in present in plugin config
---
function M.setting_config_style(style)
  -- Input text
  if style.input_text then
    vim.cmd(string.format("highlight InputText guifg=%s", style.input_text))
    if style.input_background then
      vim.cmd(string.format("highlight InputText guibg=%s", style.input_background))
    end
  else
    vim.cmd([[
      if !hlexists('InputText')
        highlight default link InputText ModeMsg
      endif
      if !hlexists('ModeMsg')
        highlight default link InputText Normal
      endif
    ]])
  end

  -- Cursor line
  if style.cursor_line then
    vim.cmd(string.format("highlight FloatCursorLine guibg=%s", style.cursor_line))
  else
    vim.cmd([[
      if !hlexists('FloatCursorLine')
        highlight default link FloatCursorLine PmenuSel
      endif
      if !hlexists('PmenuSel')
        highlight default link FloatCursorLine Visual
      endif
    ]])
  end

  -- Prompt symbol
  if style.color_symbol then
    vim.cmd(string.format("highlight PromptSymbol guifg=%s", style.color_symbol))
  else
    vim.cmd([[
      if !hlexists('PromptSymbol')
        highlight default link PromptSymbol Identifier
      endif
      if !hlexists('Identifier')
        highlight default link PromptSymbol Special
      endif
    ]])
  end

  -- Match highlight
  if style.match_highlight then
    vim.cmd(string.format("highlight PickBufferMatch guifg=%s gui=bold", style.match_highlight))
  else
    vim.cmd("highlight default link PickBufferMatch Search")
  end

  -- Titles
  if style.title_color then
    vim.cmd(string.format("highlight FloatTitle guifg=%s", style.title_color))
    vim.cmd(string.format("highlight FloatFooter guifg=%s", style.title_color))
  else
    vim.cmd([[
      if !hlexists('FloatTitle')
        highlight default link FloatTitle Title
      endif
      if !hlexists('Title')
        highlight default link FloatTitle Special
      endif
    ]])
    vim.cmd("highlight default link FloatFooter Comment")
  end

  -- Border
  if style.border_color then
    vim.cmd(string.format("highlight FloatBorder guifg=%s", style.border_color))
    if style.background then
      vim.cmd(string.format("highlight FloatBorder guibg=%s", style.background))
    end
  else
    vim.cmd([[
      if !hlexists('FloatBorder')
        highlight default link FloatBorder Normal
      endif
    ]])
  end

  -- Background
  if style.background then
    vim.cmd(string.format("highlight NormalFloat guibg=%s", style.background))
    -- Aplicar background também ao border e prompt se não tiverem cores específicas
    if not style.border_color then
      vim.cmd(string.format("highlight FloatBorder guibg=%s", style.background))
    end
    if not style.color_symbol then
      vim.cmd(string.format("highlight PromptSymbol guibg=%s", style.background))
    end
  else
    vim.cmd([[
      if !hlexists('NormalFloat')
        highlight default link NormalFloat Pmenu
      endif
      if !hlexists('Pmenu')
        highlight default link NormalFloat Normal
      endif
    ]])
  end

  -- BufferPickerIndicator (sempre com fallback)
  vim.cmd([[
    if !hlexists('BufferPickerIndicator')
      highlight default BufferPickerIndicator guifg=#aeaed1 guibg=NONE
    endif
  ]])
end

--- grep all files in the current path
--- @return table<integer, { number: integer, name: string, path: string, is_open: string}>
---
function M.grep_files()
  if M.filesys_allowed then
    local files = M.file_system_cache
    return files
  end

  M.filesys_allowed = not M.filesys_allowed

  local path = vim.fn.getcwd()
  local grep_config = M.config.grep_defaults .. "/.rgignore"

  if vim.fn.filereadable(grep_config) == 0 then
    vim.notify("rgignore not found, creating...", vim.log.levels.INFO)
    save_rg_config()
  end

  local command = string.format('rg --files --ignore-file %s %s', grep_config, path)

  local handle = io.popen(command)
  if not handle then
    vim.notify("The grep_files command faild", vim.log.levels.WARN)
    return {}
  end
  local result = handle:read("*a")
  handle:close()

  local files = {}
  local index = 1
  for line in result:gmatch("[^\r\n]+") do
    table.insert(files, {
      number = index,
      name = line:match("([^/]+)$"),
      path = line,
      is_open = find_buffer_by_path(line) ~= nil
    })
    index = index + 1
  end
  return files
end

-- local path = vim.fn.getcwd()
-- local grep_config = M.config.grep_defaults .. "/.rgignore"
-- vim.system({ 'rg', '--files', '--ignore-file', grep_config, path }, {
--   text = true
-- }, function(result)
--
--   local files = {}
--   local index = 1
--   for line in result.stdout:gmatch("[^\r\n]+") do
--     table.insert(files, {
--       number = index,
--       name = line:match("([^/]+)$"),
--       path = line,
--       is_open = nil
--     })
--     index = index + 1
--   end
--   -- return files
--
--   vim.schedule(function()
--       M.file_system_cache = files
--   end)
-- end)


M.file_system_cache = nil
M.filesys_allowed = true

local function find_files_promise()
  return function(resolve, reject)
    local path = vim.fn.getcwd()
    local grep_config = M.config.grep_defaults .. "/.rgignore"
    local job = vim.system({ 'rg', '--files', '--ignore-file', grep_config, path }, {
      text = true
    }, function(result)
      vim.schedule(function()
        if result.code == 0 then
          local files = {}
          local index = 1
          for line in result.stdout:gmatch("[^\r\n]+") do
            table.insert(files, {
              number = index,
              name = line:match("([^/]+)$"),
              path = line,
              is_open = nil
            })
            index = index + 1
          end
          resolve(files)
        else
          reject("Falha: " .. (result.stderr or "erro desconhecido"))
        end
      end)
    end)
  end
end

local promise = find_files_promise()
promise(function(files)
  M.file_system_cache = files
  -- vim.notify("Ready: " .. #files .. " files...", vim.log.levels.WARN)
end, function(erro)
  vim.notify("Error: " .. erro, vim.log.levels.WARN)
end)

function M.setup_cache_file_system()
  local promise = find_files_promise()
  promise(function(files)
    M.file_system_cache = files
    -- vim.notify("Ready: " .. #files .. " files...", vim.log.levels.WARN)
  end, function(erro)
    vim.notify("Error: " .. erro, vim.log.levels.WARN)
  end)
end

--- Open a float window hith all files in the current path
---
function M.pick_files_system()
  local MAX_DISPLAY = 999
  local displayed_count = 0

  local style = M.config.style
  local query = {}

  -- should be async
  local buffers = M.grep_files()
  local search_term
  local selected_index = 1
  local filtered_buffers = buffers
  local num_lines = count_line_buffers(buffers)

  local width = 70
  local height = math.min(22, num_lines + 15)
  local row = vim.o.lines - height - 1
  local col = 0

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = {
      { style.prompt_symbol,                              "PromptSymbol" },
      { " " .. table.concat(query) .. style.input_cursor, "InputText" }
    },
    title_pos = "left",
    footer = {
      { " FILES ", "FloatFooter" }
    },
    footer_pos = "left",
  })

  vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
  vim.api.nvim_set_option_value('filetype', 'bufferlist', { buf = buf })
  vim.api.nvim_set_option_value('number', false, { win = win })
  vim.api.nvim_set_option_value('cursorline', true, { win = win })
  vim.api.nvim_set_option_value('cursorlineopt', 'line', { win = win })
  vim.api.nvim_set_option_value('winhighlight', 'CursorLine:PmenuSel', { win = win })

  M.setting_config_style(style)
  local indicator_ns = vim.api.nvim_create_namespace("buffer_picker_indicator")

  ---- Function that deal with text input -------------------------------------------------------------
  local function update_display()
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })

    -- Update the title
    vim.api.nvim_win_set_config(win, {
      title = {
        { style.prompt_symbol,                              "PromptSymbol" },
        { " " .. table.concat(query) .. style.input_cursor, "InputText" }
      },
      footer = { { " FILES " } }
    })

    if #query > 0 then
      search_term = table.concat(query):lower()
      filtered_buffers = {}
      for _, buf_item in ipairs(buffers) do
        if buf_item.name:lower():find(search_term, 1, true) or
            buf_item.path:lower():find(search_term, 1, true) then
          table.insert(filtered_buffers, buf_item)
        end
      end
    else
      filtered_buffers = buffers -- Show all buffers when no search term
    end

    local display_buffers = {}
    displayed_count = 0

    for i, buf_item in ipairs(filtered_buffers) do
      if i <= MAX_DISPLAY then
        table.insert(display_buffers, buf_item)
        displayed_count = displayed_count + 1
      else
        break
      end
    end

    local lines = {}
    -- In first interaction 'filtered_buffers' is a table with all buffers related to the current_path
    for _, buf_item in ipairs(display_buffers) do
      local status = buf_item.is_open and "" or ""
      -- Uses truncate_path to ensure the file name is visible
      local truncated_path = truncate_path(buf_item.path, 69) -- Fit within window width

      local indicator = "  "
      local line = string.format("%s%s%s", indicator, status, truncated_path)
      table.insert(lines, line)
    end

    local total_count = #filtered_buffers
    if total_count > MAX_DISPLAY then
      table.insert(lines, string.format("... and %d more buffers (type to filter)", total_count - MAX_DISPLAY))
    end

    -- Relace the lines on the buffer with the lines of an array
    -- So with that we change the buffer displyed on the window, to show the buffes in table 'lines'
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Lock the buffer edition for safety
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
    vim.api.nvim_buf_clear_namespace(buf, indicator_ns, 0, -1)

    if #display_buffers > 0 and selected_index <= #display_buffers then
      vim.api.nvim_buf_set_extmark(
        buf,
        indicator_ns,
        selected_index - 1,
        0,
        {
          virt_text = { { style.virt_text, "BufferPickerIndicator" } },
          virt_text_pos = "overlay",
          virt_text_win_col = 0,
          priority = 10000,
          strict = false,
        }
      )
    end


    if #query > 0 then
      local search_lower = table.concat(query):lower()
      --- We go through each of the lines in filtered_buffers
      for i, _ in ipairs(display_buffers) do
        local line_text = lines[i]
        local line_lower = line_text:lower()

        local start_pos = 1
        while true do
          local match_start, match_end = line_lower:find(search_lower, start_pos, true)
          if not match_start then break end
          --- Apply to some range of text related to the buffer, the highlight group
          vim.hl.range(
            buf,
            ns_id,
            'PickBufferMatch',
            { i - 1, match_start - 1 },
            { i - 1, match_end },
            { inclusive = false }
          )
          start_pos = match_end + 1
        end
      end
    end

    -- Move the cursor to the selected item
    vim.api.nvim_win_set_cursor(win, { selected_index, 0 })
    -- Refresh the buffer or window with all the new settings like selected_index highlight and etc...
    vim.cmd("redraw")
  end
  -----------------------------------------------------------------------------------------------------


  -- Call update_display after we create it
  update_display()

  -- Main Loop
  while true do
    local ok, char_str = pcall(vim.fn.getcharstr)
    if not ok then break end
    if #char_str == 4 then
      local byte1, byte2, byte3, byte4 = char_str:byte(1), char_str:byte(2), char_str:byte(3), char_str:byte(4)
      -- Exactly default: <80><fc>^H[1-9]
      if byte1 == 128 and byte2 == 252 and byte3 == 8 and byte4 >= 49 and byte4 <= 57 then
        local ctrl_number = byte4 - 48 -- Convert ASCII to number (49->1, 50->2, etc.)
        vim.schedule(function()
          if ctrl_number <= #filtered_buffers then
            M.select_file(filtered_buffers[ctrl_number].path)
          end
        end)
        break
      end
    end

    -- Detect backspaces (all variants)
    local is_backspace = char_str == '\8' or char_str == '\127' or char_str:find("kb") or char_str:find("<80>")
    -- Check keys by their string representation
    if char_str == '\12' then -- Ctrl+l (form feed)
      vim.schedule(function()
        if #filtered_buffers > 0 then
          M.select_file(filtered_buffers[selected_index].path)
        end
      end)
      break
    elseif char_str == '#' then
      -- update_display()

      vim.api.nvim_win_close(win, true)
      vim.schedule(function()
        M.pick_buffer_cache()
      end)
      return

      -- elseif char_str == 'O' then
      --   vim.schedule(function()
      --     if #filtered_buffers > 0 then
      --       M.select_file(filtered_buffers[selected_index].path)
      --     end
      --   end)
      --   break
      -- elseif char_str == '#' then
      --   update_display()
      -- elseif char_str == 'J' then -- J
      --   selected_index = math.min(#filtered_buffers, selected_index + 1)
      --   update_display()
      -- elseif char_str == 'K' then -- K
      --   selected_index = math.max(1, selected_index - 1)
      --   update_display()
      -- elseif char_str == '\10' then -- Ctrl+j (line feed)
      --   selected_index = math.min(#filtered_buffers, selected_index + 1)
      --   update_display()
      -- elseif char_str == '\11' then -- Ctrl+k (vertical tab)
      --   selected_index = math.max(1, selected_index - 1)
      --   update_display()
    elseif char_str == '\14' then -- Ctrl+n (shift out)
      selected_index = math.min(#filtered_buffers, selected_index + 1)
      update_display()
    elseif char_str == '\16' then -- Ctrl+p (data link escape)
      selected_index = math.max(1, selected_index - 1)
      update_display()
    elseif char_str == '\9' then -- TAB
      selected_index = (selected_index % #filtered_buffers) + 1
      update_display()
      -- elseif tonumber(char_str) then -- Numbers 0-9
      --   local num = tonumber(char_str)
      --   if num <= #filtered_buffers then
      --     selected_index = num
      --     update_display()
      --   end
    elseif char_str == '\27' then -- Escape
      break
    elseif char_str == '\13' then -- Enter
      vim.schedule(function()
        if #filtered_buffers > 0 then
          M.select_file(filtered_buffers[selected_index].path)
        end
      end)
      break
    elseif is_backspace then
      if #query > 0 then
        table.remove(query)
        selected_index = 1
        update_display()
      elseif #query == 0 then
        M.filesys_allowed = not M.filesys_allowed
        buffers = M.grep_files()
        M.file_system_cache = buffers
        update_display()
      end
      -- Search characters i.e. that character typed only will be add to 'query'
      -- if the characters size was equas to 1 and if it was a character that is NOT a white space
    elseif #char_str == 1 and char_str:match('%S') then
      table.insert(query, char_str)
      selected_index = 1
      update_display()
    end
  end

  --- When some action like entry on a buffer was called by some keybindings the main loop ends and
  --- we execute the command to close the window
  vim.api.nvim_win_close(win, true)
  M._float_win = win
end

--- Lounch a window tha shows all buffers related to the current_path
function M.pick_buffer_cache()
  ---- Setting window configs ------------------------------------------------------------
  local style = M.config.style
  local query = {}
  local buffers = get_buffers_with_numbers()
  local search_term
  local selected_index = 1
  local filtered_buffers = buffers
  local num_lines = count_line_buffers(buffers)


  local width = 75
  local height = math.min(22, num_lines + 15) -- Dynamic height based on number of buffers
  local row = vim.o.lines - height - 1        -- close to 40 lines
  local col = 0

  local buf = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = 'editor',
    width = width,
    height = height,
    row = row,
    col = col,
    style = 'minimal',
    border = 'rounded',
    title = {
      { style.prompt_symbol,                              "PromptSymbol" },
      { " " .. table.concat(query) .. style.input_cursor, "InputText" }
    },
    title_pos = "left",
    footer = {
      { " Buffers ", "FloatFooter" },
    },
    footer_pos = "left",
  })

  M.config_window_buffer(win, buf)
  M.setting_config_style(style)

  -----------------------------------------------------------------------------------------------------


  ---- Function that deal with text input -------------------------------------------------------------
  local function update_display()
    vim.api.nvim_set_option_value('modifiable', true, { buf = buf })

    -- Update the title
    vim.api.nvim_win_set_config(win, {
      title = {
        { style.prompt_symbol,                              "PromptSymbol" },
        { " " .. table.concat(query) .. style.input_cursor, "InputText" }
      },
      footer = { { " BUFFERS " } }
    })

    if M.flag_confirmation and M.current_query ~= nil then
      if M.current_query ~= {} then
        local buffers_to_search = M.updated_buffers_by_query()
        if #query > 0 then
          search_term = table.concat(query):lower()
        end
        if #query == 0 then
          filtered_buffers = M.updated_buffers_by_query()
        end
        if search_term ~= nil then
          filtered_buffers = {}
          for _, buf_item in ipairs(buffers_to_search) do
            if buf_item.name:lower():find(search_term, 1, true) or
                buf_item.path:lower():find(search_term, 1, true) then
              table.insert(filtered_buffers, buf_item)
            end
          end
        end
      end
    else
      -- Based on the content on table query we filter the table 'buffers'
      -- Creating a new table 'filtered_buffers' tha are displyed later according to what we type
      if #query > 0 then
        search_term = table.concat(query):lower()
        filtered_buffers = {}
        for _, buf_item in ipairs(buffers) do
          if buf_item.name:lower():find(search_term, 1, true) or
              buf_item.path:lower():find(search_term, 1, true) then
            table.insert(filtered_buffers, buf_item)
          end
        end
      else
        filtered_buffers = buffers -- Show all buffers when no search term
      end
    end

    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

    -- Updates content with truncated paths
    local lines = {}
    for _, buf_item in ipairs(filtered_buffers) do
      -- local status = buf_item.is_open and " " or "🖹"
      local status = buf_item.is_open and "🖹" or "🖹"
      -- Uses truncate_path to ensure the file name is visible
      local truncated_path = truncate_path(buf_item.path, 69) -- Fit within window width

      local line = string.format("%s%s", status, truncated_path)
      table.insert(lines, line)
    end
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

    -- Lock the buffer edition for safety
    vim.api.nvim_set_option_value('modifiable', false, { buf = buf })


    -- Apply highlight to matches
    if #query > 0 then
      local search_lower = table.concat(query):lower()
      --- We go through each of the lines in filtered_buffers
      for i, _ in ipairs(filtered_buffers) do
        local line_text = lines[i]
        local line_lower = line_text:lower()

        local start_pos = 1
        while true do
          local match_start, match_end = line_lower:find(search_lower, start_pos, true)
          if not match_start then break end
          --- Apply to some range of text related to the buffer, the highlight group
          vim.hl.range(
            buf,
            ns_id,
            'PickBufferMatch',
            { i - 1, match_start - 1 },
            { i - 1, match_end },
            { inclusive = false }
          )
          start_pos = match_end + 1
        end
      end
    end
    -- Move the cursor to the selected item
    vim.api.nvim_win_set_cursor(win, { selected_index, 0 })
    -- Refresh the buffer or window with all the new settings like selected_index highlight and etc...
    vim.cmd("redraw")
  end
  -----------------------------------------------------------------------------------------------------



  -- Call update_display after we create it
  update_display()


  -- Main Loop
  while true do
    local ok, char_str = pcall(vim.fn.getcharstr)
    if not ok then break end
    -- Detect Alt+Number (special keys)
    -- That logical block will catch every char Array that are sent by 'vim.fn.getcharstr'
    -- and process each BYTE seatches for matchs that represente the keybindings ALT + [1-9]
    -- and if that matchs happen we catch the number which comes with and open the buffer with that number
    if #char_str == 4 then
      local byte1, byte2, byte3, byte4 = char_str:byte(1), char_str:byte(2), char_str:byte(3), char_str:byte(4)

      -- Exactly default: <80><fc>^H[1-9]
      if byte1 == 128 and byte2 == 252 and byte3 == 8 and byte4 >= 49 and byte4 <= 57 then
        local ctrl_number = byte4 - 48 -- Convert ASCII to number (49->1, 50->2, etc.)
        vim.schedule(function()
          if ctrl_number <= #filtered_buffers then
            if M.config.opt_feature.buffers_trail then
              table.insert(M.current_query, search_term)
              M.flag_confirmation = true
            end

            M._select_buffer(filtered_buffers[ctrl_number].number)
          end
        end)
        break
      end
    end

    -- Detect backspaces (all variants)
    local is_backspace = char_str == '\8' or char_str == '\127' or char_str:find("kb") or char_str:find("<80>")
    -- Check keys by their string representation
    if char_str == '\12' then -- Ctrl+l (form feed)
      vim.schedule(function()
        if #filtered_buffers > 0 then
          if M.config.opt_feature.buffers_trail then
            table.insert(M.current_query, search_term)
            M.flag_confirmation = true
          end

          M._select_buffer(filtered_buffers[selected_index].number)
        end
      end)
      break
      -- elseif char_str == ' ' then -- space
      --   vim.schedule(function()
      --     if #filtered_buffers > 0 then
      --       -- M.set_last_buffer(vim.api.nvim_get_current_buf())
      --
      --      if M.config.opt_feature.buffers_trail then
      --        M.buffers_history = filtered_buffers
      --
      --        table.insert(M.current_query, search_term)
      --        M.flag_confirmation = true
      --      end
      --      -- M.current_query = search_term
      --      -- M.flag_confirmation = true
      --       M._select_buffer(filtered_buffers[selected_index].number)
      --     end
      --   end)
      --   break
      -- elseif char_str == 'O' then
      --   vim.schedule(function()
      --     if #filtered_buffers > 0 then
      --       if M.config.opt_feature.buffers_trail then
      --         table.insert(M.current_query, search_term)
      --         M.flag_confirmation = true
      --       end
      --
      --       M._select_buffer(filtered_buffers[selected_index].number)
      --     end
      --   end)
      --   break
    elseif char_str == '#' then
      -- update_display()

      vim.api.nvim_win_close(win, true)
      vim.schedule(function()
        M.pick_files_system()
      end)
      return

      -- break
      -- elseif char_str == 'J' then -- J
      --   selected_index = math.min(#filtered_buffers, selected_index + 1)
      --   update_display()
      -- elseif char_str == 'K' then -- K
      --   selected_index = math.max(1, selected_index - 1)
      --   update_display()
      -- elseif char_str == '\10' then -- Ctrl+j (line feed)
      --   selected_index = math.min(#filtered_buffers, selected_index + 1)
      --   update_display()
      -- elseif char_str == '\11' then -- Ctrl+k (vertical tab)
      --   selected_index = math.max(1, selected_index - 1)
      --   update_display()
    elseif char_str == '\14' then -- Ctrl+n (shift out)
      selected_index = math.min(#filtered_buffers, selected_index + 1)
      update_display()
    elseif char_str == '\16' then -- Ctrl+p (data link escape)
      selected_index = math.max(1, selected_index - 1)
      update_display()
    elseif char_str == '\9' then -- TAB
      selected_index = (selected_index % #filtered_buffers) + 1
      update_display()
      -- elseif tonumber(char_str) then -- Numbers 0-9
      --   local num = tonumber(char_str)
      --   if num <= #filtered_buffers then
      --     selected_index = num
      --     update_display()
      --   end
    elseif char_str == '\27' then -- Escape
      if M.config.opt_feature.buffers_trail then
        table.insert(M.current_query, search_term)
        M.flag_confirmation = true
      end

      break
    elseif char_str == '\13' then -- Enter
      vim.schedule(function()
        if #filtered_buffers > 0 then
          -- M.set_last_buffer(vim.api.nvim_get_current_buf())

          if M.config.opt_feature.buffers_trail then
            table.insert(M.current_query, search_term)
            M.flag_confirmation = true
          end

          M._select_buffer(filtered_buffers[selected_index].number)
        end
      end)
      break
    elseif is_backspace then
      if #query > 0 then
        table.remove(query)
        selected_index = 1
        update_display()
      elseif #query == 0 and M.config.opt_feature.buffers_trail then
        M.current_query = {}
        M.flag_confirmation = false
        update_display()
      end
      -- Search characters i.e. that character typed only will be add to 'query'
      -- if the characters size was equas to 1 and if it was a character that is NOT a white space
    elseif #char_str == 1 and char_str:match('%S') then
      table.insert(query, char_str)
      selected_index = 1
      update_display()
    end
  end
  --- When some action like entry on a buffer was called by some keybindings the main loop ends and
  --- we execute the command to close the window
  vim.api.nvim_win_close(win, true)
  M._float_win = win
end

--- Function that close the window and open the buffer based on his number
--- @param buffer_number number | nil
---
function M._select_buffer(buffer_number)
  if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
    vim.api.nvim_win_close(M._float_win, true)
  end
  M.buffer_command(tostring(buffer_number))
end

--- Function to select the current line buffer based on a regular expression
--- to get the number since we are using the approach that prints the number
--- instead of allowing the native line number. For now it is not the case
---
function M._select_current_buffer()
  local line = vim.api.nvim_get_current_line()
  -- Extracts the buffer number from the line (new shape: " 1 path")
  local buffer_number = line:match('%s*[%*_]%s*(%d+)')

  if buffer_number then
    M._select_buffer(tonumber(buffer_number))
  end
end

function M.list_buffers()
  local buffers = get_buffers_with_numbers()

  vim.ui.select(buffers, {
    prompt = "Buffers:",
    format_item = function(item)
      return string.format("🖹 %-3d %-15s %s", item.number, item.name, item.path)
    end,
  }, function(choice)
    if choice then
      local existing_buf = find_buffer_by_path(choice.path)
      if existing_buf then
        vim.cmd("buffer " .. existing_buf)
      else
        vim.cmd("silent! badd " .. choice.path)
        vim.cmd("buffer " .. vim.fn.bufnr(choice.path))
      end
    end
  end)
end

--- Get the current buffer, if it is modified we save all changes
--- and after that we remove the buffer form cache and close the buffer
---
function M.close_current_buffer()
  local buf = vim.api.nvim_get_current_buf()
  local buf_name = vim.api.nvim_buf_get_name(buf)
  local buf_short_name = vim.fn.fnamemodify(buf_name, ":t")

  if vim.bo[buf].modified and vim.bo[buf].buftype == "" then
    vim.cmd("w")
  end

  remove_buffer_from_cache(buf_name, true)

  if vim.bo[buf].buftype == "" then
    vim.cmd("bd!")
  else
    vim.cmd("bd")
  end

  vim.notify(string.format("Buffer %s fechado!", buf_short_name), vim.log.levels.INFO)
end

------ swap_to_last_buffer feature ----------------------------------------------------------------------

--- Checks if the buffer param is a valid Buffer
--- @param buf integer  Buffer id (ID)
--- @return boolean
---
function M.should_save_buffer(buf)
  local buf_name = vim.api.nvim_buf_get_name(buf)

  if buf_name == "" then return false end

  local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf })
  if buftype ~= "" then return false end

  if is_plugin_buffer(buf) then return false end

  if vim.fn.filereadable(buf_name) ~= 1 then return false end

  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf })
  if filetype == "TelescopePrompt" or filetype == "TelescopeResults"
      or filetype == "bufferlist" then
    return false
  end

  return true
end

M.stack = {}
--- Every time that we trigger the Event 'BufEnter' we get the current buffer which we Enter
--- and if it is valid buffer we save it in a table call 'stack'
--- @param buf integer  Buffer id (ID)
---
function M.push_to_stack(buf)
  if M.should_save_buffer(buf) then
    if M.stack[#M.stack] == vim.api.nvim_get_current_buf() then
      return
    end

    table.insert(M.stack, buf)
    if #M.stack > 2 then
      -- vim.notify("Removeing buffer in position 1", vim.log.levels.WARN)
      table.remove(M.stack, 1)
      return
    end
  end
end

--- Get the first buffer in table 'stack' and jump to it. We get first because the first position
--- on the table 'stack' means the previous buffer that we visit since we add every new and valid
--- buffer to the last position in the table and exlude the first each time the table get de size > 2.
---
function M.pick_last()
  if #M.stack < 2 then
    vim.notify("Need at least 2 buffers in stack", vim.log.levels.WARN)
    return
  end

  local target_buf = M.stack[1]
  if target_buf and vim.api.nvim_buf_is_valid(target_buf) then
    vim.cmd("buffer " .. target_buf)
    vim.notify("Jumping to the previous buffer", vim.log.levels.WARN)
  else
    vim.notify("Previous buffer is invalid", vim.log.levels.ERROR)
    table.remove(M.stack, #M.stack - 1)
  end
end

function M.add_it_to_cache()
  local buf = vim.api.nvim_get_current_buf()
  add_buffer_to_cache(buf)
end

---------------------------------------------------------------------------------------------------------



-- Keymaps
function M.setup_keymaps()
  local keymaps = M.config.keymaps

  vim.keymap.set("n", '<leader>a', function()
    M.add_it_to_cache()
    vim.notify("addind that file to buffer_cache...", vim.log.levels.WARN)
  end, { desc = "Add file to buffer_cache" })
  vim.keymap.set("n", keymaps.pick_previous, M.pick_last, { desc = "Jump to the previous buffer" })
  vim.keymap.set("n", keymaps.list_buffers, M.list_buffers, { desc = "List buffers (with cache)" })
  vim.keymap.set("n", keymaps.move_backward, move_buffer_backward, { desc = "Move buffer backward in list" })
  vim.keymap.set("n", keymaps.move_forward, move_buffer_forward, { desc = "Move buffer forward in list" })
  vim.keymap.set('n', keymaps.buffer_picker, ':Mag <CR>', { desc = 'Open buffer by number' })
  vim.keymap.set("n", keymaps.file_picker, function()
    M.pick_files_system()
  end, { desc = 'Open file system_search in window' })

  vim.keymap.set("n", keymaps.close_buffer, function()
    if is_telescope_window() then
      close_telescope_windows()
      return
    end
    M.close_current_buffer()
  end, { desc = "Save, remove cache and close buffer" })

  vim.keymap.set("n", keymaps.clear_path, clear_current_path_buffers,
    { desc = "Clear buffers of the current path (except the current one)" })
  vim.keymap.set("n", keymaps.remove_last, remove_last_buffer_from_cache, { desc = "Remove last buffer from cache" })
  vim.keymap.set("n", keymaps.clear_cache, clear_cache, { desc = "Clear all buffer cache" })


  -- Version that allows closing information tab when existing.
  for i = 1, 9 do
    vim.keymap.set("n", "<A-" .. i .. ">", function()
      -- Checks if the current buffer is "[Draft]" and closes the tab
      local current_buf = vim.api.nvim_get_current_buf()
      local buf_name = vim.api.nvim_buf_get_name(current_buf)

      -- If it is an unnamed buffer (draft) and it is not the only tab
      if buf_name == "" then
        local tab_count = vim.fn.tabpagenr('$') -- Total numbers of tabs
        if tab_count > 1 then                   -- Only closes if there is more than one tab
          vim.cmd("tabclose")
        else
          -- If it is the only tab, just close the draft buffer
          vim.cmd("bd!")
        end
      end

      -- Open the buffer normally
      local buffers = get_buffers_with_numbers()
      if buffers[i] then
        M.buffer_command({ args = tostring(i) })
      else
        vim.notify("There is no buffer on position " .. i, vim.log.levels.WARN)
      end
    end, { desc = "Open buffer " .. i .. " from cache" })
  end
end

-- Setting up Autocommands to track events.
function M.setup_autocmds()
  local augroup = vim.api.nvim_create_augroup("PickBufferAutoCmds", {})

  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,

    callback = function(args)
      local buf = args.buf
      if is_valid_buffer(buf) and not is_plugin_buffer(buf) then
        add_buffer_to_cache(buf)
      end

      M.push_to_stack(vim.api.nvim_get_current_buf())
    end,
  })


  vim.api.nvim_create_autocmd("DirChanged", {
    group = augroup,

    callback = function()
      local cache_data = load_cache()
      local current_path = get_current_path()
      if cache_data[current_path] then
        local new_list = {}
        for _, item in ipairs(cache_data[current_path]) do
          if vim.fn.filereadable(item.path) == 1 then
            table.insert(new_list, item)
          end
        end
        cache_data[current_path] = new_list
        save_cache(cache_data)
      end
      M.stack = {}

      M.setup_cache_file_system()
    end,
  })
end

---------------------------------------------------------------------------------------------------------






-- Main Setup
function M.setup(user_config)
  local merged_config = vim.tbl_deep_extend("force", default_config, user_config or {})
  if user_config and user_config.opt_feature then
    merged_config.opt_feature = vim.tbl_deep_extend("force", default_config.opt_feature, user_config.opt_feature)
  end
  M.config = merged_config

  M.config.grep_defaults = vim.fn.expand(M.config.grep_defaults)

  setup_cache()
  setup_rg_defaults()
  M.setup_keymaps()
  M.setup_autocmds()


  vim.api.nvim_create_user_command('Mag', function(opts)
    M.buffer_command(opts.args)
  end, {
    nargs = '?',
    complete = function(arg_lead, cmd_line, cursor_pos)
      return M.buffer_completion(arg_lead, cmd_line, cursor_pos)
    end,
    desc = 'Open buffer from cache or show floating window'
  })


  return M
end

return M
