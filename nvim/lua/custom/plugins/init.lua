-- You can add your own plugins here or in other files in this directory!
--  I promise not to create any merge conflicts in this directory :)
--
-- See the kickstart.nvim README for more information
return {
  {
    'akinsho/toggleterm.nvim',
    version = '*',
    config = true,
  },
  {
    'nvim-treesitter/nvim-treesitter-context',
    event = 'BufReadPre',
    opts = {
      mode = 'cursor',
      max_lines = 3,
    },
  },
  { 'sainnhe/gruvbox-material' },
  {
    'ray-x/go.nvim',
    dependencies = {
      'ray-x/guihua.lua',
      'neovim/nvim-lspconfig',
    },
    opts = {
      lsp_codelens = false, -- the fix for your error
      -- other options you want
    },
    config = function(_, opts)
      require('go').setup(opts)

      local format_sync_grp = vim.api.nvim_create_augroup('GoFormat', {})
      vim.api.nvim_create_autocmd('BufWritePre', {
        pattern = '*.go',
        callback = function()
          require('go.format').goimports()
        end,
        group = format_sync_grp,
      })
    end,
    event = { 'CmdlineEnter' },
    ft = { 'go', 'gomod' },
    build = ':lua require("go.install").update_all_sync()',
  },
  {
    'dmtrKovalenko/fff.nvim',
    build = function()
      -- this will download prebuild binary or try to use existing rustup toolchain to build from source
      -- (if you are using lazy you can use gb for rebuilding a plugin if needed)
      require('fff.download').download_or_build_binary()
    end,
    -- if you are using nixos
    -- build = "nix run .#release",
    opts = {},
    lazy = false,
    keys = {
      {
        '<leader>ff',
        function()
          require('fff').find_files()
        end,
        desc = '[F]ind [F]iles',
      },
      {
        '<leader>fg',
        function()
          require('fff').live_grep()
        end,
        desc = '[F]ind by [G]rep',
      },
      {
        '<leader>fz',
        function()
          require('fff').live_grep { grep = { modes = { 'fuzzy', 'plain' } } }
        end,
        desc = '[F]ind fu[z]zy grep',
      },
      {
        '<leader>fc',
        function()
          require('fff').live_grep { query = vim.fn.expand '<cword>' }
        end,
        desc = '[F]ind [C]urrent word',
      },
    },
  },
  { 'https://github.com/rebelot/kanagawa.nvim' },
  {
    'scottmckendry/cyberdream.nvim',
    lazy = false,
    priority = 1000,
  },

  {
    'kdheepak/lazygit.nvim',
    cmd = { 'LazyGit', 'LazyGitConfig', 'LazyGitCurrentFile', 'LazyGitFilter', 'LazyGitFilterCurrentFile' },
    dependencies = { 'nvim-lua/plenary.nvim' },
    keys = {
      { '<leader>gg', '<cmd>LazyGit<cr>', desc = '[G]it: Lazy[G]it' },
      { '<leader>gf', '<cmd>LazyGitCurrentFile<cr>', desc = '[G]it: current [F]ile history' },
    },
  },

  {
    'Saecki/crates.nvim',
    event = { 'BufRead Cargo.toml' },
    opts = {
      completion = { cmp = { enabled = false }, crates = { enabled = true } },
      lsp = { enabled = true, actions = true, completion = true, hover = true },
    },
  },

  {
    'folke/flash.nvim',
    event = 'VeryLazy',
    opts = {},
    keys = {
      {
        's',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').jump()
        end,
        desc = 'Flash',
      },
      {
        'S',
        mode = { 'n', 'x', 'o' },
        function()
          require('flash').treesitter()
        end,
        desc = 'Flash Treesitter',
      },
      {
        'r',
        mode = 'o',
        function()
          require('flash').remote()
        end,
        desc = 'Remote Flash',
      },
      {
        'R',
        mode = { 'o', 'x' },
        function()
          require('flash').treesitter_search()
        end,
        desc = 'Treesitter Search',
      },
    },
  },

  {
    'kevinhwang91/nvim-ufo',
    dependencies = { 'kevinhwang91/promise-async' },
    event = 'BufReadPost',
    opts = {
      provider_selector = function()
        return { 'treesitter', 'indent' }
      end,
    },
    keys = {
      {
        'zR',
        function()
          require('ufo').openAllFolds()
        end,
        desc = 'Open all folds',
      },
      {
        'zM',
        function()
          require('ufo').closeAllFolds()
        end,
        desc = 'Close all folds',
      },
      {
        'zK',
        function()
          local winid = require('ufo').peekFoldedLinesUnderCursor()
          if not winid then
            vim.lsp.buf.hover()
          end
        end,
        desc = 'Peek fold / hover',
      },
    },
  },

  {
    'folke/noice.nvim',
    event = 'VeryLazy',
    dependencies = {
      'MunifTanjim/nui.nvim',
      'rcarriga/nvim-notify',
    },
    opts = {
      lsp = {
        override = {
          ['vim.lsp.util.convert_input_to_markdown_lines'] = true,
          ['vim.lsp.util.stylize_markdown'] = true,
          ['cmp.entry.get_documentation'] = true,
        },
      },
      presets = {
        bottom_search = true,
        command_palette = true,
        long_message_to_split = true,
        inc_rename = false,
        lsp_doc_border = true,
      },
    },
  },
  {
    'nvim-java/nvim-java',
    config = function()
      require('java').setup()
      vim.lsp.enable 'jdtls'
    end,
  },
}
