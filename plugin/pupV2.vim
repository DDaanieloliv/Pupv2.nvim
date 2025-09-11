" PupV2.nvim - buffer manager with persistent cache
" Last Change: 2025
" Maintainer: Daniel Oliveira daniel0333v@gamil.com
" License: MIT

if exists('g:loaded_pick_buffer')
    finish
endif
let g:loaded_pick_buffer = 1

" Restauração do cpo para compatibilidade
let s:save_cpo = &cpo
set cpo&vim

lua require('pupV2').setup()

" Comando principal
command! -nargs=? -complete=customlist,v:lua.require'pupV2'.buffer_completion B lua require('pupV2').buffer_command(<q-args>)

" Restaura cpo
let &cpo = s:save_cpo
unlet s:save_cpo

