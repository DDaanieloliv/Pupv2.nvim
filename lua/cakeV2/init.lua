--  ██████╗ ██████╗ ██████╗ ███████╗
-- ██╔════╝██╔═══██╗██╔══██╗██╔════╝
-- ██║     ██║   ██║██║  ██║█████╗
-- ██║     ██║   ██║██║  ██║██╔══╝
-- ╚██████╗╚██████╔╝██████╔╝███████╗
--  ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝


local M = {}


-- Configuração padrão
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
		clear_cache = "<leader>cc"
	},
	ignore_patterns = {
		"neo%-tree", "NvimTree", "packer", "fugitive", "term://", "^no name"
	}
}

-- Adicione com as outras variáveis no topo
local ns_id = vim.api.nvim_create_namespace('PickBufferMatchHL')

M.config = vim.deepcopy(default_config)

-- Variáveis internas
local cache_file = nil

-- Funções utilitárias
local function get_buf_option(bufnr, option)
	return vim.api.nvim_get_option_value(option, { buf = bufnr })
end

local function find_buffer_by_path(path)
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(buf) == path then
			return buf
		end
	end
	return nil
end

local function is_valid_buffer(buf)
	local buf_name = vim.api.nvim_buf_get_name(buf)
	local buftype = get_buf_option(buf, "buftype")
	local filetype = get_buf_option(buf, "filetype")
	return buf_name ~= "" and buftype == "" and filetype ~= "" and vim.fn.filereadable(buf_name) == 1
end

local function is_plugin_buffer(buf)
	local buf_name = vim.api.nvim_buf_get_name(buf)
	for _, pattern in ipairs(M.config.ignore_patterns) do
		if buf_name:match(pattern) then
			return true
		end
	end
	return false
end

local function get_current_path()
	return vim.fn.getcwd()
end

local function is_telescope_window()
	local current_buf = vim.api.nvim_get_current_buf()
	local current_ft = get_buf_option(current_buf, "filetype")
	return current_ft == "TelescopePrompt"
end

local function close_telescope_windows()
	for _, win in ipairs(vim.api.nvim_list_wins()) do
		local buf = vim.api.nvim_win_get_buf(win)
		local ft = get_buf_option(buf, "filetype")
		if ft == "TelescopePrompt" or ft == "TelescopeResults" then
			pcall(vim.api.nvim_win_close, win, true)
		end
	end
end

-- Sistema de cache
local function setup_cache()
	if vim.fn.isdirectory(M.config.cache_dir) == 0 then
		vim.fn.mkdir(M.config.cache_dir, "p")
	end
	cache_file = M.config.cache_dir .. "/buffers.lua"

	if vim.fn.filereadable(cache_file) == 0 then
		save_cache({})
	end
end

local function load_cache()
	local ok, cache_data = pcall(dofile, cache_file)
	return ok and cache_data or {}
end

local function save_cache(cache_data)
	local file = io.open(cache_file, "w")
	if file then
		file:write("return " .. vim.inspect(cache_data))
		file:close()
	end
end

local function add_buffer_to_cache(buf)
	local buf_name = vim.api.nvim_buf_get_name(buf)
	if not is_valid_buffer(buf) then return end

	local current_path = get_current_path()
	local cache_data = load_cache()
	cache_data[current_path] = cache_data[current_path] or {}

	local exists = false
	for _, item in ipairs(cache_data[current_path]) do
		if item.path == buf_name then
			exists = true
			break
		end
	end

	if not exists then
		table.insert(cache_data[current_path], {
			name = vim.fn.fnamemodify(buf_name, ":t"),
			path = buf_name,
		})
		save_cache(cache_data)
	end
end

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

local function remove_buffer_from_cache(path, force)
	local current_path = get_current_path()
	local cache_data = load_cache()

	if not cache_data[current_path] then
		return false
	end

	for i, item in ipairs(cache_data[current_path]) do
		if item.path == path then
			if #cache_data[current_path] == 1 and not force then
				vim.notify("Não é possível remover o último buffer do path atual!", vim.log.levels.WARN)
				return false
			end

			table.remove(cache_data[current_path], i)
			save_cache(cache_data)
			return true
		end
	end
	return false
