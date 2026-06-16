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
          if (res.status == 401 or res.status == 403) then
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
        local text = data.choices and data.choices[1] and data.choices[1].message and data.choices[1].message.content or "ERROR: Unexpected API response"
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

local function start_attention_beeper()
  local uv = vim.uv or vim.loop
  local noisy = get_env("AGENT_NOISY_MODE", "false")
  if noisy ~= "true" then
    return function() end
  end

  local sound_path = get_env("AGENT_SOUND_PATH", "/usr/share/sounds/freedesktop/stereo/message.oga")
  local interval = tonumber(get_env("AGENT_SOUND_INTERVAL", "5")) or 5

  local function play_sound()
      uv.spawn("paplay", { args = { sound_path }, detached = true }, function() end)
  end

  play_sound()

  local timer = uv.new_timer()
  timer:start(interval * 1000, interval * 1000, function()
      play_sound()
  end)

  return function()
    if timer and not timer:is_closing() then
      timer:stop()
      timer:close()
    end
  end
end

function M.start_orchestration()
  vim.ui.input({ prompt = "Tarea para Agentes (Ej: Script en python para...): " }, function(user_prompt)
    if not user_prompt or user_prompt == "" then return end

    local function inject_files(text)
       return text:gsub("@([%w_./-]+)", function(filepath)
          local f = io.open(filepath, "r")
          if f then
             local content = f:read("*a")
             f:close()
             return "\n\n--- INICIO DEL ARCHIVO: " .. filepath .. " ---\n" .. content .. "\n--- FIN DEL ARCHIVO ---\n\n"
          else
             return " [Error: no se pudo leer el archivo " .. filepath .. "] "
          end
       end)
    end

    user_prompt = inject_files(user_prompt)

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
    
    local architecture_prompt = "You are an AI Architect. User wants: " .. user_prompt .. "\nEvaluate the task's complexity. If it is very simple (e.g., small scripts, docs, single configs), write the FULL code yourself and start your response EXACTLY with 'MODE: EASY'. If it is complex (e.g., full apps, heavy logic, multiple files), do not write code, start your response EXACTLY with 'MODE: COMPLEX' and provide ONLY a concise technical plan and pseudocode to solve this. Minimize your response to save tokens."
    
    log("> **[Arquitecto Cloud]** Analizando petición para minimizar tokens...\n")
    
    local function execute_architecture(arch_response)
      log("> **[Arquitecto] Plan generado:**\n" .. arch_response)
      log("\n---\n")

      local function start_deployment(code_response)
         local raw_code = code_response:match("```[%w]*\n(.-)```") or code_response
         vim.fn.setreg("+", raw_code)
         log("\n> 📋 **El código ha sido copiado a tu portapapeles temporalmente.**")

         log("\n> ⏳ **[Arquitecto Cloud (Deployer)]** Construyendo el ejecutable de despliegue `deploy_ai.sh`... (Por favor espera unos segundos)\n")
         
         local deploy_prompt = "You are the Deployment Agent. The following code has been approved:\n\n" .. code_response .. "\n\nWrite a bash script that:\n1. Creates all necessary directories (using mkdir -p).\n2. Saves the code into the correct files (using cat << 'EOF' > filename).\n3. EXECUTES the necessary commands to compile and run the project (e.g., `cargo run`, `python3 file.py`, `node app.js`, etc.).\n\nEnsure the script is safe and correctly escapes contents. Output ONLY the raw bash script inside a ```bash block. Do not include any other text."
         
         local function execute_deployment(deploy_response)
            if deploy_response:match("^ERROR") then
               log("\n> ⚠️ **Fallo al generar script de despliegue:** " .. deploy_response)
               return
            end

            local bash_script = deploy_response:match("```bash\n(.-)```") or deploy_response:match("```\n(.-)```") or deploy_response
            local f = io.open("deploy_ai.sh", "w")
            if f then
               f:write(bash_script)
               f:close()
               vim.fn.system("chmod +x deploy_ai.sh")
               log("\n> 💾 **Script guardado como `deploy_ai.sh` en el directorio actual.**")
               
               vim.schedule(function()
                   vim.cmd("split deploy_ai.sh")
                   local stop_beep = start_attention_beeper()
                   local choice = vim.fn.confirm("¿Permitir al Arquitecto ejecutar deploy_ai.sh en tu entorno?", "&Sí\n&No", 2)
                   stop_beep()
                   
                   if choice == 1 then
                       log("\n> 🚀 **Ejecutando script en nueva terminal interactiva...**")
                       
                       -- Run in terminal so user can see output and interact
                       vim.cmd("split | terminal ./deploy_ai.sh")
                       
                       vim.defer_fn(function()
                          if vim.api.nvim_buf_is_valid(buf) then
                              vim.api.nvim_buf_delete(buf, { force = true })
                          end
                          vim.notify("Orquestador finalizado. Puedes ver la ejecución en la terminal.", vim.log.levels.INFO)
                       end, 1500)
                   else
                       log("\n> 🛑 **Despliegue cancelado. Puedes revisar y ejecutar `deploy_ai.sh` manualmente.**")
                   end
               end)
            else
               log("\n> ⚠️ **Error al guardar deploy_ai.sh**")
            end
         end

         call_cloud(deploy_prompt, function(deploy_response)
            if deploy_response:match("^ERROR") then
               log(deploy_response)
               log("\n> ⚠️ **[Sistema]** Falló el Deployer Cloud. Iniciando fallback a Ollama...\n")
               call_ollama(deploy_prompt, function(fallback_deploy)
                  execute_deployment(fallback_deploy)
               end)
               return
            end
            execute_deployment(deploy_response)
         end)
      end
      
      local function do_iteration(comments, previous_code)
         log("> **[Ollama Local (Turboquant)]** Iteración " .. current_iter .. "/" .. max_iter .. ". Escribiendo código...\n")
         local ollama_prompt = "You are a Developer. Write the full code for this plan:\n" .. arch_response
         if previous_code then
            ollama_prompt = ollama_prompt .. "\n\nHere is your previously generated code that failed review:\n```\n" .. previous_code .. "\n```\n"
         end
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
                  
                  start_deployment(code_response)
               else
                  log("### ❌ [Arquitecto] Revisión fallida. Comentarios:\n" .. review_response)
                  current_iter = current_iter + 1
                  if current_iter > max_iter then
                     log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado. Abortando.")
                     log("\n--- ÚLTIMO CÓDIGO ---\n" .. code_response)
                  else
                     log("\n---\n")
                     do_iteration(review_response, code_response)
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
      
      vim.schedule(function()
          local stop_beep = start_attention_beeper()
          vim.ui.input({ prompt = "Feedback al Arquitecto (Vacío para APROBAR): " }, function(feedback)
              stop_beep()
              if feedback and feedback ~= "" then
                  log("> **[Usuario] Feedback al Arquitecto:** " .. feedback .. "\n")
                  log("> **[Arquitecto Cloud]** Revisando plan...\n")
                  
                  local revision_prompt = "You are an AI Architect. Here is your previous plan:\n" .. arch_response .. "\n\nThe user provided this feedback: " .. feedback .. "\n\nPlease revise the plan accordingly. Provide ONLY the revised concise technical plan and pseudocode."
                  
                  call_cloud(revision_prompt, function(revised_response)
                     if revised_response:match("^ERROR") then
                        log(revised_response)
                        log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud en la revisión. Fallback a Ollama...\n")
                        call_ollama(revision_prompt, function(fallback_rev)
                           if fallback_rev:match("^ERROR") then log(fallback_rev) return end
                           execute_architecture(fallback_rev)
                        end)
                        return
                     end
                     execute_architecture(revised_response)
                  end)
              else
                  if arch_response:match("[Mm][Oo][Dd][Ee]:%s*[Ee][Aa][Ss][Yy]") then
                      log("> ✅ **Código Aprobado por el Usuario (Delegación Inteligente).**\n")
                      start_deployment(arch_response)
                  else
                      log("> ✅ **Plan Aprobado por el Usuario. Iniciando desarrollo...**\n")
                      do_iteration(nil, nil)
                  end
              end
          end)
      end)
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
