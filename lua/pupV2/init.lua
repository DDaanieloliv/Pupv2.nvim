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
  keymaps = {
    list_buffers = "<leader>ls",
    move_backward = "<leader>[",
    move_forward = "<leader>]",
    buffer_picker = "ç",
    close_buffer = "<leader>q",
    clear_path = "<leader>x",
    remove_last = "<leader>r",
    pick_previous = "<leader>la",
    clear_cache = "<leader>cc"
  },
	ignore_patterns = {
    "TelescopePrompt", "TelescopeResults", "bufferlist",	"neo%-tree", "NvimTree", "packer", "fugitive", "term://", "^no name"
	},
  style = {
    border = 'rounded',
    background       = nil,
    cursor_line      = nil,
    border_color     = nil,
    title_color      = nil,
    color_symbol     = nil,
    match_highlight  = '#9484D2',
    input_background = nil,
    input_text       = nil,
    prompt_symbol    = '',
    input_cursor     = '│ ',
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
  return buf_name ~= "" and buftype == "" and filetype ~= "" and vim.fn.filereadable(buf_name) == 1
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
    table.insert(cache_data[current_path], {      -- In Lua array are 1-based intead 0-based
      name = vim.fn.fnamemodify(buf_name, ":t"),  -- :t >> tail >> last part of the path >> buffer name
      path = buf_name,
    })
    save_cache(cache_data)
  end
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


---------------------------------------------------------------------------------------------------------







------ M.table functios ---------------------------------------------------------------------------------


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

	--[[
  If the current @param is diferent of "" we searches matches in completions table with arg_lead like that
  'print(("abc"):match("^a"))' (It prints 'abc' if it have some match tha beginning with "a"
  ]]
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


	--[[
  If the received @param is == "", we call the function 'M.show_buffers_in_float'
  that show all buffer related to the current_path
  ]]
  if target_arg == "" then
    -- Show floating window instead of printing to terminal
    M.show_buffers_in_float()
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







M.buffers_history = nil

--- Lounch a window tha shows all buffers related to the current_path
---
function M.show_buffers_in_float()
	local buffers = get_buffers_with_numbers()
	local style = M.config.style

	local query = {}
	local selected_index = 1

  if M.config.opt_feature.buffers_trail then
    if M.buffers_history ~= nil then
      buffers = M.buffers_history
    end
  end
	local filtered_buffers = buffers


  ---- Setting window configs ------------------------------------------------------------
	local num_lines = 0
  if buffers then
    for i, _ in ipairs(buffers) do
      num_lines = i
    end
  end

 	-- Floating Window Settings - BOTTOM LEFT CORNER
	local width = 75
	-- local height = 20
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
			{ " Buffers ", "FloatFooter" }
		},
		footer_pos = "left",
	})


	--- Configure the buffer option with some option that we could see in ':set all'
	---
	vim.api.nvim_set_option_value('modifiable', false, { buf = buf })
	vim.api.nvim_set_option_value('filetype', 'bufferlist', { buf = buf })
	---
	vim.api.nvim_set_option_value('number', true, { win = win })
	vim.api.nvim_set_option_value('numberwidth', 1, { win = win })
	vim.api.nvim_set_option_value('cursorline', true, { win = win })
	vim.api.nvim_set_option_value('cursorlineopt', 'line', { win = win })
	vim.api.nvim_set_option_value('winhighlight', 'CursorLine:FloatCursorLine', { win = win })


	if style.border_color then
		vim.cmd(string.format("highlight FloatBorder guifg=%s", style.border_color))
		vim.cmd(string.format("highlight PromptSymbol guifg=%s", style.border_color))
	end
	if style.color_symbol then
		vim.cmd(string.format("highlight PromptSymbol guifg=%s", style.color_symbol))
	end
	if style.cursor_line then
		vim.cmd(string.format("highlight FloatCursorLine guibg=%s", style.cursor_line))
	end
	if style.match_highlight then
		vim.cmd(string.format("highlight PickBufferMatch guifg=%s gui=bold", style.match_highlight))
	end
	if style.input_text then
		vim.cmd(string.format("highlight InputText guifg=%s", style.input_text))
	end
	if style.title_color then
		vim.cmd(string.format("highlight FloatTitle guifg=%s", style.title_color))
		vim.cmd(string.format("highlight FloatFooter guifg=%s", style.title_color))
	end
	if style.input_background then
		vim.cmd(string.format("highlight InputText guibg=%s", style.input_background))
	end
	if style.background then
		vim.cmd(string.format("highlight NormalFloat guibg=%s", style.background))
		vim.cmd(string.format("highlight FloatBorder guibg=%s", style.background))
		vim.cmd(string.format("highlight PromptSymbol guibg=%s", style.background))
	end
  -----------------------------------------------------------------------------------------------------

	-- Set a keymap that trigger the function ':lua require("pick-buffer")._select_current_buffer()<CR>'
	-- vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',
	-- 	':lua require("pick-buffer")._select_current_buffer()<CR>',
	-- 	{ noremap = true, silent = true })


  ---- Function that deal with text input -------------------------------------------------------------

	-- Function update_display with truncate
	local function update_display()
		--[[ The function : nvim_buf_set_option is Deprecated. Use |nvim_set_option_value()| instead. ]]
		-- vim.api.nvim_buf_set_option(buf, 'modifiable', true)
		--
		-- Now we allow the buffer to be modified
		vim.api.nvim_set_option_value('modifiable', true, { buf = buf })

		-- Update the title
		vim.api.nvim_win_set_config(win, {
			title = {
				{ style.prompt_symbol,                              "PromptSymbol" },
				{ " " .. table.concat(query) .. style.input_cursor, "InputText" }
			},
			footer = { { " BUFFERS " } }
		})

    -- Based on the content on table query we filter the table 'buffers'
    -- Creating a new table 'filtered_buffers' tha are displyed later according to what we type
		if #query > 0 then
			local search_term = table.concat(query):lower()
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
		-- selected_index = math.max(1, math.min(selected_index, #filtered_buffers))


		-- Clears previous highlights
    --
    -- • {buffer}      Buffer id, or 0 for current buffer
    -- • {ns_id}       Namespace to clear, or -1 to clear all namespaces.
    -- • {line_start}  Start of range of lines to clear
    -- • {line_end}    End of range of lines to clear (exclusive) or -1 to
    --                 clear to end of buffer.
    --
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- Updates content with truncated paths
    --
    -- With the 'filtered_buffers' that we get, base on the query we fill 'lines' table with
    -- the Itens from 'filtered_buffers', but now with a truncated path tha fits on the window and a status
		local lines = {}
    -- In first interaction 'filtered_buffers' is a table with all buffers related to the current_path
		for _, buf_item in ipairs(filtered_buffers) do
			-- for i, buf_item in ipairs(filtered_buffers) do
			-- local status = buf_item.is_open and " " or "🖹"
			local status = buf_item.is_open and "🖹" or "🖹"
			-- Uses truncate_path to ensure the file name is visible
			local truncated_path = truncate_path(buf_item.path, 69) -- Fit within window width

			-- local line = string.format("%d %s%s", buf_item.number, status, truncated_path)
			-- local line = string.format("%s %-3d %s", status, buf_item.number, truncated_path)
			local line = string.format("%s%s", status, truncated_path)
			table.insert(lines, line)
		end

		-- Relace the lines on the buffer with the lines of an array
    -- So with that we change the buffer displyed on the window, to show the buffes in table 'lines'
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		-- vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)

		--[[ The function : nvim_buf_set_option is Deprecated. Use |nvim_set_option_value()| instead. ]]
		-- vim.api.nvim_buf_set_option(buf, 'modifiable', false)

    -- Lock the buffer edition for safety
		vim.api.nvim_set_option_value('modifiable', false, { buf = buf })

		-- Apply highlight to matches
		if #query > 0 then
			local search_lower = table.concat(query):lower()

      --- We go through each of the lines in filtered_buffers
			for i, _ in ipairs(filtered_buffers) do
				-- for i, buf_item in ipairs(filtered_buffers) do
				local line_text = lines[i]
				local line_lower = line_text:lower()

				local start_pos = 1
				while true do
          --[[
          'string.find()' Return two values when find some match, we define 'match_start' that
          will receive the initial position(related to the string index where the match begins)
          'match_end' will receive the last position(related to the string index where the match finish)
          ]]
					local match_start, match_end = line_lower:find(search_lower, start_pos, true)
					if not match_start then break end
					--[[ the function : nvim_buf_add_highlightUse is Deprecated. Use |vim.hl.range()| or |nvim_buf_set_extmark()| ]]
					-- vim.api.nvim_buf_add_highlight(
					--   buf,
					--   ns_id,
					--   'PickBufferMatch',
					--   i - 1,
					--   match_start - 1,
					--   match_end
					-- )
          --- Apply to some range of text related to the buffer, the highlight group
					vim.hl.range(
						buf,
						ns_id,
						'PickBufferMatch',
            --- We define the lines where we want to add the highlight groups,
            --- because since we are adding them to a buffer, we need to specify
            --- on which line and in which part of its text the group should be applied.
            --- That’s why we use 'i - 1'. The '-1' is because the Vim API is 0-based.
						{ i - 1, match_start - 1 },
						{ i - 1, match_end },
						{ inclusive = false }
					)
          --- That line which update 'start_pos', crucial because when we find the first match
          --- and we add the highlight group to that match(range text) we set on start_pos the position
          --- where we stop to search for match line_lower. So it make us come back to the string position
          --- which we can see 'match_end + 1' and continue searches for matchs in 'line_lower' string.
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
  --
  -- That main loop after we open the float window and we call tha 'update_display'
  -- function above, we starts a loop which get each input sent by our keyboard except
  -- the keybindings which are defined bellow
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
            -- M.set_last_buffer(vim.api.nvim_get_current_buf())

            if M.config.opt_feature.buffers_trail then
              M.buffers_history = filtered_buffers
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
          -- M.set_last_buffer(vim.api.nvim_get_current_buf())

          if M.config.opt_feature.buffers_trail then
            M.buffers_history = filtered_buffers
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
      --      end
      --
			--       M._select_buffer(filtered_buffers[selected_index].number)
			--     end
			--   end)
			--   break
		elseif char_str == 'O' then
			vim.schedule(function()
				if #filtered_buffers > 0 then
          -- M.set_last_buffer(vim.api.nvim_get_current_buf())

          if M.config.opt_feature.buffers_trail then
            M.buffers_history = filtered_buffers
          end

					M._select_buffer(filtered_buffers[selected_index].number)
				end
			end)
			break
		elseif char_str == 'J' then -- J
			selected_index = math.min(#filtered_buffers, selected_index + 1)
			update_display()
		elseif char_str == 'K' then -- K
			selected_index = math.max(1, selected_index - 1)
			update_display()
		elseif char_str == '\10' then -- Ctrl+j (line feed)
			selected_index = math.min(#filtered_buffers, selected_index + 1)
			update_display()
		elseif char_str == '\11' then -- Ctrl+k (vertical tab)
			selected_index = math.max(1, selected_index - 1)
			update_display()
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
        M.buffers_history = filtered_buffers
      end

			break
		elseif char_str == '\13' then -- Enter
			vim.schedule(function()
				if #filtered_buffers > 0 then
          -- M.set_last_buffer(vim.api.nvim_get_current_buf())

          if M.config.opt_feature.buffers_trail then
            M.buffers_history = filtered_buffers
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
        buffers = get_buffers_with_numbers()
        M.buffers_history = buffers
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

  local buftype = vim.api.nvim_get_option_value("buftype", { buf = buf})
  if buftype ~= "" then return false end

  if is_plugin_buffer(buf) then return false end

  if vim.fn.filereadable(buf_name) ~= 1 then return false end

  local filetype = vim.api.nvim_get_option_value("filetype", { buf = buf})
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
    if M.stack[#M.stack] == vim.api.nvim_get_current_buf()   then
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

---------------------------------------------------------------------------------------------------------



-- Keymaps
function M.setup_keymaps()
  local keymaps = M.config.keymaps

  -- vim.keymap.set('n', '<leader>bf', M.show_buffers_in_float, { desc = 'Show buffer in a float window' })

  vim.keymap.set("n", keymaps.pick_previous, M.pick_last, { desc = "Jump to the previous buffer" })
  vim.keymap.set("n", keymaps.list_buffers, M.list_buffers, { desc = "List buffers (with cache)" })
  vim.keymap.set("n", keymaps.move_backward, move_buffer_backward, { desc = "Move buffer backward in list" })
  vim.keymap.set("n", keymaps.move_forward, move_buffer_forward, { desc = "Move buffer forward in list" })
  vim.keymap.set('n', keymaps.buffer_picker, ':Mag ', { desc = 'Open buffer by number' })

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
        if tab_count > 1 then               -- Only closes if there is more than one tab
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

  -- M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

  setup_cache()
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
