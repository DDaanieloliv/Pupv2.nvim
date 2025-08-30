if exists('g:loaded_pick_buffer')
    finish
endif
let g:loaded_pick_buffer = 1

lua require('pick-buffer').setup()

" Comando principal CORRIGIDO - usando "<args>" em vez de <f-args>
command! -nargs=? -complete=customlist,v:lua.require'pick-buffer'.buffer_completion B lua require('pick-buffer').buffer_command({args = "<args>"})
