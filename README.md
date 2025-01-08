# allure-go.nvim

A plugin wrapper for [allure-go](https://github.com/ozontech/allure-go) and [Allure Report](https://allurereport.org/docs/install-for-macos/).

## Features
- Runs allure serve when tests fail
- Runs a single test under the cursor
- Updates build tags

## 📦 Installation
1. Install dependencies:
   ```
   brew install allure
   ```

2. Install the plugin via your favorite package manager (e.g., vim-plug, packer.nvim, etc.):
   ```lua
   -- lazy.nvim
   {
      "Alexandersfg4/allure-go.nvim",
      opts = {},
      keys = {
         -- Allure keymaps
         { "<leader>tr", "<cmd>lua require('allure-go').check_and_run_allure()<cr>", desc = "Run allure serve" },
         { "<leader>ts", "<cmd>lua require('allure-go').stop_allure()<cr>",          desc = "Stop allure serve" },
         { "<leader>tf", "<cmd>lua require('allure-go').run_go_test()<cr>",          desc = "Run test under cursor" },
         { "<leader>ta", "<cmd>lua require('allure-go').run_go_test_all()<cr>",      desc = "Run all tests" },
         { "<leader>tp", "<cmd>lua require('allure-go').stop_tests()<cr>",           desc = "Stop currently running test" },
         { "<leader>tc", "<cmd>lua require('allure-go').change_tag()<cr>",           desc = "Change tag" },
      },
   }
   ```

3. Setup the plugin in your `init.lua`. (This step is not needed with lazy.nvim if `opts` is set as above.)
   ```lua
   require("allure-go").setup()
   ```

## Troubleshooting
- If you encounter issues, ensure that your dependencies are correctly installed and updated.

