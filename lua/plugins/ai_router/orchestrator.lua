local M = {}
local curl = require("plenary.curl")
local telegram = require("plugins.ai_router.telegram")

local function get_env(var, default)
  local v = vim.env[var]
  if not v or v == "" then return default end
  return v
end

-- FIX #5: Validación de respuestas vacías
local function is_valid_response(text)
  return text and vim.trim(text) ~= "" and not text:match("^%s*$")
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
        { role = "user",   content = prompt },
      },
      temperature = 0.2,
      max_tokens = tonumber(get_env("AGENT_MAX_OUTPUT_TOKENS", "4096")),
    })

    curl.post(url, {
      body = body,
      headers = {
        ["Content-Type"] = "application/json",
        ["Authorization"] = "Bearer " .. key,
      },
      callback = function(res)
        -- FIX #2: 429 rate-limit tratado igual que otros errores recuperables
        if res.status ~= 200 then
          local is_auth_error = (res.status == 401 or res.status == 403)
          local can_retry = not is_auth_error and index < #models

          if can_retry then
            vim.schedule(function()
              vim.notify(
                "Falló modelo " .. current_model .. " (HTTP " .. res.status .. "), intentando con el siguiente...",
                vim.log.levels.WARN
              )
              try_model(index + 1)
            end)
          else
            vim.schedule(function()
              callback("ERROR Cloud (" .. current_model .. "): " .. res.status .. " " .. res.body)
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
            require("plugins.ai_router.metrics").add_usage("openrouter", data.usage.total_tokens)
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
    })
  end

  try_model(1)
end

local function get_local_models()
  local local_models_str = get_env("AGENT_LOCAL_MODEL", "llama3")
  local local_models = vim.split(local_models_str, ",")
  for i, m in ipairs(local_models) do
    local_models[i] = vim.trim(m)
  end
  return local_models
end

local function call_ollama(model, prompt, callback)
  local url = get_env("OLLAMA_HOST", "http://localhost:11434") .. "/api/chat"

  local system_prompt = "You are an Expert Senior Developer. Your task is to write exhaustive, production-grade, and deeply detailed code/documentation."
  local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
  system_prompt = system_prompt .. "\n" .. anti_lazy

  local messages = {
    { role = "system", content = system_prompt },
    { role = "user",   content = prompt },
  }

  local accumulated_text = ""
  local continuation_count = 0
  local max_continuations = 5 -- prevent infinite loops

  local function send_request()
    local body = vim.json.encode({
      model = model,
      messages = messages,
      stream = false,
      temperature = 0.1,
      options = {
        num_predict = tonumber(get_env("AGENT_LOCAL_MAX_PREDICT", "4096")),
        num_ctx = tonumber(get_env("AGENT_LOCAL_MAX_CTX", "16384")),
      },
    })

    curl.post(url, {
      body = body,
      headers = { ["Content-Type"] = "application/json" },
      callback = function(res)
        if res.status ~= 200 then
          vim.schedule(function()
            callback("ERROR Ollama: " .. tostring(res.status) .. " " .. tostring(res.body))
          end)
          return
        end
        local ok, data = pcall(vim.json.decode, res.body)
        if not ok or not data or not data.message then
          vim.schedule(function()
            callback("ERROR Ollama: JSON decode failed")
          end)
          return
        end

        accumulated_text = accumulated_text .. data.message.content

        -- Si se cortó por límite de tokens (length), y no hemos excedido el máximo de continuaciones
        if data.done_reason == "length" and continuation_count < max_continuations then
          continuation_count = continuation_count + 1
          table.insert(messages, { role = "assistant", content = data.message.content })
          table.insert(messages, { role = "user", content = "Continue exactly where you left off. Do not repeat anything from before. Do not add introductory text. If you were inside a markdown block, continue writing raw code without opening a new markdown block." })
          send_request()
        else
          vim.schedule(function()
            callback(accumulated_text)
          end)
        end
      end,
    })
  end

  send_request()
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
    completion = "customlist,v:lua._ai_router_file_complete",
  }, function(user_prompt)
    if not user_prompt or user_prompt == "" then return end

    local inhibit_job_id = -1
    if vim.fn.executable("systemd-inhibit") == 1 then
      inhibit_job_id = vim.fn.jobstart({
        "systemd-inhibit", "--what=sleep:idle", "--who=Neovim AI Router", "--why=Orquestador trabajando", "sleep", "86400"
      })
    end

    local function stop_inhibit()
      if inhibit_job_id > 0 then
        pcall(vim.fn.jobstop, inhibit_job_id)
        inhibit_job_id = -1
      end
    end

    local function inject_files(text)
      return text:gsub("@([%w_./-]+)", function(filepath)
        if vim.fn.isdirectory(filepath) == 1 then
          local output = "\n\n--- INICIO DEL DIRECTORIO: " .. filepath .. " ---\n"
          local files = vim.fn.systemlist("find " .. vim.fn.shellescape(filepath) .. " -type f -not -path '*/\\.*'")
          for _, f_path in ipairs(files) do
             local fd = io.open(f_path, "r")
             if fd then
                 local content = fd:read("*a")
                 fd:close()
                 output = output .. "--- ARCHIVO: " .. f_path .. " ---\n" .. content .. "\n--- FIN DE ARCHIVO ---\n"
             end
          end
          output = output .. "--- FIN DEL DIRECTORIO ---\n\n"
          return output
        else
          local f = io.open(filepath, "r")
          if f then
            local content = f:read("*a")
            f:close()
            return "\n\n--- INICIO DEL ARCHIVO: " .. filepath .. " ---\n" .. content .. "\n--- FIN DEL ARCHIVO ---\n\n"
          else
            return " [Error: no se pudo leer el archivo/directorio " .. filepath .. "] "
          end
        end
      end)
    end

    user_prompt = inject_files(user_prompt)

    vim.cmd("vsplit")
    local win = vim.api.nvim_get_current_win()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_win_set_buf(win, buf)
    vim.api.nvim_buf_set_name(buf, "AI_Orchestrator_" .. math.random(1000))
    vim.bo[buf].syntax = "markdown"

    local function log(msg)
      if not vim.api.nvim_buf_is_valid(buf) then return end
      vim.api.nvim_buf_set_lines(buf, -1, -1, false, vim.split(msg, "\n"))
      if vim.api.nvim_win_is_valid(win) then
        local count = vim.api.nvim_buf_line_count(buf)
        pcall(vim.api.nvim_win_set_cursor, win, { count, 0 })
      end
      if telegram.is_enabled() then
        telegram.send_message(msg)
      end
    end

    log("# ORQUESTADOR MULTI-AGENTE INICIADO")
    log("**Meta:** " .. user_prompt)
    log("---\n")

    -- FIX #3: process_urls_and_continue con contador atómico correcto vía vim.schedule
    local function process_urls_and_continue(prompt_text, callback)
      local urls = {}
      for url in prompt_text:gmatch("https?://[%w%-_%.%?%.:/%+=&]+") do
        table.insert(urls, url)
      end

      if #urls == 0 then
        callback(prompt_text)
        return
      end

      log("> 🌐 **[Sistema]** Detectadas " .. #urls .. " URLs. Obteniendo contexto vía Jina Reader (timeout 10s)...")

      local new_prompt = prompt_text
      local total = #urls
      local completed = 0  -- accedido solo desde vim.schedule, seguro

      local function on_fetch_done()
        completed = completed + 1
        if completed == total then
          callback(new_prompt)
        end
      end

      for _, url in ipairs(urls) do
        curl.get("https://r.jina.ai/" .. url, {
          timeout = 10000,
          callback = function(res)
            vim.schedule(function()
              if res.status == 200 then
                log("> 🟢 Descarga exitosa: " .. url)
                new_prompt = new_prompt .. "\n\n[WEB CONTEXT: " .. url .. "]\n" .. res.body .. "\n[END WEB CONTEXT]\n"
              else
                log("> 🔴 Error al descargar " .. url .. " (Status: " .. res.status .. "). Ignorando.")
              end
              on_fetch_done()
            end)
          end,
        })
      end
    end

    process_urls_and_continue(user_prompt, function(final_prompt)
      local max_iter = tonumber(get_env("AGENT_MAX_ITERATIONS", "3"))
      local cwd = vim.fn.getcwd()
      local tree = vim.fn.system("find . -maxdepth 2 -not -path '*/\\.*' | sort")

      local architecture_prompt = "You are an AI Architect. Evaluate the task complexity:\n\nUser wants: "
        .. final_prompt
        .. "\n\n[ENVIRONMENT CONTEXT]\nWorking Directory: "
        .. cwd
        .. "\nExisting Files:\n"
        .. tree
        .. "\n\nSTRICT RULES:\n"
        .. "1. If the task is TRIVIAL (e.g. a single simple script, 'Hello World', < 50 lines): Start exactly with 'MODE: FAST'. Then immediately write the code using this EXACT format:\n"
        .. "### FILE: path/to/file\n```\n<code here>\n```\n"
        .. "2. If the user EXPLICITLY requests extensive documentation (e.g. using keywords like 'docs', 'documentación', 'manual', 'enciclopedia') AND the task involves NO source code logic: Start exactly with 'MODE: DOCS'. Do NOT use this mode if the user wants to generate software code, otherwise they will reject the plan. Produce a minimal plan ending with a list of files to generate in this EXACT format:\n"
        .. "   [FILE] path/to/file | {one-line purpose}\n"
        .. "3. If the task requires multiple files, complex logic, or architecture: Start exactly with 'MODE: PLAN'. Produce a minimal plan ending with a list of files to generate in this EXACT format:\n"
        .. "   [FILE] path/to/file | {one-line purpose}\n\n"
        .. "Do not mix modes. When in doubt, use MODE: PLAN."

      log("> **[Arquitecto Cloud]** Analizando petición para minimizar tokens...\n")

      -- Función para guardar un archivo individual de forma nativa en Lua
      local function save_file_native(filepath, content)
        local clean_code = content:match("```[%w]*\n(.-)```") or content
        local dir = filepath:match("(.+)/[^/]+$")
        if dir then
          vim.fn.mkdir(dir, "p")
        end
        local f = io.open(filepath, "w")
        if f then
          f:write(clean_code)
          f:close()
          return true
        end
        return false
      end

      local function execute_architecture(arch_response)
        if not is_valid_response(arch_response) then
          log("\n> ⚠️ **[Sistema]** El Arquitecto devolvió una respuesta vacía. Abortando.")
          return
        end

        log("> **[Arquitecto] Plan generado:**\n" .. arch_response)
        log("\n---\n")

        local function start_fast_track(code_to_deploy)
          local count = 0
          local parts = vim.split(code_to_deploy, "### FILE: ", { plain = true })
          for _, part in ipairs(parts) do
            part = vim.trim(part)
            if part ~= "" then
              local newline_idx = part:find("\n")
              if newline_idx then
                local filepath = vim.trim(part:sub(1, newline_idx - 1))
                local code = part:sub(newline_idx + 1)
                if save_file_native(filepath, code) then
                  log("### 💾 Guardado en disco: `" .. filepath .. "`")
                  count = count + 1
                end
              end
            end
          end
          if count > 0 then
            log("\n> 🚀 **[Fast Track] Despliegue completado.** " .. count .. " archivo(s) guardado(s).")
          else
            log("\n> ⚠️ **[Sistema]** No se encontraron marcadores de archivo válidos en Fast Track.")
          end
        end

        -- Extraer lista de archivos del plan
        local files = {}
        local file_purposes = {}
        for filepath, purpose in arch_response:gmatch("%[FILE%]%s*([%w_./-]+)%s*|%s*([^\n\r]+)") do
          local fp = vim.trim(filepath)
          local p = vim.trim(purpose)
          if fp ~= "" then
            table.insert(files, fp)
            file_purposes[fp] = p
          end
        end
        if #files == 0 then
          -- Fallback in case Architect didn't follow format exactly
          for filepath in arch_response:gmatch("%[FILE%]%s*([%w_./-]+)") do
            local fp = vim.trim(filepath)
            if fp ~= "" then
              table.insert(files, fp)
              file_purposes[fp] = "General implementation"
            end
          end
        end
        if #files == 0 then
          table.insert(files, "main_project")
        end

        local all_generated_code = ""

        -- FIX #1: current_iter declarada DENTRO de process_chunk, una por archivo,
        -- sin ningún shadowing externo
        local function dump_state(current_file, chunk_index)
          local state = "# AI Router - Orchestrator State (Brain)\n\n"
          state = state .. "## Meta del Proyecto\n" .. final_prompt .. "\n\n"
          state = state .. "## Plan del Arquitecto\n" .. arch_response .. "\n\n"
          state = state .. "## Memoria a Corto Plazo (Archivos Aprobados)\n"
          if chunk_index > 1 then
            for i = 1, chunk_index - 1 do
              state = state .. "- `[x]` " .. files[i] .. "\n"
            end
          else
            state = state .. "*Ninguno todavía*\n"
          end
          
          state = state .. "\n## Tarea Actual\n"
          if current_file then
            state = state .. "- `[/]` Trabajando en: **" .. current_file .. "** (Iteración actual)\n"
          else
            state = state .. "- `[x]` **¡Todos los archivos completados!**\n"
          end

          local f = io.open(".ai_router_state.md", "w")
          if f then
            f:write(state)
            f:close()
          end
        end

        local function process_chunk(chunk_index)
          if chunk_index > #files then
            log("\n> 🎯 **Todos los archivos han sido generados y guardados en disco.**")
            log("> 📄 El estado final de la memoria se ha guardado en `.ai_router_state.md`")
            dump_state(nil, chunk_index)
            stop_inhibit()
            return
          end

          local current_file = files[chunk_index]
          log("\n> 📦 **Procesando archivo (" .. chunk_index .. "/" .. #files .. "):** `" .. current_file .. "`")
          dump_state(current_file, chunk_index)

          local approved_context = ""
          if chunk_index > 1 then
            local approved_files = {}
            for i = 1, chunk_index - 1 do
              table.insert(approved_files, files[i])
            end
            approved_context = "\n\n[CRITICAL]: The following files have ALREADY been successfully generated and approved: "
              .. table.concat(approved_files, ", ")
              .. ". DO NOT request them to be added or fixed. Focus EXCLUSIVELY on: "
              .. current_file
          end

          local iter_count = 1

          local is_docs_mode = arch_response:match("^[Mm][Oo][Dd][Ee]:%s*[Dd][Oo][Cc][Ss]") ~= nil

          local current_purpose = file_purposes[current_file] or "General implementation"
          local base_prompt = ""

          if is_docs_mode then
            base_prompt = "You are an Expert Technical Writer and Architect implementing exactly ONE file.\n"
              .. "FILE: " .. current_file .. "\n"
              .. "PURPOSE: " .. current_purpose .. "\n\n"
              .. "Overall Project Goal: " .. final_prompt .. "\n\n"
              .. "CRITICAL INSTRUCTIONS FOR MODE DOCS:\n"
              .. "- You MUST write EXCEPTIONAL, EXTENSIVE, and DEEPLY COMPREHENSIVE documentation.\n"
              .. "- The document MUST be Complete (cover all edge cases), Precise (technically flawless), Concise in format but exhaustive in content, and Unambiguous.\n"
              .. "- Caveman mode is TEMPORARILY DISABLED for this file. You are FREE and REQUIRED to write as much detailed text as necessary to fully cover the topic.\n"
              .. "- NEVER summarize. NEVER output a 'bare minimum' skeleton.\n"
              .. approved_context
          else
            base_prompt = "You are an Expert Developer implementing exactly ONE file.\n"
              .. "FILE: " .. current_file .. "\n"
              .. "PURPOSE: " .. current_purpose .. "\n\n"
          local function do_iteration(comments, previous_code, force_model)
            local local_models = get_local_models()
            if force_model then
              local_models = { force_model }
            end

            local model_idx = 1
            local current_code = previous_code

            local function run_next_model()
              if model_idx > #local_models then
                finish_relay(current_code)
                return
              end

              local current_model = local_models[model_idx]
              log("> **[Ollama Local (" .. current_model .. ")]** Iteración " .. iter_count .. "/" .. max_iter .. ". Paso " .. model_idx .. "/" .. #local_models .. "...\n")

              local ollama_prompt
              if iter_count == 1 and model_idx == 1 then
                ollama_prompt = base_prompt
              elseif iter_count > 1 and model_idx == 1 then
                ollama_prompt = base_prompt .. "\n\n=================================\n\n"
                  .. "You are currently FIXING this file based on the Architect's feedback.\n"
                  .. "Here is your previously generated code:\n```\n"
                  .. (current_code or "")
                  .. "\n```\n\nFix the code based EXACTLY on these comments:\n"
                  .. (comments or "")
              else
                ollama_prompt = base_prompt .. "\n\n=================================\n\n"
                  .. "You are the NEXT developer in the relay. Refine and improve the draft from the previous developer.\n"
                  .. "PREVIOUS DRAFT:\n```\n"
                  .. (current_code or "")
                  .. "\n```\n\nImprove it while maintaining the original purpose."
              end

              ollama_prompt = ollama_prompt .. "\nAdd a comment somewhere in the code (using appropriate comment syntax): `# Esto lo hizo " .. current_model .. "` to sign your work."

              if vim.env.CAVEMAN_MODE == "true" and not is_docs_mode then
                ollama_prompt = ollama_prompt .. "\n\nCAVEMAN MODE: Output ONLY code. No chatter. Shortest possible fixes."
              end
              local anti_lazy = "CRITICAL: You are an autonomous system. Do NOT use placeholders, comments like 'rest of code here', or summaries. You MUST write the ENTIRE implementation for ALL requested files. Skipping code will break the deployment."
              ollama_prompt = ollama_prompt .. "\n" .. anti_lazy
              ollama_prompt = ollama_prompt .. "\nOutput ONLY the raw code inside standard markdown blocks (```). Do not include any other text."

              call_ollama(current_model, ollama_prompt, function(code_response)
                if code_response:match("^ERROR") then
                  log("> ⚠️ **[Sistema]** Error (" .. code_response .. "). Saltando el modelo " .. current_model .. "...")
                  model_idx = model_idx + 1
                  run_next_model()
                  return
                end
                current_code = code_response
                model_idx = model_idx + 1
                run_next_model()
              end)
            end

            local function finish_relay(final_code)
              final_code = final_code or ""
              log("> **[Ollama Local]** Cadena completada (" .. current_file .. "). Auto-evaluando...\n")

              local self_review_prompt = "You are an AI Self-Reviewer. Review the code you just generated for " .. current_file .. ".\n\nCODE:\n" .. final_code .. "\n\nIdentify any obvious bugs, missing implementations, or placeholders. You MUST reply with a raw JSON object: {\"score\": 100, \"fixes\": \"list of fixes or empty\"}. Score 90-100 if perfect, <90 if there are issues."
              
              if vim.env.CAVEMAN_MODE == "true" then
                self_review_prompt = self_review_prompt .. "\nCAVEMAN MODE: Output ONLY the raw JSON object."
              end

              call_ollama(local_models[#local_models], self_review_prompt, function(self_review_response)
                local self_json_str = self_review_response:match("{.*}") or self_review_response
                local ok, data = pcall(vim.json.decode, self_json_str)
                local self_fixes = ""
                if ok and type(data) == "table" then
                  self_fixes = data.fixes or ""
                  if type(self_fixes) == "table" then self_fixes = vim.json.encode(self_fixes) end
                end

                log("> **[Ollama Auto-Review]** Evaluado localmente. Enviando defensa al Arquitecto Cloud para veredicto final...\n")

                local review_prompt
                local line_count = select(2, final_code:gsub('\n', '\n')) + 1
                if iter_count == 1 then
                  review_prompt = "You are the Architect. The Developer generated code for "
                    .. current_file .. " (Length: " .. line_count .. " lines).\n\n"
                    .. "The Developer's self-review (defense) noted these issues:\n" .. self_fixes .. "\n\n"
                    .. "Review the code against the overall purpose: " .. (file_purposes[current_file] or "General") .. "\n\nCODE:\n"
                    .. final_code
                    .. approved_context
                else
                  review_prompt = "You are the Architect. You previously requested these fixes for "
                    .. current_file
                    .. ":\n"
                    .. (comments or "")
                    .. "\n\nReview the updated code:\n\nCODE:\n"
                    .. final_code
                    .. approved_context
                end

                review_prompt = review_prompt .. "\n\nYou MUST reply with a raw JSON object and nothing else. Format:\n{\n  \"score\": 100,\n  \"fixes\": [\"list of fixes if any\"],\n  \"cooperation_notes\": \"notas breves sobre como colaboraron los modelos locales\",\n  \"cooperation_scores\": \"modelA=80, modelB=90\"\n}\nIf the code works perfectly, give a score of 90 to 100. If it has minor bugs, give 80 to 89. If it has major bugs, give < 80. IMPORTANT: The score MUST be a NUMERIC INTEGER."

                if vim.env.CAVEMAN_MODE == "true" then
                  review_prompt = review_prompt .. "\n\nCAVEMAN MODE: Output ONLY the raw JSON object. No markdown formatting, no explanations."
                end

                local function handle_review(review_response)
                  local json_str = review_response:match("{.*}") or review_response
                  local ok2, data2 = pcall(vim.json.decode, json_str)

                  local score = 0
                  local fixes = review_response
                  local coop_notes = ""
                  local coop_scores = ""
                  if ok2 and type(data2) == "table" then
                    score = tonumber(data2.score) or 0
                    fixes = data2.fixes or "Unknown error"
                    coop_notes = data2.cooperation_notes or ""
                    coop_scores = data2.cooperation_scores or ""
                    if type(fixes) == "table" then
                      fixes = vim.json.encode(fixes)
                    elseif type(fixes) ~= "string" then
                      fixes = tostring(fixes)
                    end
                  else
                    log("\n> ⚠️ **[Sistema]** Falló el parseo JSON del Revisor. Asumiendo score 0.")
                  end

                  if coop_notes ~= "" then
                    log("> 🤝 **[Cooperación]** Notas: " .. coop_notes)
                  end
                  if coop_scores ~= "" then
                    log("> 📊 **[Cooperación]** Puntajes: " .. coop_scores)
                  end

                  if score >= 90 then
                    log("### ✅ [Arquitecto] Archivo `" .. current_file .. "` APROBADO (Score: " .. score .. ") en iteración " .. iter_count .. "!")
                    if save_file_native(current_file, final_code) then
                       log("### 💾 Guardado en disco: `" .. current_file .. "`")
                    end
                    all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. final_code
                    process_chunk(chunk_index + 1)
                  elseif score >= 80 then
                    log("### 🩹 [Arquitecto] Errores menores en " .. current_file .. " (Score: " .. score .. "). Delegando parche a Cloud Developer...")
                    local patch_prompt = "You are a Developer. The code below has these minor issues:\n"
                      .. fixes
                      .. "\n\nCODE:\n"
                      .. final_code
                      .. "\n\nFix the code. Return the fixed code inside a markdown block. BEFORE the code block, briefly list the exact changes you made (verbose log)."

                    call_cloud(patch_prompt, function(patch_response)
                      if patch_response:match("^ERROR") then
                        log("\n> ⚠️ **[Sistema]** Falló el parche en la nube. Forzando iteración local...")
                        iter_count = iter_count + 1
                        if iter_count > max_iter then
                          log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado para " .. current_file .. ". Aceptando tal como está.")
                          if save_file_native(current_file, final_code) then
                             log("### 💾 Guardado en disco: `" .. current_file .. "`")
                          end
                          all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. final_code
                          process_chunk(chunk_index + 1)
                        else
                          do_iteration(fixes, final_code)
                        end
                        return
                      end

                      log("\n> ☁️ **[Cloud Developer]** Cambios aplicados en `" .. current_file .. "`:\n" .. patch_response)
                      local patched_code = patch_response:match("```[%w]*\n(.-)```") or patch_response
                      log("\n### ✅ [Sistema] Archivo `" .. current_file .. "` APROBADO vía parche Cloud!")
                      if save_file_native(current_file, patched_code) then
                         log("### 💾 Guardado en disco: `" .. current_file .. "`")
                      end
                      all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. patched_code
                      process_chunk(chunk_index + 1)
                    end)
                  else
                    local best_model = nil
                    if coop_scores ~= "" then
                      local max_coop = -1
                      for m, s in coop_scores:gmatch("([%w%-_]+)%s*=%s*(%d+)") do
                        local iscore = tonumber(s)
                        if iscore and iscore > max_coop then
                          max_coop = iscore
                          best_model = m
                        end
                      end
                    end
                    
                    log("### ❌ [Arquitecto] Revisión fallida para " .. current_file .. " (Score: " .. score .. "). Comentarios:\n" .. fixes)
                    if best_model then
                      log("> 👑 El modelo **" .. best_model .. "** obtuvo el mejor puntaje de cooperación y liderará el parcheo.")
                    end

                    iter_count = iter_count + 1
                    if iter_count > max_iter then
                      log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado para " .. current_file .. ". Aceptando tal como está.")
                      if save_file_native(current_file, final_code) then
                         log("### 💾 Guardado en disco: `" .. current_file .. "`")
                      end
                      all_generated_code = all_generated_code .. "\n\n### FILE: " .. current_file .. "\n" .. final_code
                      process_chunk(chunk_index + 1)
                    else
                      log("\n---\n")
                      do_iteration(fixes, final_code, best_model)
                    end
                  end
                end

                call_cloud(review_prompt, function(review_response)
                  if review_response:match("^ERROR") then
                    log(review_response)
                    log("\n> ⚠️ **[Sistema]** Falló el Revisor Cloud. Fallback a Ollama...\n")
                    call_ollama(get_local_models()[1], review_prompt, function(fallback_review)
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

            run_next_model()
          end
          end

          do_iteration(nil, nil)
        end

        -- FIX #6: vim.schedule en lugar de vim.defer_fn(100ms) para el feedback
        vim.schedule(function()
          vim.cmd("redraw")
          local stop_beep = start_attention_beeper()

          local feedback_processed = false

          local function process_feedback(feedback, from_telegram)
            if feedback_processed then return end
            feedback_processed = true
            stop_beep()
            telegram.stop_polling()

            if from_telegram then
              vim.schedule(function()
                local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
                vim.api.nvim_feedkeys(esc, "n", false)
              end)
            end

            if feedback == false then return end -- Aborted locally

            if feedback and feedback ~= "" then
              log("> **[Usuario] Feedback al Arquitecto:** " .. feedback .. "\n")
              log("> **[Arquitecto Cloud]** Revisando plan...\n")

              local format_rules = "\n\nSTRICT RULES FOR OUTPUT:\n"
                .. "Produce a minimal plan ending with a list of files to generate in this EXACT format:\n"
                .. "   [FILE] path/to/file | {one-line purpose}\n\n"
                .. "Failure to use the [FILE] format will break the system. NEVER output filenames in a different format."

              local revision_prompt = "You are an AI Architect. Here is your previous plan:\n"
                .. arch_response
                .. "\n\nThe user provided this feedback: "
                .. feedback
                .. "\n\nPlease revise the plan accordingly. Provide ONLY the revised concise technical plan and pseudocode."
                .. format_rules

              if vim.env.CAVEMAN_MODE == "true" then
                revision_prompt = revision_prompt .. "\n\nCAVEMAN MODE: Output ONLY the updated technical plan. No apologies, no introductions. Shortest possible output."
              end

              call_cloud(revision_prompt, function(revised_response)
                if revised_response:match("^ERROR") then
                  log(revised_response)
                  log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud en la revisión. Fallback a Ollama...\n")
                  call_ollama(get_local_models()[1], revision_prompt, function(fallback_rev)
                    if fallback_rev:match("^ERROR") then
                      log(fallback_rev)
                      return
                    end
                    execute_architecture(fallback_rev)
                  end)
                  return
                end
                execute_architecture(revised_response)
              end)
            else
              if arch_response:match("^[Mm][Oo][Dd][Ee]:%s*[Ff][Aa][Ss][Tt]") then
                log("> ⚡ **[Fast Track]** Tarea simple detectada. Guardando archivo(s) nativamente...\n")
                start_fast_track(arch_response)
              elseif arch_response:match("^[Mm][Oo][Dd][Ee]:%s*[Dd][Oo][Cc][Ss]") then
                log("> 📚 **[Docs Mode]** Tarea de documentación detectada. Caveman desactivado temporalmente. Iniciando Escuadrón...\n")
                process_chunk(1)
              else
                log("> ✅ **Plan Aprobado por el Usuario. Iniciando Escuadrón (Ollama)...**\n")
                process_chunk(1)
              end
            end
          end

          telegram.poll_for_reply(function(reply)
            process_feedback(reply, true)
          end, function()
            log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
            telegram.stop_polling()
            stop_inhibit()
            if not feedback_processed then
               feedback_processed = true
               local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
               vim.api.nvim_feedkeys(esc, "n", false)
            end
          end)

          vim.ui.input({ prompt = "Feedback al Arquitecto (Vacío para APROBAR): " }, function(feedback)
            process_feedback(feedback, false)
          end)
        end)
      end

      call_cloud(architecture_prompt, function(arch_response)
        if arch_response:match("^ERROR") then
          log(arch_response)
          log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud. Fallback a Ollama...\n")
          call_ollama(get_local_models()[1], architecture_prompt, function(fallback_arch)
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