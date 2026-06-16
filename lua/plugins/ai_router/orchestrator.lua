local M = {}
local curl = require("plenary.curl")

local function get_env(var, default)
  local v = vim.env[var]
  if not v or v == "" then return default end
  return v
end

local function call_cloud(prompt, callback)
  local url = get_env("AGENT_CLOUD_URL", "https://openrouter.ai/api/v1/chat/completions")
  local key = get_env("OPENROUTER_API_KEY", "")
  local model_env = get_env("AGENT_CLOUD_MODEL", "meta-llama/llama-3-8b-instruct")
  local models = vim.split(model_env, ",")

  if key == "" then
     vim.schedule(function()
        vim.notify("Falta OPENROUTER_API_KEY en .env para el Arquitecto Cloud.", vim.log.levels.ERROR)
     end)
     return
  end

  local system_prompt = "You are a helpful AI."
  if vim.env.CAVEMAN_MODE == "true" then
    system_prompt = "Talk like caveman. Cut filler words. Use minimal grammar. Keep technical accuracy. Shortest possible output."
  end

  local function try_model(index)
    local current_model = models[index]
    if not current_model then return end
    current_model = vim.trim(current_model)

    local body = vim.json.encode({
      model = current_model,
      messages = {
        { role = "system", content = system_prompt },
        { role = "user", content = prompt }
      },
      temperature = 0.2
    })

    curl.post(url, {
      body = body,
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. key
      },
      callback = function(res)
        if res.status ~= 200 then
          if (res.status == 401 or res.status == 403 or res.status == 429) then
            vim.schedule(function() callback("ERROR Cloud (" .. current_model .. "): " .. res.status .. " " .. res.body) end)
            return
          end

          if index < #models then
            vim.schedule(function()
              vim.notify("Falló modelo " .. current_model .. " (" .. res.status .. "), intentando con el siguiente...", vim.log.levels.WARN)
              try_model(index + 1)
            end)
          else
            vim.schedule(function() callback("ERROR Cloud (" .. current_model .. "): " .. res.status .. " " .. res.body) end)
          end
          return
        end
        local data = vim.json.decode(res.body)
        local text = data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content or "Error: Unexpected API response"
        vim.schedule(function() callback(text) end)
      end
    })
  end

  try_model(1)
end

local function call_ollama(prompt, callback)
  local url = get_env("OLLAMA_HOST", "http://localhost:11434") .. "/api/chat"
  local model = get_env("AGENT_LOCAL_MODEL", "llama3")

  local system_prompt = "You are a helpful AI."
  if vim.env.CAVEMAN_MODE == "true" then
    system_prompt = "Talk like caveman. Cut filler words. Use minimal grammar. Keep technical accuracy. Shortest possible output."
  end

  local body = vim.json.encode({
    model = model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = prompt }
    },
    stream = false,
    temperature = 0.1
  })

  curl.post(url, {
    body = body,
    headers = { ["Content-Type"] = "application/json" },
    callback = function(res)
      if res.status ~= 200 then
        vim.schedule(function() callback("ERROR Ollama: " .. res.status .. " " .. res.body) end)
        return
      end
      local data = vim.json.decode(res.body)
      local text = data.message.content
      vim.schedule(function() callback(text) end)
    end
  })
end

function M.start_orchestration()
  vim.ui.input({ prompt = "Tarea para Agentes (Ej: Script en python para...): " }, function(user_prompt)
    if not user_prompt or user_prompt == "" then return end

    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_name(buf, "AI_Orchestrator_" .. math.random(1000))
    vim.bo[buf].filetype = "markdown"
    
    local function log(msg)
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(msg, "\n"))
      local count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(win, {count, 0})
    end

    log("# ORQUESTADOR MULTI-AGENTE INICIADO")
    log("**Meta:** " .. user_prompt)
    log("---\n")
    
    local max_iter = tonumber(get_env("AGENT_MAX_ITERATIONS", "3"))
    local current_iter = 1
    
    local architecture_prompt = "You are an AI Architect. User wants: " .. user_prompt .. "\nProvide ONLY a concise technical plan and pseudocode to solve this. Do not write full code. Minimize your response to save tokens."
    
    log("> **[Arquitecto Cloud]** Analizando petición para minimizar tokens...\n")
    
    local function execute_architecture(arch_response)
      log("> **[Arquitecto] Plan generado:**\n" .. arch_response)
      log("\n---\n")
      
      local function do_iteration(comments)
         log("> **[Ollama Local (Turboquant)]** Iteración " .. current_iter .. "/" .. max_iter .. ". Escribiendo código...\n")
         local ollama_prompt = "You are a Developer. Write the full code for this plan:\n" .. arch_response
         if comments then
            ollama_prompt = ollama_prompt .. "\n\nFix the code based on the Architect's review:\n" .. comments
         end
         ollama_prompt = ollama_prompt .. "\nOutput ONLY the raw code inside standard markdown blocks (```). Do not include any other text."

         call_ollama(ollama_prompt, function(code_response)
            if code_response:match("^ERROR") then
               log(code_response)
               return
            end
            
            log("> **[Ollama Local]** Código completado. Solicitando revisión iterativa...\n")
            
            local review_prompt = "You are the Architect. Review this code against your plan:\n\nCODE:\n" .. code_response .. "\n\nPLAN:\n" .. arch_response .. "\n\nIf the code works perfectly and implements the plan, reply EXACTLY with the word 'APPROVED' (nothing else). If it has bugs or issues, reply with a very concise list of fixes."
            
            local function handle_review(review_response)
               if review_response:match("APPROVED") then
                  log("### ✅ [Arquitecto] Código APROBADO en la iteración " .. current_iter .. "!")
                  log("\n--- CÓDIGO FINAL ---\n" .. code_response)
                  
                  local raw_code = code_response:match("```[%w]*\n(.-)```") or code_response
                  vim.fn.setreg("+", raw_code)
                  log("\n> 📋 **El código final ha sido copiado a tu portapapeles (+).**")
               else
                  log("### ❌ [Arquitecto] Revisión fallida. Comentarios:\n" .. review_response)
                  current_iter = current_iter + 1
                  if current_iter > max_iter then
                     log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado. Abortando.")
                     log("\n--- ÚLTIMO CÓDIGO ---\n" .. code_response)
                  else
                     log("\n---\n")
                     do_iteration(review_response)
                  end
               end
            end

            call_cloud(review_prompt, function(review_response)
               if review_response:match("^ERROR") then
                  log(review_response)
                  log("\n> ⚠️ **[Sistema]** Falló el Revisor Cloud. Iniciando fallback a Ollama...\n")
                  call_ollama(review_prompt, function(fallback_review)
                     if fallback_review:match("^ERROR") then
                        log(fallback_review)
                        return
                     end
                     handle_review(fallback_review)
                  end)
                  return
               end
               handle_review(review_response)
            end)
         end)
      end
      
      do_iteration(nil)
    end

    call_cloud(architecture_prompt, function(arch_response)
      if arch_response:match("^ERROR") then
         log(arch_response)
         log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud. Iniciando fallback a Ollama...\n")
         call_ollama(architecture_prompt, function(fallback_arch)
             if fallback_arch:match("^ERROR") then
                 log(fallback_arch)
                 return
             end
             execute_architecture(fallback_arch)
         end)
         return
      end
      execute_architecture(arch_response)
    end)
  end)
end

return M