end

local function remove_last_buffer_from_cache()
	local current_path = get_current_path()
	local current_buf_name = vim.api.nvim_buf_get_name(0)
	local cache_data = load_cache()

	if not cache_data[current_path] or #cache_data[current_path] == 0 then
		vim.notify("Nenhum buffer para remover neste path!", vim.log.levels.WARN)
		return
	end

	local last_buffer = cache_data[current_path][#cache_data[current_path]]
	if last_buffer.path == current_buf_name then
		vim.notify("Remoção não sucedida devido o último buffer ser seu buffer atual", vim.log.levels.WARN)
		return
	end

	local buf_to_close = find_buffer_by_path(last_buffer.path)
	table.remove(cache_data[current_path])
	save_cache(cache_data)

	if buf_to_close and buf_to_close ~= vim.api.nvim_get_current_buf() then
		vim.api.nvim_buf_delete(buf_to_close, { force = true })
		vim.notify("Último buffer removido do cache e fechado", vim.log.levels.INFO)
	else
		vim.notify("Último buffer removido do cache", vim.log.levels.INFO)
	end
end

local function clear_cache()
	local current_buf = vim.api.nvim_get_current_buf()
	local current_path = get_current_path()
	local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
	local cache_data = load_cache()

	for path, buffers in pairs(cache_data) do
		if path ~= current_path then
			for _, item in ipairs(buffers) do
				local buf = find_buffer_by_path(item.path)
				if buf and buf ~= current_buf then
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
	vim.notify("Cache limpo! Apenas o buffer atual foi mantido.", vim.log.levels.INFO)
end

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
							vim.notify("Erro ao salvar " .. item.path .. ": " .. err, vim.log.levels.ERROR)
						end
					end
					pcall(vim.api.nvim_buf_delete, buf, { force = true })
				end
			end
		end
	end

	save_cache(new_cache)
	pcall(vim.cmd, "silent! call clearmatches()")
	pcall(vim.cmd, "silent! call histdel('/', -1)")
	vim.notify("Buffers do path atual foram salvos e fechados", vim.log.levels.INFO)
end

local function move_buffer_forward()
	local current_buf = vim.api.nvim_get_current_buf()
	local current_path = get_current_path()
	local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
	local cache_data = load_cache()

	if not cache_data[current_path] or #cache_data[current_path] < 2 then
		vim.notify("Não há buffers suficientes para mover", vim.log.levels.WARN)
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
		vim.notify("Buffer já está na última posição", vim.log.levels.INFO)
		return
	end

	cache_data[current_path][current_index], cache_data[current_path][current_index + 1] =
	cache_data[current_path][current_index + 1], cache_data[current_path][current_index]

	save_cache(cache_data)
	vim.notify(string.format("Buffer movido para a posição %d", current_index + 1), vim.log.levels.INFO)
end

local function move_buffer_backward()
	local current_buf = vim.api.nvim_get_current_buf()
	local current_path = get_current_path()
	local current_buf_name = vim.api.nvim_buf_get_name(current_buf)
	local cache_data = load_cache()

	if not cache_data[current_path] or #cache_data[current_path] < 2 then
		vim.notify("Não há buffers suficientes para mover", vim.log.levels.WARN)
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
		vim.notify("Buffer já está na primeira posição", vim.log.levels.INFO)
		return
	end

	cache_data[current_path][current_index], cache_data[current_path][current_index - 1] =
	cache_data[current_path][current_index - 1], cache_data[current_path][current_index]

	save_cache(cache_data)
	vim.notify(string.format("Buffer movido para a posição %d", current_index - 1), vim.log.levels.INFO)
end


function M.buffer_completion(arg_lead, cmd_line, cursor_pos)
	local completions = {}
	local buffers = get_buffers_with_numbers()

	for _, buf in ipairs(buffers) do
		-- Encurta o path para mostrar apenas as últimas 2-3 pastas
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



function M.test_title_input()
	local query = {}

	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = 'editor',
		width = 60,
		height = 10,
		row = 5,
		col = 10,
		style = 'minimal',
		border = 'single',
		title = { { "> ", "FloatTitle" } },
		title_pos = "left",
	})

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"Digite no título acima ↑",
		"",
		"Backspace: apagar",
		"Enter: confirmar",
		"ESC: sair"
	})

	local function update_title()
		local title_text = "> " .. table.concat(query)
		vim.api.nvim_win_set_config(win, {
			title = { { title_text, "FloatTitle" } }
		})
		vim.cmd("redraw")
	end

	update_title()

	while true do
		local ok, char = pcall(vim.fn.getcharstr)
		if not ok then break end

		-- Verifica se é Backspace (todas as representações possíveis)
		local is_backspace = char == '\8' or char == '\127' or char == '<80>kb' or char:find('kb$')

		if char == '\27' then -- Escape
			break
		elseif char == '\13' then -- Enter
			vim.notify("Confirmado: " .. table.concat(query), vim.log.levels.INFO)
			break
		elseif is_backspace then -- Backspace
			if #query > 0 then
				table.remove(query)
				update_title()
			end
		elseif char:match('^[%g%s]$') then -- Caracteres normais
			table.insert(query, char)
			update_title()
		end
	end

	vim.api.nvim_win_close(win, true)
	vim.api.nvim_buf_delete(buf, {force = true})
