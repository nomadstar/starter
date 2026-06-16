local M = {}

function M.get_models()
  local models = {}
  if M._cached_models and M._cache_time and (os.time() - M._cache_time < 300) then
    return M._cached_models
  end
  
  local cmd = vim.env.OLLAMA_CMD or "ollama"
  local handle = io.popen(cmd .. " list | tail -n +2 | awk '{print $1}' 2>/dev/null")
  if handle then
    local result = handle:read("*a")
    handle:close()
    if result then
      for model in result:gmatch("[^\r\n]+") do
        if model ~= "" then
          table.insert(models, model)
        end
      end
    end
  end
  
  if #models > 0 then
    M._cached_models = models
  else
    M._cached_models = {}
  end
  M._cache_time = os.time()
  
  return M._cached_models
end

return M
