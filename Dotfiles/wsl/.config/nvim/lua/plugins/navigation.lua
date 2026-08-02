return {
  {
	'stevearc/oil.nvim',
	opts = { view_options = { show_hidden = true}},
	keys = { { '<leader>e', '<cmd>Oil<cr>', desc = 'File Browser'}},
  },  
  {
    "folke/snacks.nvim",
    priority = 1000,
    lazy = false,
    ---@type snacks.Config
    opts = {
      -- your configuration comes here
      -- or leave it empty to use the default settings
      -- refer to the configuration section below
      input = { enabled = true },
      picker = { enabled = true },
      notifier = { enabled = true },
    },
    keys = {
      { "<leader>b", function() Snacks.picker.buffers() end, desc = "Buffers" },
      { "<leader>s", function() Snacks.picker.grep() end, desc = "Search Text" },
      { "<leader>f", function() Snacks.picker.files() end, desc = "Find Files" },
      { "gd", function() Snacks.picker.lsp_definitions() end, desc = "Goto Definition" },
    },
  },
}
