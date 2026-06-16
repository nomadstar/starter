local M = {}

local state_path = vim.fn.stdpath("data") .. "/ai_metrics.json"
local state = {
  providers = {
    anthropic = { max_tokens = 50000, current_usage = 0, recent_failures = {} },
    openai = { max_tokens = 50000, current_usage = 0, recent_failures = {} },
    gemini = { max_tokens = 50000, current_usage = 0, recent_failures = {} },
    openrouter = { max_tokens = 50000, current_usage = 0, recent_failures = {} },
    together = { max_tokens = 50000, current_usage = 0, recent_failures = {} }
  }
}

local function load_state()
  local f = io.open(state_path, "r")
  if f then
    local content = f:read("*a")
    f:close()
    local ok, parsed = pcall(vim.json.decode, content)
    if ok and parsed then 
      -- Merge for any new providers
      for k, v in pairs(parsed.providers or {}) do
        if state.providers[k] then
          state.providers[k] = v
        end
      end
    end
  end
end

local function save_state()
  local f = io.open(state_path, "w")
  if f then
    f:write(vim.json.encode(state))
    f:close()
  end
end

load_state()

function M.get_best_provider()
  local mode = vim.env.AI_ROUTER_MODE or "4"
  
  if mode == "2" then
    return "ollama"
  end

  local ordered = {"anthropic", "openai", "gemini", "openrouter", "together"}
  
  for _, p in ipairs(ordered) do
    local p_state = state.providers[p]
    if p_state then
      if vim.env[string.upper(p) .. "_API_KEY"] and p_state.current_usage < p_state.max_tokens then
         return p
      end
    end
  end
  
  if mode == "1" then
    return nil -- No fallback to local in Full Cloud mode
  end
  
  local ollama = require("plugins.ai_router.ollama")
  local ollama_models = ollama.get_models()
  if #ollama_models > 0 then
    return "ollama", ollama_models[1]
  end
  
  return nil
end

function M.add_usage(provider, tokens)
  if state.providers[provider] then
    state.providers[provider].current_usage = state.providers[provider].current_usage + tokens
    save_state()
  end
end

function M.report_failure(provider)
  if not state.providers[provider] then return end
  local p_state = state.providers[provider]
  
  local failed_at = p_state.current_usage
  
  -- Regla 1: Estimar hacia arriba
  if failed_at > p_state.max_tokens then
    p_state.max_tokens = failed_at
    p_state.recent_failures = {}
  else
    -- Regla 2 y 3: Dos fallas consecutivas antes del max_tokens
    table.insert(p_state.recent_failures, failed_at)
    if #p_state.recent_failures >= 2 then
      local val1 = p_state.recent_failures[#p_state.recent_failures - 1]
      local val2 = p_state.recent_failures[#p_state.recent_failures]
      
      if val1 <= p_state.max_tokens and val2 <= p_state.max_tokens then
        if val1 == val2 then
          p_state.max_tokens = val1
        else
          p_state.max_tokens = math.floor((val1 + val2) / 2)
        end
      end
      p_state.recent_failures = {}
    end
  end
  
  -- Reseteamos el usage para el nuevo ciclo simulado y obligar fallback si queremos que salte temporalmente
  -- Pero en realidad el limit es total. Si falló, la "cuota" está llena hasta que hagamos un comando manual de "reset credits"
  -- Así que subimos artificialmente current_usage al max_tokens para que fallback sea definitivo hasta que se haga reset
  p_state.current_usage = p_state.max_tokens 
  save_state()
  
  local next_provider = M.get_best_provider()
  if next_provider == "ollama" then
    vim.notify("Creditos de " .. provider .. " acabados, intentando con Ollama", vim.log.levels.WARN)
  elseif next_provider == nil then
    vim.notify("No hay inteligencias artificiales disponibles", vim.log.levels.ERROR)
  else
    vim.notify("Creditos de " .. provider .. " acabados, entregando contexto a " .. next_provider, vim.log.levels.WARN)
  end
end

function M.reset_credits(provider)
  if state.providers[provider] then
    state.providers[provider].current_usage = 0
    save_state()
    vim.notify("Creditos reiniciados para " .. provider, vim.log.levels.INFO)
  end
end

return M
