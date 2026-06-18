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

function M.get_recent_file_contents(files, current_index, max_files)
  local context = ""
  if current_index <= 1 then return context end
  
  local start_idx = math.max(1, current_index - max_files)
  local approved_files = {}
  
  for i = start_idx, current_index - 1 do
    local filepath = vim.fn.getcwd() .. "/" .. files[i]
    local file = io.open(filepath, "r")
    if file then
      local content = file:read("*a")
      file:close()
      table.insert(approved_files, "### [ARCHIVO APROBADO PREVIAMENTE] " .. files[i] .. "\n```\n" .. content .. "\n```\n")
    else
      table.insert(approved_files, "### [ARCHIVO APROBADO PREVIAMENTE] " .. files[i] .. "\n(Contenido no disponible en disco)\n")
    end
  end
  
  if #approved_files > 0 then
    context = "\n\n=================================\n"
    context = context .. "[CRÍTICO - MEMORIA ITERATIVA]: Te proporciono el contenido EXACTO de los últimos " .. #approved_files .. " archivos que ya fueron generados exitosamente. Úsalos SOLO como contexto para mantener la continuidad, nomenclatura y el hilo conductor. NO los modifiques ni los repitas. Enfócate ÚNICAMENTE en el nuevo archivo solicitado.\n\n"
    context = context .. table.concat(approved_files, "\n")
  end
  
  return context
end

local sleep_job = nil

function M.prevent_sleep()
  if sleep_job then return end
  if vim.fn.executable("systemd-inhibit") == 1 then
    local Job = require("plenary.job")
    sleep_job = Job:new({
      command = "systemd-inhibit",
      args = { "--what=sleep:idle", "--why=AiRouter Orchestration", "sleep", "31536000" },
      on_exit = function()
        sleep_job = nil
      end,
    })
    sleep_job:start()
  end
end

function M.allow_sleep()
  if sleep_job then
    pcall(function() sleep_job:shutdown() end)
    sleep_job = nil
  end
end

function M.get_system_status(callback)
  local script = [[
cpu_usage=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
gpu_info=$(nvidia-smi --query-gpu=utilization.gpu,memory.used --format=csv,noheader 2>/dev/null || echo "No GPU")
ollama_usage=$(ps aux | grep "[o]llama" | awk '{cpu+=$3; mem+=$4} END {print "CPU: "cpu"% RAM: "mem"%"}')
echo "CPU Global: $cpu_usage%"
echo "GPU: $gpu_info"
echo "Ollama: $ollama_usage"
  ]]
  local Job = require("plenary.job")
  Job:new({
    command = "bash",
    args = { "-c", script },
    on_exit = function(j, return_val)
      local result = table.concat(j:result(), "\n")
      local orchestration_state = "Inactiva"
      if _G.AI_ROUTER_ACTIVE_JOBS and #_G.AI_ROUTER_ACTIVE_JOBS > 0 then
        orchestration_state = "Activa (" .. #_G.AI_ROUTER_ACTIVE_JOBS .. " jobs)"
      end
      
      local status_msg = "📊 **Estado del Sistema:**\n\n"
        .. result .. "\n"
        .. "Orquestación: " .. orchestration_state
      
      vim.schedule(function()
        callback(status_msg)
      end)
    end,
  }):start()
end

return M
