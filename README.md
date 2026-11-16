# manscope.nvim

Search man pages the way Telescope searches files: the catalog stays on the left, the formatted page stays on the right.

```
┌ Man pages ──────────────┐ ┌ java(1) ─────────────────────────┐
│ > java                  │ │ NAME                             │
│ java                (1) │ │      java - launch a Java app…   │
│ javac               (1) │ │ SYNOPSIS                         │
│ javadoc             (1) │ │      java [options] mainclass    │
└─────────────────────────┘ └──────────────────────────────────┘
```

That split is Telescope's horizontal layout (`mirror` off). It fits man pages because the list is a catalog and the page is a document: you fuzzy-find a page, read it in the preview, then open it.

`:Telescope man_pages` is the same family of UI, with two limits this plugin does not keep. It only lists section 1 unless you pass `sections`, and its fuzzy match uses the page name only. Manscope lists every section, matches the name, the section, and the apropos description, and can search inside the page you are looking at.

## Requirements

- Neovim 0.9 or newer, and a telescope.nvim build that supports it. The current telescope.nvim release requires Neovim 0.11
- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) and [plenary.nvim](https://github.com/nvim-lua/plenary.nvim)
- `man` and `apropos` on `PATH`
- `col` is optional. When it is present, the preview strips nroff overstrike

## Install

### lazy.nvim

```lua
{
  "Aissa-cmd/manscope.nvim",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  cmd = "Manscope",
  keys = {
    { "<leader>mm", "<cmd>Manscope<cr>", desc = "Search man pages" },
    { "<leader>mw", "<cmd>Manscope cword<cr>", desc = "Man page for word under cursor" },
  },
  opts = {},
}
```

### packer

```lua
use({
  "Aissa-cmd/manscope.nvim",
  requires = {
    "nvim-lua/plenary.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function()
    require("manscope").setup()
  end,
})
```

Calling `setup` is optional. The defaults already put search on the left and the page on the right.

## Use

```vim
:Manscope                  " search every section
:Manscope printf           " same picker, prompt filled with "printf"
:Manscope cword            " prompt filled with the word under the cursor
:Manscope section 3        " start in section 3 (also matches 3perl, 3posix, …)
:Manscope section 3 printf
:Manscope history
:Manscope headings         " headings of the man page in the current window
:Manscope headings java(1)
:Manscope lines            " search the lines of the current man page
:Manscope lines 1 java
```

From Telescope:

```vim
:Telescope manscope
:Telescope manscope history
:Telescope manscope headings
:Telescope manscope lines
```

```lua
require("telescope").load_extension("manscope")
```

Inside the catalog:

| Key | Action |
| --- | --- |
| `<CR>` | Open the page with `:Man` |
| `<C-x>` | Open in a horizontal split |
| `<C-v>` | Open in a vertical split |
| `<C-t>` | Open in a new tab |
| `<M-s>` | Cycle the section filter (all, 1, 2, … 9) |
| `<M-h>` | Headings of the selected page, preview jumps to the heading |
| `<M-l>` | Search the lines of the selected page |

`<C-u>` and `<C-d>` still scroll the preview. The section filter is also shown in the results title (`All sections`, `Section 3`, …).

Headings and line search use the same left/right layout. The preview is the page, scrolled to the heading or line. Opening one of those entries runs `:Man` and jumps to that text.

Recent pages are stored in `stdpath("data")/manscope/history.json`.

## Setup

```lua
require("manscope").setup({
  -- Sections in the <M-s> cycle. nil keeps every section apropos returns.
  -- "1" also matches "1ssl" and "1p". It does not match section "10".
  sections = nil,
  section_match = "prefix", -- or "exact"
  open = "current", -- "current" | "horizontal" | "vertical" | "tab"
  man_cmd = nil, -- e.g. { "apropos", "." }
  layout = {
    width = 0.92,
    height = 0.88,
    preview_width = 0.58,
    prompt_position = "top",
    mirror = false, -- true swaps the sides: preview left, search right
  },
  history = {
    enabled = true,
    limit = 50,
    path = nil,
  },
  mappings = {
    cycle_section = "<M-s>",
    headings = "<M-h>",
    lines = "<M-l>",
  },
})
```

The same table can live under `extensions.manscope` in `telescope.setup`. An explicit `layout_strategy` passed to `:Telescope manscope` still overrides this picker.

`:checkhealth manscope` reports whether `man`, `apropos`, `col`, and Telescope are available.

## License

MIT
