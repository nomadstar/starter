return {
  {
    "olimorris/codecompanion.nvim",
    dependencies = {
      "nvim-lua/plenary.nvim",
      "nvim-treesitter/nvim-treesitter",
    },
    keys = {
      { "<leader>ac", function()
          if vim.env.AI_ROUTER_MODE == "3" then
            require('plugins.ai_router.orchestrator').start_orchestration()
          else
            vim.cmd("CodeCompanionRouted")
          end
        end, desc = "AI Chat (Routed/Iterative)", mode = { "n", "v" } },
      { "<leader>ai", "<cmd>CodeCompanionRoutedInline<cr>", desc = "AI Inline (Routed)", mode = { "n", "v" } },
      { "<leader>af", "<cmd>AIRouterReportFailure<cr>", desc = "Report AI Failure (Fallback)", mode = "n" },
      { "<leader>am", "<cmd>lua require('plugins.ai_router.orchestrator').start_orchestration()<cr>", desc = "AI Multi-Agent (Cloud+Ollama)", mode = "n" },
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

        local system_prompt = "You are a helpful AI assistant."
        if vim.env.CAVEMAN_MODE == "true" then
          system_prompt = "Talk like caveman. Cut filler words. Use minimal grammar. Keep technical accuracy. Shortest possible output."
        end

        -- Configuración dinámica según el fallback
        local opts = {
          strategies = {
            chat = { adapter = best_provider },
            inline = { adapter = best_provider },
          },
          opts = {
            system_prompt = system_prompt,
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
        elseif best_provider == "openrouter" then
          opts.adapters = {
            openrouter = function()
              return require("codecompanion.adapters").extend("openai", {
                name = "openrouter",
                url = "https://openrouter.ai/api/v1/chat/completions",
                env = {
                  api_key = vim.env.OPENROUTER_API_KEY,
                },
                schema = {
                  model = {
                    default = "meta-llama/llama-3-8b-instruct",
                  }
                }
              })
            end,
          }
        elseif best_provider == "together" then
          opts.adapters = {
            together = function()
              return require("codecompanion.adapters").extend("openai", {
                name = "together",
                url = "https://api.together.xyz/v1/chat/completions",
                env = {
                  api_key = vim.env.TOGETHER_API_KEY,
                },
                schema = {
                  model = {
                    default = "meta-llama/Llama-3-8b-chat-hf",
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
      
      vim.api.nvim_create_user_command("NewTeleBot", function()
        require("plugins.ai_router.telegram").update_bot_commands()
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
