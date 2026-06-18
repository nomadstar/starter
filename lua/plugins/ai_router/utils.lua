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
function M.read_local_context(path)
  local expanded = vim.fn.expand(path)
  if vim.fn.isdirectory(expanded) == 1 then
    local files = vim.fn.globpath(expanded, "**/*", 0, 1)
    local context = ""
    local max_files = 30
    local count = 0
    for _, f in ipairs(files) do
      if vim.fn.isdirectory(f) == 0 and not f:match("/%.git/") and not f:match("/node_modules/") and not f:match("/target/") and not f:match("%.jpg$") and not f:match("%.png$") then
        count = count + 1
        if count > max_files then
          context = context .. "\n\n--- [WARNING: TOO MANY FILES IN FOLDER, TRUNCATED] ---\n"
          break
        end
        local content = M.read_local_context(f)
        context = context .. content
      end
    end
    return context
  elseif vim.fn.filereadable(expanded) == 1 then
    local file = io.open(expanded, "r")
    if file then
      local content = file:read("*a")
      file:close()
      return "\n\n--- CONTENIDO DE " .. expanded .. " ---\n" .. content
    end
  end
  return ""
end

return M