end







function M.buffer_command(args)
	-- Verifica se args é uma string (quando chamado via comando)
	if type(args) == "string" then
		args = { args = args }
	end

	args = args or {}
	local target_arg = args.args or ""

	-- local buffers = get_buffers_with_numbers()
	--
	-- if target_arg == "" then
	--     print("Buffers:")
	--     for _, buf in ipairs(buffers) do
	--         local status = buf.is_open and "* " or "_"
	--         -- Encurta o path da mesma forma que na completion
	--         local short_path = vim.fn.fnamemodify(buf.path, ":~:")
	--         local filename = vim.fn.fnamemodify(buf.path, ":t")
	--         local path_without_filename = short_path:sub(1, #short_path - #filename)
	--
	--         -- Imprime com highlight para o nome do arquivo
	--         print(string.format("  %s[%d] %s", status, buf.number, path_without_filename) ..
	--               "" .. filename .. " ")
	--     end
	--     return
	-- end

	if target_arg == "" then
		-- Mostra a janela flutuante em vez de imprimir no terminal
		M.show_buffers_in_float()
		return
	end

	local buffers = get_buffers_with_numbers()


	local target = target_arg
	local num = tonumber(target)
	local found_buffer = nil

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
			vim.notify("Arquivo não encontrado: " .. found_buffer.path, vim.log.levels.ERROR)
			remove_buffer_from_cache(found_buffer.path, true)
		end
	else
		vim.notify("Buffer não encontrado: " .. target, vim.log.levels.WARN)
	end
end








function M.show_buffers_in_float()
	local buffers = get_buffers_with_numbers()

	-- Conteúdo da janela flutuante
	-- local lines = {"Buffers:"}
	local lines = {}
	for _, buf in ipairs(buffers) do
		local status = buf.is_open and "·" or "_"
		-- Encurta o path da mesma forma que na completion
		local short_path = vim.fn.fnamemodify(buf.path, ":~:")
		local filename = vim.fn.fnamemodify(buf.path, ":t")
		local path_without_filename = short_path:sub(1, #short_path - #filename)

		local line = string.format("  %s%d: %s%s", status, buf.number, path_without_filename, filename)
		table.insert(lines, line)
	end

	-- Calcular largura dinâmica baseada no conteúdo
	local max_line_length = 0
	for _, line in ipairs(lines) do
		if #line > max_line_length then
			max_line_length = #line
		end
	end

	-- Configurações da janela flutuante - CANTO INFERIOR ESQUERDO
	-- local width = math.min(max_line_length + 2, 80)   -- Largura dinâmica com limite máximo
	-- local height = #lines
	local width = 69   -- Largura dinâmica com limite máximo
	local height = 25
	local row = vim.o.lines - height - 1              -- Canto inferior
	local col = 0                                     -- Canto esquerdo (colado na borda)



	local query = {}
	local selected_index = 1  -- Índice do item selecionado



	-- Criar buffer flutuante
	local buf = vim.api.nvim_create_buf(false, true)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = 'editor',
		width = width,
		height = height,
		row = row,
		col = col,
		style = 'minimal',
		border = {
			{ "╭", "FloatBorder" },
			{ "─", "FloatBorder" },
			{ "╮", "FloatBorder" },
			{ "│", "FloatBorder" },
			{ "╯", "FloatBorder" },
			{ "─", "FloatBorder" },
			{ "╰", "FloatBorder" },
			{ "│", "FloatBorder" },
		},
		-- -- Título na parte inferior direita
		-- title = {
		-- 	{ " > ", "FloatTitle" }
		-- },
		-- Título com cor diferente para o ">" e para o input
		title = {
			{ "> ", "PromptSymbol" },      -- Símbolo ">" com cor diferente
			{ table.concat(query), "InputText" }  -- Texto do input com outra cor
		},

		title_pos = "left",     -- Título à direita
		footer = {
			{ " Buffers ", "FloatFooter" }
		},
		footer_pos = "left",     -- Footer à esquerda
	})


	-- Configurar o buffer
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	vim.api.nvim_buf_set_option(buf, 'filetype', 'bufferlist')

	-- CONFIGURAÇÕES DE HIGHLIGHT PARA A JANELA FLUTUANTE
	-- Aplicar o highlight da linha do cursor
	vim.api.nvim_win_set_option(win, 'cursorline', true)  -- Ativa cursorline
	vim.api.nvim_win_set_option(win, 'cursorlineopt', 'both')  -- Destaca linha e número
	vim.api.nvim_win_set_option(win, 'winhighlight', 'CursorLine:FloatCursorLine')


	-- Definir highlight personalizado para CursorLine
	vim.cmd([[
				highlight FloatCursorLine guibg=#312f2d
				]])


	-- Adicionar highlights personalizados (opcional)
	vim.cmd([[
				" highlight NormalNC guibg=none
				highlight NormalFloat  guibg=#181715
				highlight FloatBorder  guibg=#181715

				highlight PromptSymbol guibg=#06070d
				highlight InputText    guibg=#06070d

				highlight FloatFooter  guibg=#181715

				highlight PromptSymbol guifg=#B9B8B4
				highlight FloatBorder  guifg=#B9B8B4
				highlight FloatTitle   guifg=#B9B8B4 guibg=black " guibg=#504945
				highlight FloatFooter  guifg=#B9B8B4 " guibg=none " guibg=#3c3836
				highlight InputText    guifg=#A9B7C6 " gui=bold
				]])

	-- -- Mapeamentos para fechar a janela
	-- vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', { noremap = true, silent = true })
	-- vim.api.nvim_buf_set_keymap(buf, 'n', '<ESC>', ':q<CR>', { noremap = true, silent = true })
	--
	-- -- Mapeamentos para selecionar buffer
	for i = 1, #buffers do
		if i <= 9 then     -- Apenas teclas 1-9
			vim.api.nvim_buf_set_keymap(buf, 'n', tostring(i),
				':lua require("pick-buffer")._select_buffer(' .. i .. ')<CR>',
				{ noremap = true, silent = true })
		end
	end

	-- -- Mapeamento para selecionar com Enter
	vim.api.nvim_buf_set_keymap(buf, 'n', '<CR>',
		':lua require("pick-buffer")._select_current_buffer()<CR>',
		{ noremap = true, silent = true })




	-- local function update_display()
	-- 	vim.api.nvim_buf_set_option(buf, 'modifiable', true)
	--
	-- 	-- Atualiza título
	-- 	local title_text = "> " .. table.concat(query) .. " "
	-- 	-- vim.api.nvim_win_set_config(win, {
	-- 	-- 	title = { { title_text, "FloatTitle" } },
	-- 	-- 	footer = { { " BUFFERS " } }
	-- 	-- })
	-- 	vim.api.nvim_win_set_config(win, {
	-- 		title = {
	-- 			{ "❭", "PromptSymbol" },
	-- 			{ " " .. table.concat(query) .. "│ ", "InputText" }
	-- 		},
	-- 		footer = { { " BUFFERS " } }
	-- 	})
	--
	-- 	-- Filtra buffers
	-- 	if #query > 0 then
	-- 		local search_term = table.concat(query):lower()
	-- 		filtered_buffers = {}
	-- 		for _, buf in ipairs(buffers) do
	-- 			if buf.name:lower():find(search_term, 1, true) or
	-- 				buf.path:lower():find(search_term, 1, true) then
	-- 				table.insert(filtered_buffers, buf)
	-- 			end
	-- 		end
	-- 	else
	-- 		filtered_buffers = buffers
	-- 	end
	--
	-- 	selected_index = math.max(1, math.min(selected_index, #filtered_buffers))
	--
	-- 	-- Atualiza conteúdo COM SELEÇÃO VISUAL
	-- 	local lines = {}
	-- 	for i, buf in ipairs(filtered_buffers) do
	-- 		-- local status = buf.is_open and "·" or "_"
	-- 		local status = buf.is_open and " " or " _"
	-- 		local selector = (i == selected_index) and "" or ""
	-- 		local short_path = vim.fn.fnamemodify(buf.path, ":~:")
	-- 		local filename = vim.fn.fnamemodify(buf.path, ":t")
	-- 		local path_without_filename = short_path:sub(1, #short_path - #filename)
	--
	-- 		local line = string.format("%s%s%d: %s%s", selector, status, buf.number, path_without_filename, filename)
	-- 		table.insert(lines, line)
	-- 	end
	--
	-- 	vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
	-- 	vim.api.nvim_buf_set_option(buf, 'modifiable', false)
	--
	-- 	-- Move o cursor para o item selecionado
	-- 	vim.api.nvim_win_set_cursor(win, {selected_index, 0})
	-- 	vim.cmd("redraw")
	-- end


	-- Função update_display(), com highlight para matchs.
	local function update_display()
		vim.api.nvim_buf_set_option(buf, 'modifiable', true)

		-- Atualiza título
		vim.api.nvim_win_set_config(win, {
			title = {
				{ "", "PromptSymbol" },
				{ " " .. table.concat(query) .. "│ ", "InputText" }
			},
			footer = { { " BUFFERS " } }
		})

		vim.cmd([[
		highlight PickBufferMatch guifg=#7A729A gui=bold
		highlight PickBufferMatchCurrent guifg=#FF6B6B gui=bold
    ]])

		-- Filtra buffers
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
			filtered_buffers = buffers
		end

		selected_index = math.max(1, math.min(selected_index, #filtered_buffers))

		-- Limpa highlights anteriores
		vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

		-- Atualiza conteúdo
		local lines = {}
		for i, buf_item in ipairs(filtered_buffers) do
			local status = buf_item.is_open and " " or "🖹"
			local short_path = vim.fn.fnamemodify(buf_item.path, ":~:")
			local filename = vim.fn.fnamemodify(buf_item.path, ":t")
			local path_without_filename = short_path:sub(1, #short_path - #filename)

			local line = string.format("%s%d %s%s", status, buf_item.number, path_without_filename, filename)
			table.insert(lines, line)
		end

		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(buf, 'modifiable', false)

		-- ADICIONE ESTA PARTE PARA HIGHLIGHT DOS MATCHES
		if #query > 0 then
			local search_lower = table.concat(query):lower()

			for i, buf_item in ipairs(filtered_buffers) do
				local line_text = lines[i]
				local line_lower = line_text:lower()

				-- Encontra todas as posições onde a query aparece
				local start_pos = 1
				while true do
					local match_start, match_end = line_lower:find(search_lower, start_pos, true)
					if not match_start then break end

					vim.api.nvim_buf_add_highlight(
						buf,
						ns_id,
						'PickBufferMatch',  -- Seu highlight personalizado
						i - 1,
						match_start - 1,
						match_end
					)
					start_pos = match_end + 1
				end
			end
		end

		-- Move o cursor para o item selecionado
		vim.api.nvim_win_set_cursor(win, {selected_index, 0})
		vim.cmd("redraw")
	end




	update_display()

	-- LOOP PRINCIPAL COM NAVEGAÇÃO CTRL+TECLAS
	while true do
		local ok, key = pcall(vim.fn.getchar)
		if not ok then break end

		-- DETECÇÃO ESPECÍFICA PARA <80>kb
		-- O backspace está vindo como um código especial, não como string
		local is_backspace = false
		local char_str = ""

		-- Verifica se é o código especial do backspace (<80>kb)
		if type(key) == "number" then
			-- Para códigos numéricos, convertemos para string para verificar
			char_str = vim.fn.nr2char(key)

			-- Backspace tradicional (ASCII 8 ou 127)
			if key == 8 or key == 127 then
				is_backspace = true
			end
		else
			-- Para strings, verificamos diretamente
			char_str = key
		end

		-- Verifica se é o backspace especial <80>kb
		if char_str:find("kb") or char_str:find("<80>") then
			is_backspace = true
		end

		-- NAVEGAÇÃO
		-- if key == 10 or char_str == 'J' then -- Ctrl+j ou 'J'
		-- 	selected_index = math.min(#filtered_buffers, selected_index + 1)
		-- 	update_display()
		-- elseif key == 11 or char_str == 'K' then -- Ctrl+k ou 'K'
		-- 	selected_index = math.max(1, selected_index - 1)
		-- 	update_display()
		if key == 10 then -- Ctrl+j
			selected_index = math.min(#filtered_buffers, selected_index + 1)
			update_display()
		elseif key == 11 then -- Ctrl+k
			selected_index = math.max(1, selected_index - 1)
			update_display()
		elseif key == 14 then -- Ctrl+n
			selected_index = math.min(#filtered_buffers, selected_index + 1)
			update_display()
		elseif key == 16 then -- Ctrl+p
			selected_index = math.max(1, selected_index - 1)
			update_display()

			-- ⭐ TECLAS NUMÉRICAS
		elseif tonumber(char_str) then
			local num = tonumber(char_str)
			if num <= #filtered_buffers then
				selected_index = num
				update_display()
			end

			-- AÇÕES
		elseif key == 27 or char_str == '\27' then -- Escape
			break
		elseif key == 13 or char_str == '\13' then -- Enter
			vim.schedule(function()
				if #filtered_buffers > 0 then
					M._select_buffer(filtered_buffers[selected_index].number)
				end
			end)
			break

			-- elseif char_str == 'q' then -- Quit
			-- 	break

			-- BACKSPACE - CORREÇÃO PARA <80>kb
		elseif is_backspace then
			if #query > 0 then
				table.remove(query)
				selected_index = 1
				update_display()
			end

			-- INPUT NORMAL
		elseif char_str:match('%S') and #char_str == 1 then
			table.insert(query, char_str)
			selected_index = 1
			update_display()

		end
	end


	vim.api.nvim_win_close(win, true)


	-- Salvar referência da janela flutuante para fechar depois
	M._float_win = win
end










-- Função auxiliar para selecionar buffer
function M._select_buffer(buffer_number)
	if M._float_win and vim.api.nvim_win_is_valid(M._float_win) then
		vim.api.nvim_win_close(M._float_win, true)
	end
	M.buffer_command(tostring(buffer_number))
end



-- Função para selecionar buffer da linha atual
function M._select_current_buffer()
	local line = vim.api.nvim_get_current_line()
	-- Extrai o número do buffer da linha (novo formato: "·1: path")
	local buffer_number = line:match('%s*[%*_]%s*(%d+):')

	if buffer_number then
		M._select_buffer(tonumber(buffer_number))
	end
end


function M.list_buffers()
	local buffers = get_buffers_with_numbers()

	vim.ui.select(buffers, {
		prompt = "Buffers:",
		format_item = function(item)
			return string.format("[%d] %s   %s", item.number, item.name, item.path)
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

-- Keymaps
function M.setup_keymaps()
	local keymaps = M.config.keymaps

	vim.keymap.set('n', '<leader>bf', M.show_buffers_in_float, { desc = 'Mostrar buffers em janela flutuante' })

	vim.keymap.set("n", keymaps.list_buffers, M.list_buffers, { desc = "Listar buffers (com cache)" })
	vim.keymap.set("n", keymaps.move_backward, move_buffer_backward, { desc = "Mover buffer para trás na lista" })
	vim.keymap.set("n", keymaps.move_forward, move_buffer_forward, { desc = "Mover buffer para frente na lista" })
	vim.keymap.set('n', keymaps.buffer_picker, ':B ', { desc = 'Abrir buffer por número' })

	vim.keymap.set("n", keymaps.close_buffer, function()
		if is_telescope_window() then
			close_telescope_windows()
			return
		end
		M.close_current_buffer()
	end, { desc = "Salvar, remover do cache e fechar buffer" })

	vim.keymap.set("n", keymaps.clear_path, clear_current_path_buffers,
		{ desc = "Limpar buffers do path atual (exceto o atual)" })
	vim.keymap.set("n", keymaps.remove_last, remove_last_buffer_from_cache, { desc = "Remover último buffer do cache" })
	vim.keymap.set("n", keymaps.clear_cache, clear_cache, { desc = "Limpar todo o cache de buffers" })




	-- for i = 1, 9 do
	-- 	vim.keymap.set("n", "<A-" .. i .. ">", function()
	-- 		local buffers = get_buffers_with_numbers()
	-- 		if buffers[i] then
	-- 			M.buffer_command({ args = tostring(i) })
	-- 		else
	-- 			vim.notify("Não há buffer na posição " .. i, vim.log.levels.WARN)
	-- 		end
	-- 	end, { desc = "Abrir buffer " .. i .. " do cache" })
	-- end


	-- Versão que permite fechar tab informativa quando existente.
	for i = 1, 9 do
		vim.keymap.set("n", "<A-" .. i .. ">", function()
			-- Verifica se o buffer atual é "[Rascunho]" e fecha a tab
			local current_buf = vim.api.nvim_get_current_buf()
			local buf_name = vim.api.nvim_buf_get_name(current_buf)

			-- Se for um buffer sem nome (rascunho) e não for a única aba
			if buf_name == "" then
				local tab_count = vim.fn.tabpagenr('$')  -- Número total de abas
				if tab_count > 1 then  -- Só fecha se houver mais de uma aba
					vim.cmd("tabclose")
				else
					-- Se for a única aba, apenas fecha o buffer rascunho
					vim.cmd("bd!")
				end
			end

			-- Abre o buffer normalmente
			local buffers = get_buffers_with_numbers()
			if buffers[i] then
				M.buffer_command({ args = tostring(i) })
			else
				vim.notify("Não há buffer na posição " .. i, vim.log.levels.WARN)
			end
		end, { desc = "Abrir buffer " .. i .. " do cache" })
	end

end

-- Autocommands
function M.setup_autocmds()
	-- Id group
	local augroup = vim.api.nvim_create_augroup("PickBufferAutoCmds", {})

	vim.api.nvim_create_autocmd("BufEnter", {
		group = augroup,

		-- A keyword'callback', necessária pq o como passamos uma tabela como argumento
		-- não ter palavras chaves como 'group' ou 'callback' causaria um erro pois a
		-- api do lua não entenderia como ler essa tabela visto que se não usassemos a
		-- keyword 'callback' a função seria considerada um indice.
		callback = function(args)
			-- O parâmetro 'args' é Tabela que o Neovim passa automaticamente para a callback
			-- quando o evento ocorre. args.buf contém o número do buffer onde o evento aconteceu.
			local buf = args.buf
			if is_valid_buffer(buf) and not is_plugin_buffer(buf) then
				add_buffer_to_cache(buf)
			end
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
		end,
	})
end

-- Setup principal
function M.setup(user_config)
	M.config = vim.tbl_deep_extend("force", default_config, user_config or {})

	setup_cache()
	M.setup_keymaps()
	M.setup_autocmds()

	return M
end

return M
