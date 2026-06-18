local M = {}
local curl = require("plenary.curl")
local utils = require("plugins.ai_router.utils")
local metrics = require("plugins.ai_router.metrics")

_G.AI_ROUTER_ACTIVE_JOBS = _G.AI_ROUTER_ACTIVE_JOBS or {}
_G.AI_ROUTER_KILLED = false

function M.kill_all()
  _G.AI_ROUTER_KILLED = true
  utils.allow_sleep()
  for _, job in ipairs(_G.AI_ROUTER_ACTIVE_JOBS) do
    pcall(function() job:shutdown() end)
  end
  _G.AI_ROUTER_ACTIVE_JOBS = {}
end

function M.call_cloud(prompt, callback)
  local url = utils.get_env("AGENT_CLOUD_URL", "https://openrouter.ai/api/v1/chat/completions")
  local key = utils.get_env("OPENROUTER_API_KEY", "")
  local model_env = utils.get_env("AGENT_CLOUD_MODEL", "meta-llama/llama-3-8b-instruct")
  local models = vim.split(model_env, ",")

  if key == "" then
    vim.schedule(function()
      vim.notify("Falta OPENROUTER_API_KEY en .env para el Arquitecto Cloud.", vim.log.levels.ERROR)
    end)
    return
  end

  local system_prompt = "You are a helpful AI."
  local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
  system_prompt = system_prompt .. "\n" .. anti_lazy

  if vim.env.CAVEMAN_MODE == "true" then
    system_prompt = "Talk like caveman. Cut filler words. Use minimal grammar. Keep technical accuracy. Shortest possible output.\n" .. anti_lazy
  end

  local function try_model(index)
    local current_model = models[index]
    if not current_model then return end
    current_model = vim.trim(current_model)

    local body = vim.json.encode({
      model = current_model,
      messages = {
        { role = "system", content = system_prompt },
        { role = "user",   content = prompt },
      },
      temperature = 0.2,
      max_tokens = tonumber(utils.get_env("AGENT_MAX_OUTPUT_TOKENS", "4096")),
    })

    if _G.AI_ROUTER_KILLED then return callback("ERROR: Killed") end

    local job = curl.post(url, {
      body = body,
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. key,
      },
      callback = function(res)
        if res.status ~= 200 then
          local is_auth_error = (res.status == 401 or res.status == 403)
          local can_retry = not is_auth_error and index < #models

          if can_retry then
            vim.schedule(function()
              vim.notify(
                "Falló modelo " .. current_model .. " (HTTP " .. tostring(res.status) .. "), intentando con el siguiente...",
                vim.log.levels.WARN
              )
              try_model(index + 1)
            end)
          else
            vim.schedule(function()
              callback("ERROR Cloud (" .. current_model .. "): " .. tostring(res.status) .. " " .. tostring(res.body))
            end)
          end
          return
        end

        local ok, data = pcall(vim.json.decode, res.body)
        if not ok or not data then
          vim.schedule(function()
            callback("ERROR Cloud: JSON decode failed")
          end)
          return
        end

        if data.usage and data.usage.total_tokens then
          pcall(function()
            metrics.add_usage("openrouter", data.usage.total_tokens)
          end)
        end

        local text = data.choices
          and data.choices[1]
          and data.choices[1].message
          and data.choices[1].message.content
          or "ERROR: Unexpected API response"
        vim.schedule(function()
          callback(text)
        end)
      end,
      on_error = function(err)
        vim.schedule(function()
          if index < #models then
            ui.log("\n> ⚠️ **[Sistema]** Fallo de red con " .. current_model .. ". Intentando con fallback...", vim.log.levels.WARN)
            try_model(index + 1)
          else
            callback("ERROR Cloud Network: " .. vim.inspect(err))
          end
        end)
      end,
      timeout = 300000, -- 5 minutos
    })
    table.insert(_G.AI_ROUTER_ACTIVE_JOBS, job)
  end

  try_model(1)
end

function M.call_ollama(model, prompt, callback)
  local url = utils.get_env("OLLAMA_HOST", "http://localhost:11434") .. "/api/chat"

  local system_prompt = "You are an Expert Senior Developer. Your task is to write exhaustive, production-grade, and deeply detailed code/documentation."
  local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
  system_prompt = system_prompt .. "\n" .. anti_lazy

  local messages = {
    { role = "system", content = system_prompt },
    { role = "user",   content = prompt },
  }

  local accumulated_text = ""
  local continuation_count = 0
  local max_continuations = 5 

  local function send_request()
    local body = vim.json.encode({
      model = model,
      messages = messages,
      stream = true,
      temperature = 0.1,
      options = {
        num_predict = tonumber(utils.get_env("AGENT_LOCAL_MAX_PREDICT", "4096")),
        num_ctx = tonumber(utils.get_env("AGENT_LOCAL_MAX_CTX", "16384")),
      },
    })

    if _G.AI_ROUTER_KILLED then return callback("ERROR: Killed") end

    local job = curl.post(url, {
      body = body,
      headers = { ["Content-Type"] = "application/json" },
      stream = function(err, data)
        if err or not data then return end
        
        vim.schedule(function()
          local lines = vim.split(data, "\n")
          for _, line in ipairs(lines) do
            if line ~= "" then
              local ok, json = pcall(vim.json.decode, line)
              if ok and json.message and json.message.content then
                accumulated_text = accumulated_text .. json.message.content
                require("plugins.ai_router.ui").log_stream(json.message.content)
                if json.done and json.done_reason == "length" then
                   if continuation_count < max_continuations then
                     continuation_count = continuation_count + 1
                     table.insert(messages, { role = "user", content = "Continue EXACTLY from where you left off. Do not repeat anything. Output ONLY the continuation of the code or markdown block." })
                     send_request()
                     return
                   end
                end
              end
            end
          end
        end)
      end,
      callback = function(res)
        if res.status ~= 200 then
          vim.schedule(function()
            callback("ERROR Ollama: " .. tostring(res.status) .. " " .. tostring(res.body))
          end)
          return
        end

        table.insert(messages, { role = "assistant", content = accumulated_text })

        -- The stream callback handles the length continuation, so here we just return the final text
        vim.schedule(function()
          require("plugins.ai_router.ui").log_stream("\n")
          callback(accumulated_text)
        end)
      end,
      on_error = function(err)
        vim.schedule(function()
          callback("ERROR Ollama Network: " .. vim.inspect(err))
        end)
      end,
      timeout = 3600000, -- 1 hora (Ollama local puede ser muy lento)
    })
    table.insert(_G.AI_ROUTER_ACTIVE_JOBS, job)
  end

  send_request()
end

return M
