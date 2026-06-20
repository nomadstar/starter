local M = {}

local state = {
  providers = {
    anthropic = { exhausted = false },
    openai = { exhausted = false },
    gemini = { exhausted = false },
    openrouter = { exhausted = false },
    together = { exhausted = false }
  }
}

local session_tokens = 0
local budget_killed = false

function M.get_best_provider()
  local mode = vim.env.AI_ROUTER_MODE or "4"
  if mode == "2" then return "ollama" end

  local ordered = {"anthropic", "openai", "gemini", "openrouter", "together"}
  
  for _, p in ipairs(ordered) do
    if state.providers[p] and not state.providers[p].exhausted then
      if vim.env[string.upper(p) .. "_API_KEY"] then
         return p
      end
    end
  end
  
  if mode == "1" then return nil end
  
  local ollama = require("plugins.ai_router.ollama")
  local ollama_models = ollama.get_models()
  if #ollama_models > 0 then
    return "ollama", ollama_models[1]
  end
  
  return nil
end

function M.add_usage(provider, tokens)
  if budget_killed then return end
  if not tokens then return end
  
  session_tokens = session_tokens + tonumber(tokens)
  local budget_str = require("plugins.ai_router.utils").get_env("AGENT_TOKEN_BUDGET", "")
  if budget_str ~= "" then
    local budget = tonumber(budget_str)
    if budget and session_tokens > budget then
      budget_killed = true
      require("plugins.ai_router.ui").log("\n> 🛑 **[Seguridad]** Presupuesto de tokens excedido (" .. session_tokens .. " > " .. budget .. "). Apagando sistema.")
      require("plugins.ai_router.api").kill_all()
    end
  end
end

function M.report_failure(provider)
  if not state.providers[provider] then return end
  
  state.providers[provider].exhausted = true
  
  local next_provider = M.get_best_provider()
  if next_provider == "ollama" then
    vim.notify("Falla con " .. provider .. ", intentando con Ollama", vim.log.levels.WARN)
  elseif next_provider == nil then
    vim.notify("No hay inteligencias artificiales disponibles", vim.log.levels.ERROR)
  else
    vim.notify("Falla con " .. provider .. ", entregando contexto a " .. next_provider, vim.log.levels.WARN)
  end
end

function M.reset_credits(provider)
  if state.providers[provider] then
    state.providers[provider].exhausted = false
    vim.notify("Estado reiniciado para " .. provider, vim.log.levels.INFO)
  end
end

return M
