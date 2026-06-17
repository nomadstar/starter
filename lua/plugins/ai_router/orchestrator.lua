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
        { role = "user", content = prompt }
      },
      temperature = 0.2,
      max_tokens = tonumber(get_env("AGENT_MAX_OUTPUT_TOKENS", "4096"))
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
        
        if data.usage and data.usage.total_tokens then
          pcall(function()
            require("plugins.ai_router.metrics").add_usage("openrouter", data.usage.total_tokens)
          end)
        end
        
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
  local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
  system_prompt = system_prompt .. "\n" .. anti_lazy
  
  if vim.env.CAVEMAN_MODE == "true" then
    system_prompt = "Talk like caveman. Cut filler words. Use minimal grammar. Keep technical accuracy. Shortest possible output.\n" .. anti_lazy
  end

  local body = vim.json.encode({
    model = model,
    messages = {
      { role = "system", content = system_prompt },
      { role = "user", content = prompt }
    },
    stream = false,
    temperature = 0.1,
    options = {
      num_predict = tonumber(get_env("AGENT_LOCAL_MAX_PREDICT", "2048"))
    }
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

_G._ai_router_file_complete = function(arglead, cmdline, cursorpos)
   if arglead:match("^@") then
      local prefix = arglead:sub(2)
      local matches = vim.fn.glob(prefix .. "*", false, true)
      local results = {}
      for _, m in ipairs(matches) do
         if vim.fn.isdirectory(m) == 1 then
            table.insert(results, "@" .. m .. "/")
         else
            table.insert(results, "@" .. m)
         end
      end
      return results
   end
   return {}
end

function M.start_orchestration()
  vim.ui.input({ 
      prompt = "Tarea para Agentes (Ej: Script en python para...): ",
      completion = "customlist,v:lua._ai_router_file_complete"
  }, function(user_prompt)
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
    pcall(vim.treesitter.stop, buf)
    
    local function log(msg)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(msg, "\n"))
      if vim.api.nvim_win_is_valid(win) then
          local count = vim.api.nvim_buf_line_count(buf)
          pcall(vim.api.nvim_win_set_cursor, win, {count, 0})
      end
    end

    log("# ORQUESTADOR MULTI-AGENTE INICIADO")
    log("**Meta:** " .. user_prompt)
    log("---\n")
    
    local function process_urls_and_continue(prompt_text, callback)
       local urls = {}
       for url in prompt_text:gmatch("https?://[%w-_%.%?%.:/%+=&]+") do
          table.insert(urls, url)
       end
       
       if #urls == 0 then
          callback(prompt_text)
          return
       end
       
       log("> 🌐 **[Sistema]** Detectadas " .. #urls .. " URLs. Obteniendo contexto vía Jina Reader (timeout 10s)...")
       local new_prompt = prompt_text
       local completed = 0
       
       for _, url in ipairs(urls) do
          curl.get("https://r.jina.ai/" .. url, {
             timeout = 10000,
             callback = function(res)
                vim.schedule(function()
                   completed = completed + 1
                   if res.status == 200 then
                      log("> 🟢 Descarga exitosa: " .. url)
                      new_prompt = new_prompt .. "\n\n[WEB CONTEXT: " .. url .. "]\n" .. res.body .. "\n[END WEB CONTEXT]\n"
                   else
                      log("> 🔴 Error al descargar " .. url .. " (Status: " .. res.status .. "). Ignorando.")
                   end
                   
                   if completed == #urls then
                      callback(new_prompt)
                   end
                end)
             end
          })
       end
    end

    process_urls_and_continue(user_prompt, function(final_prompt)
       local max_iter = tonumber(get_env("AGENT_MAX_ITERATIONS", "3"))
       local current_iter = 1
       
       local cwd = vim.fn.getcwd()
       local tree = vim.fn.system("find . -maxdepth 2 -not -path '*/\\.*' | sort")
       
       local architecture_prompt = "You are an AI Architect. User wants: " .. final_prompt .. "\n\n[ENVIRONMENT CONTEXT]\nWorking Directory: " .. cwd .. "\nExisting Files:\n" .. tree .. "\nEvaluate the task's complexity. If it is very simple (e.g., small scripts, docs, single configs), write the FULL code yourself and start your response EXACTLY with 'MODE: EASY'. If it is complex (e.g., full apps, heavy logic, multiple files), do not write code, start your response EXACTLY with 'MODE: COMPLEX' and provide a concise technical plan. At the VERY END of your plan, list ALL the files that need to be created or modified, each on a new line starting EXACTLY with '[FILE] path/to/file'."
       
       log("> **[Arquitecto Cloud]** Analizando petición para minimizar tokens...\n")
    
    local function execute_architecture(arch_response)
      log("> **[Arquitecto] Plan generado:**\n" .. arch_response)
      log("\n---\n")

      local function start_deployment(code_response)
         local raw_code = code_response:match("```[%w]*\n(.-)```") or code_response
         vim.fn.setreg("+", raw_code)
         log("\n> 📋 **El código ha sido copiado a tu portapapeles temporalmente.**")

         local function execute_deployment(bash_script)
            local f = io.open("deploy_ai.sh", "w")
            if f then
               f:write(bash_script)
               f:close()
               vim.fn.system("chmod +x deploy_ai.sh")
               log("\n> 💾 **Script generado como `deploy_ai.sh`.**")
               
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

         local function build_deploy_script_native(generated_code)
            local script = "#!/bin/bash\nset -e\ntrap 'rm -f deploy_ai.sh' EXIT\n\n"
            local count = 0
            local parts = vim.split(generated_code, "### FILE: ", { plain = true })
            for _, part in ipairs(parts) do
               part = vim.trim(part)
               if part ~= "" then
                  local newline_idx = part:find("\n")
                  if newline_idx then
                     local filepath = vim.trim(part:sub(1, newline_idx - 1))
                     local code = part:sub(newline_idx + 1)
                     local clean_code = code:match("```[%w]*\n(.-)```") or code
                     local dir = filepath:match("(.+)/[^/]+$")
                     if dir then script = script .. "mkdir -p " .. dir .. "\n" end
                     script = script .. "cat > " .. filepath .. " << 'ENDOFFILE'\n" .. clean_code .. "\nENDOFFILE\n\n"
                     count = count + 1
                  end
               end
            end
            if count == 0 then return nil end
            return script
         end

         local native_script = build_deploy_script_native(code_response)
         if native_script then
             log("\n> ⚡ **[Sistema]** Construyendo script de despliegue nativamente (Evitando límites de tokens)...")
             execute_deployment(native_script)
         else
             log("\n> ⏳ **[Arquitecto Cloud (Deployer)]** Construyendo el ejecutable de despliegue `deploy_ai.sh`... (Por favor espera unos segundos)\n")
             
             local deploy_prompt = "You are the Deployment Agent. The following code has been approved:\n\n" .. code_response .. "\n\nWrite a bash script that:\n1. Includes `trap 'rm -f deploy_ai.sh' EXIT` at the top to self-delete.\n2. Creates all necessary directories (using mkdir -p).\n3. Saves the code into the correct files (using cat << 'EOF' > filename).\n4. EXECUTES the necessary commands to compile and run the project.\n\nEnsure the script is safe and correctly escapes contents. Output ONLY the raw bash script inside a ```bash block. Do not include any other text."
             
             call_cloud(deploy_prompt, function(deploy_response)
                if deploy_response:match("^ERROR") then
                   log(deploy_response)
                   log("\n> ⚠️ **[Sistema]** Falló el Deployer Cloud. Iniciando fallback a Ollama...\n")
                   call_ollama(deploy_prompt, function(fallback_deploy)
                      local bash_script = fallback_deploy:match("```bash\n(.-)```") or fallback_deploy:match("```\n(.-)```") or fallback_deploy
                      execute_deployment(bash_script)
                   end)
                   return
                end
                local bash_script = deploy_response:match("```bash\n(.-)```") or deploy_response:match("```\n(.-)```") or deploy_response
                execute_deployment(bash_script)
             end)
         end
      end
      
      local files = {}
      for file in arch_response:gmatch("%[FILE%]%s*([^\n\r]+)") do
         table.insert(files, vim.trim(file))
      end
      if #files == 0 then
         table.insert(files, "main_project")
      end
      
      local all_generated_code = ""
      
      local function process_chunk(chunk_index)
         if chunk_index > #files then
            log("\n> 🎯 **Todos los archivos han sido generados.** Iniciando despliegue...")
            start_deployment(all_generated_code)
            return
         end
         
         local current_file = files[chunk_index]
         log("\n> 📦 **Procesando archivo (" .. chunk_index .. "/" .. #files .. "):** `" .. current_file .. "`")
         
         local approved_context = ""
         if chunk_index > 1 then
             local approved_files = {}
             for i = 1, chunk_index - 1 do table.insert(approved_files, files[i]) end
             approved_context = "\n\n[CRITICAL]: The following files have ALREADY been successfully generated and approved: " .. table.concat(approved_files, ", ") .. ". DO NOT request them to be added or fixed. Focus EXCLUSIVELY on: " .. current_file
         end
         
         local current_iter = 1
         
         local function do_iteration(comments, previous_code)
            log("> **[Ollama Local (Turboquant)]** Iteración " .. current_iter .. "/" .. max_iter .. ". Escribiendo código...\n")
            local ollama_prompt
            if current_iter == 1 then
               ollama_prompt = "You are a Developer. Write the full code for this specific file: " .. current_file .. ". Here is the overall plan for context:\n" .. arch_response .. approved_context
            else
               ollama_prompt = "You are a Developer. You are fixing the file: " .. current_file .. ". Here is your previously generated code:\n```\n" .. previous_code .. "\n```\n\nFix the code based EXACTLY on these comments:\n" .. comments
            end
            
            if vim.env.CAVEMAN_MODE == "true" then
               ollama_prompt = ollama_prompt .. "\n\nCAVEMAN MODE: Output ONLY code. No chatter. Shortest possible fixes."
            end
            local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
            ollama_prompt = ollama_prompt .. "\n" .. anti_lazy
            ollama_prompt = ollama_prompt .. "\nOutput ONLY the raw code inside standard markdown blocks (```). Do not include any other text."
   
            call_ollama(ollama_prompt, function(code_response)
               if code_response:match("^ERROR") then
                  log(code_response)
                  return
               end
               
               log("> **[Ollama Local]** Código completado (" .. current_file .. "). Solicitando revisión iterativa...\n")
               
               local review_prompt
               if current_iter == 1 then
                  review_prompt = "You are the Architect. Review this code for the file " .. current_file .. " against your plan:\n\nCODE:\n" .. code_response .. "\n\nPLAN:\n" .. arch_response .. approved_context .. "\n\nYou MUST reply with a raw JSON object and nothing else. Format:\n{\n  \"score\": 100,\n  \"fixes\": \"list of fixes if any, or empty\"\n}\nIf the code works perfectly, give a score of 90 to 100. If it has minor bugs, give 80 to 89. If it has major bugs, give < 80."
               else
                  review_prompt = "You are the Architect. You previously requested these fixes for " .. current_file .. ":\n" .. comments .. "\n\nReview the updated code:\n\nCODE:\n" .. code_response .. approved_context .. "\n\nYou MUST reply with a raw JSON object and nothing else. Format:\n{\n  \"score\": 100,\n  \"fixes\": \"list of fixes if any, or empty\"\n}\nIf the code works perfectly, give a score of 90 to 100. If it has minor bugs, give 80 to 89. If it has major bugs, give < 80."
               end
               
               if vim.env.CAVEMAN_MODE == "true" then
                  review_prompt = review_prompt .. "\n\nCAVEMAN MODE: Output ONLY the raw JSON object. No markdown formatting, no explanations."
               end
               
               local function handle_review(review_response)
                  local json_str = review_response:match("{.*}") or review_response
                  local ok, data = pcall(vim.json.decode, json_str)
                  
                  local score = 0
                  local fixes = review_response
                  if ok and type(data) == "table" then
                      score = tonumber(data.score) or 0
                      fixes = data.fixes or "Unknown error"
                      if type(fixes) == "table" then
                          fixes = vim.json.encode(fixes)
                      elseif type(fixes) ~= "string" then
                          fixes = tostring(fixes)
                      end
                  else
                      log("\n> ⚠️ **[Sistema]** Falló el parseo JSON del Revisor. Asumiendo score 0.")
                  end
                  
                  if score >= 90 then
                     log("### ✅ [Arquitecto] Archivo `" .. current_file .. "` APROBADO (Score: " .. score .. ") en iteración " .. current_iter .. "!")
                     all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. code_response
                     process_chunk(chunk_index + 1)
                  elseif score >= 80 and score < 90 then
                     log("### 🩹 [Arquitecto] Errores menores en " .. current_file .. " (Score: " .. score .. "). Delegando parche a Cloud Developer...")
                     local patch_prompt = "You are a Developer. The code below has these minor issues:\n" .. fixes .. "\n\nCODE:\n" .. code_response .. "\n\nFix the code. Return the fixed code inside a markdown block. BEFORE the code block, briefly list the exact changes you made (verbose log)."
                     
                     call_cloud(patch_prompt, function(patch_response)
                        if patch_response:match("^ERROR") then
                           log("\n> ⚠️ **[Sistema]** Falló el parche en la nube. Forzando iteración local...")
                           do_iteration(fixes, code_response)
                           return
                        end
                        
                        log("\n> ☁️ **[Cloud Developer]** Cambios aplicados en `" .. current_file .. "`:\n" .. patch_response)
                        local patched_code = patch_response:match("```[%w]*\n(.-)```") or patch_response
                        
                        log("\n### ✅ [Sistema] Archivo `" .. current_file .. "` APROBADO vía parche Cloud!")
                        all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. patched_code
                        process_chunk(chunk_index + 1)
                     end)
                  else
                     log("### ❌ [Arquitecto] Revisión fallida para " .. current_file .. " (Score: " .. score .. "). Comentarios:\n" .. fixes)
                     current_iter = current_iter + 1
                     if current_iter > max_iter then
                        log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado para " .. current_file .. ". Aceptando tal como está.")
                        all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. code_response
                        process_chunk(chunk_index + 1)
                     else
                        log("\n---\n")
                        do_iteration(fixes, code_response)
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
         
         do_iteration(nil, nil)
      end
      
      vim.defer_fn(function()
          vim.cmd("redraw")
          local stop_beep = start_attention_beeper()
          vim.ui.input({ prompt = "Feedback al Arquitecto (Vacío para APROBAR): " }, function(feedback)
              stop_beep()
              if feedback and feedback ~= "" then
                  log("> **[Usuario] Feedback al Arquitecto:** " .. feedback .. "\n")
                  log("> **[Arquitecto Cloud]** Revisando plan...\n")
                  
                  local revision_prompt = "You are an AI Architect. Here is your previous plan:\n" .. arch_response .. "\n\nThe user provided this feedback: " .. feedback .. "\n\nPlease revise the plan accordingly. Provide ONLY the revised concise technical plan and pseudocode."
                  
                  if vim.env.CAVEMAN_MODE == "true" then
                     revision_prompt = revision_prompt .. "\n\nCAVEMAN MODE: Output ONLY the updated technical plan. No apologies, no introductions. Shortest possible output."
                  end
                  
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
                      process_chunk(1)
                  end
              end
          end)
      end, 100)
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
  end)
end

return M
