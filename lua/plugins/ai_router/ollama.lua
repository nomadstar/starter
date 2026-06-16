local M = {}

function M.get_models()
  local models = {}
  if M._cached_models then
    return M._cached_models
  end
  
  local handle = io.popen("ollama list | tail -n +2 | awk '{print $1}' 2>/dev/null")
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
    -- Solo imprimimos advertencia si no hay red tampoco, pero aquí es la capa de ollama.
    M._cached_models = {}
  end
  
  return M._cached_models
end

return M
