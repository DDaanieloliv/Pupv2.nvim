# PupV2.nvim

A personal plugin that helps me switch between buffers in Neovim and handle them per working directory.
Whith a file search builtin ripgrep powered.


https://github.com/user-attachments/assets/bdd56b2b-2d5d-4578-8922-e381da5cded8



## Features


- Path-aware caching: Buffers are organized by project directory

- Persistent cache: Your buffer history survives Neovim sessions

- Automatic cleanup: Removes invalid buffers and maintains organization

- Last Buffer Swap: Jump to the previous buffer visited

- Buffer trail: Your last query is persisted in a stack

- FileSearche: Find your file in the current path

## Overview

The main motivation is to provide an "environment" with buffers that I often use in my projects.
Making it easier to navigate between them and search for them, and whith pick_file_system enter on buffer that have not yet been added.

## Dependecies

- This plugin use ripgrep to grep the files in file system.

 >_Ripgrep 'rg' is a fast, line-oriented search tool that recursively searches for a regular expression pattern in your current directory, while respecting .gitignore rules and ignoring hidden and binary files by default._

- You can chose your favorite package manager to install this tool, or use this git repository [ripgrep](https://github.com/BurntSushi/ripgrep).




- To use the telescope options like, <leader>ls you should using the plugin [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim).

## Installation

- Using Packer.nvim

```lua
use {
  'DDaanieloliv/Pupv2.nvim',
  config = function()
    require('pupV2').setup()
  end
}
```

- Using Lazy.nvim

```lua
{
  "DDaanieloliv/Pupv2.nvim",
  config = function()
    require("pupV2").setup({})
  end
}
```
**or**
```lua
  {
    "DDaanieloliv/Pupv2.nvim",
    opts = {
      style = {
        cursor_line = '#1c1a18',
      }
    }
  }
```

### How to start

- Use `:Mag` to open the buffer menu.<br>

### User interface

A floating window displays your buffers in chronological order. Features include:

- **Smart Positioning**: Appears at bottom-left corner for easy access
- **Visual Feedback**: Vertical bar indicates current input position  
- **Real-time Filtering**: Start typing to instantly filter buffers
- **Keyboard Navigation**: Multiple keybinding options for different workflows


   
### Usage cycle

- **Basic Navigation**:
  - `<C-n>` - Move selection down
  - `<C-p>` - Move selection up
  - `<Tab>` - Cycle through buffers
  - `<Enter>` | `<C-m>` - Open selected buffer
  - `<Esc>` - Close window
  - `<#>` - Open the pick_file_system window

- **Direct Access**:
  - `Alt+1` to `Alt+9` - Jump to buffer 1-9 directly 
  

## Default config


- Default configuration (customize as needed):

```lua
require('pupV2').setup({
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
})
```


## Keybindings


- Navigation

```Key	Action
<A-1> to <A-9>	Open buffer 1-9 directly
<leader>ls	    List all cached buffers in telescope
<leader>m      Open a float window to pick buffers added to the current path
<leader>d      Open a float window to pick every file in the current path
```

- Buffer Management


```Key	Action
<leader>q	  Close current buffer (smart)
<leader>[	  Move buffer backward in list
<leader>]	  Move buffer forward in list
<leader>x	  Clear current path buffers
<leader>r	  Remove last buffer from cache
<leader>cc	Clear entire buffer cache
<leader>la  Jump to previous buffer
```

- Floating Window Controls

```Key	Action
<C-j>	       Move selection down
<C-k>	       Move selection up
1-9	         Select buffer by number
TAB	         Cycle through buffers
Enter/<C-m>	 Confirm selection
ESC	         Close without selection

Type any letter	Real-time filtering
```

- Path Truncation

The plugin truncates long paths:

```lua
-- Example: 
-- Original: /home/user/projects/long-project-name/src/components/very-long-component-name.lua
-- Truncated: ~/proj...ong-project-name/src/components/very-long-component-name.lua
```

## Others Usages

- Command Mode

```vim
:Mag 3           " Open buffer 3
:Mag filename    " Open buffer by name
:Mag            " Show interactive picker
```

- API Access
```lua
local pick_buffer = require('pick-buffer')
```

```lua
-- Get all buffers with numbers
local buffers = pick_buffer.get_buffers_with_numbers()
```

```lua
-- Programmatic buffer selection
pick_buffer.buffer_command("3")
```
