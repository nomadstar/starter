local M = {}

function M.get_env(var, default)
  local v = vim.env[var]
  if not v or v == "" then return default end
  return v
end

function M.get_local_models()
  local local_models_str = M.get_env("AGENT_LOCAL_MODEL", "llama3")
  local local_models = vim.split(local_models_str, ",")
  for i, m in ipairs(local_models) do
    local_models[i] = vim.trim(m)
  end
  return local_models
end

function M.is_valid_response(text)
  return text and vim.trim(text) ~= "" and not text:match("^%s*$")
end

function M.save_file_native(filename, content)
  local cwd = vim.fn.getcwd()
  local file_path = cwd .. "/" .. filename
  local dir = vim.fn.fnamemodify(file_path, ":h")

  if vim.fn.isdirectory(dir) == 0 then
    vim.fn.mkdir(dir, "p")
  end

  local file = io.open(file_path, "w")
  if file then
    file:write(content)
    file:close()
    return true
  else
    vim.schedule(function()
      vim.notify("Error guardando " .. file_path, vim.log.levels.ERROR)
    end)
    return false
  end
end

function M.jina_fetch(url, callback)
  local jina_url = "https://r.jina.ai/" .. url
  require("plenary.curl").get(jina_url, {
    headers = {
      ["Accept"] = "text/event-stream"
    },
    callback = function(res)
      if res.status == 200 then
        callback(res.body)
      else
        callback("ERROR Jina fetch: " .. res.status .. " " .. (res.body or ""))
      end
    end
  })
end

return M
