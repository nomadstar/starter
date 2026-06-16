local M = {}

local env_path = vim.fn.stdpath("config") .. "/.env"

local function load_env()
  local f = io.open(env_path, "r")
  if not f then return end
  for line in f:lines() do
    local eq_idx = line:find("=")
    if eq_idx then
      local key = line:sub(1, eq_idx - 1):match("^%s*(.-)%s*$")
      local val = line:sub(eq_idx + 1):match("^%s*(.-)%s*$")
      
      if val and val:sub(1,1) == '"' and val:sub(-1,-1) == '"' then
         val = val:sub(2, -2)
      end

      if key and val and key ~= "" then
        vim.fn.setenv(key, val)
      end
    end
  end
  f:close()
end

load_env()

function M.require_key(provider)
  local key_map = {
    openai = { env = "OPENAI_API_KEY", url = "https://platform.openai.com/api-keys" },
    anthropic = { env = "ANTHROPIC_API_KEY", url = "https://console.anthropic.com/settings/keys" },
    gemini = { env = "GEMINI_API_KEY", url = "https://aistudio.google.com/app/apikey" },
    openrouter = { env = "OPENROUTER_API_KEY", url = "https://openrouter.ai/keys" },
    together = { env = "TOGETHER_API_KEY", url = "https://api.together.xyz/settings/api-keys" }
  }
  
  local info = key_map[provider]
  if not info then return true end
  
  local current_key = vim.env[info.env]
  if current_key and current_key ~= "" then return true end
  
  vim.ui.input({
    prompt = "Falta " .. info.env .. " para " .. provider .. ". Obtenla en " .. info.url .. " | Ingresa la API Key: ",
  }, function(input)
    if input and input ~= "" then
      vim.fn.setenv(info.env, input)
      local f = io.open(env_path, "a")
      if f then
        f:write("\n" .. info.env .. "=\"" .. input .. "\"\n")
        f:close()
        vim.notify("Credencial de " .. provider .. " guardada de forma segura.", vim.log.levels.INFO)
      end
    else
      vim.notify("No se ingresó credencial para " .. provider, vim.log.levels.WARN)
    end
  end)
  
  return vim.env[info.env] ~= nil and vim.env[info.env] ~= ""
end

return M
