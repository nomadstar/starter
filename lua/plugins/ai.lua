return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", "<cmd>CodeCompanionRouted<cr>", desc = "AI Chat (Routed)", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>CodeCompanionRoutedInline<cr>", desc = "AI Inline (Routed)", mode = { "n", "v" } },
      { "<leader>af", "<cmd>AIRouterReportFailure<cr>", desc = "Report AI Failure (Fallback)", mode = "n" },
    },
    config = function()
      local credentials = require("plugins.ai_router.credentials")
      local metrics = require("plugins.ai_router.metrics")

      local function ensure_provider()
        local best_provider, model = metrics.get_best_provider()
        if not best_provider then
          vim.notify("No hay inteligencias artificiales disponibles", vim.log.levels.ERROR)
          return nil, nil
        end

        if best_provider ~= "ollama" then
          if not credentials.require_key(best_provider) then
            return nil, nil
          end
        end

        -- Configuración dinámica según el fallback
        local opts = {
          strategies = {
            chat = { adapter = best_provider },
            inline = { adapter = best_provider },
          },
        }

        if best_provider == "ollama" and model then
          opts.adapters = {
            ollama = function()
              return require("codecompanion.adapters").extend("ollama", {
                name = "ollama",
                schema = {
                  model = {
                    default = model,
                  }
                }
              })
            end,
          }
        end

        require("codecompanion").setup(opts)
        return best_provider, model
      end

      -- Comandos para interactuar con la IA de forma segura
      vim.api.nvim_create_user_command("CodeCompanionRouted", function(opts)
        local provider = ensure_provider()
        if provider then
          -- Estimación cruda: Sumamos 500 tokens por cada chat nuevo 
          -- (En una implementación real se intercepta el hook HTTP de respuesta)
          metrics.add_usage(provider, 500)
          vim.cmd("CodeCompanionChat " .. opts.args)
        end
      end, { nargs = "*" })

      vim.api.nvim_create_user_command("CodeCompanionRoutedInline", function(opts)
        local provider = ensure_provider()
        if provider then
          metrics.add_usage(provider, 200)
          vim.cmd("CodeCompanion " .. opts.args)
        end
      end, { nargs = "*" })

      vim.api.nvim_create_user_command("AIRouterReportFailure", function()
        local provider = metrics.get_best_provider()
        if provider then
          metrics.report_failure(provider)
        end
      end, {})
      
      -- Setup base
      require("codecompanion").setup({
         display = {
            chat = { show_settings = true }
         }
      })
    end,
  }
}
