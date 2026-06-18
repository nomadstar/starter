local M = {}
local telegram = require("plugins.ai_router.telegram")
local utils = require("plugins.ai_router.utils")
local ui = require("plugins.ai_router.ui")
local api = require("plugins.ai_router.api")
local relay = require("plugins.ai_router.relay")

function M.start_orchestration()
  vim.api.nvim_create_user_command("AiRouterKill", function()
    require("plugins.ai_router.api").kill_all()
    require("plugins.ai_router.ui").log("\n> 💀 **[Sistema]** Ejecución abortada localmente (AiRouterKill).")
  end, {})
  
  vim.api.nvim_create_user_command("AiRouterToggle", function()
    require("plugins.ai_router.ui").toggle_floating_window()
  end, {})

  local buf, win = ui.create_floating_window()

  vim.ui.input({ prompt = "Prompt para Arquitecto: " }, function(user_prompt)
    if not utils.is_valid_response(user_prompt) then
      vim.notify("Prompt cancelado o vacío", vim.log.levels.WARN)
      return
    end
    
    -- Reset kill switch
    _G.AI_ROUTER_KILLED = false
    
    -- Bloquear hibernación mientras dura la orquestación
    utils.prevent_sleep()

    ui.log("# ORQUESTADOR MULTI-AGENTE INICIADO\n**Meta:** " .. user_prompt .. "\n")
    
      local function process_urls_and_continue(prompt, on_fetch_done)
      local urls = {}
      for url in prompt:gmatch("https?://[%w-_%.%?%.:/%+=&]+") do
        table.insert(urls, url)
      end
      
      local local_paths = {}
      for path in prompt:gmatch("@([%w-_%.%?%.:/%+~\\]+)") do
        table.insert(local_paths, path)
      end

      local current_prompt = prompt

      if #local_paths > 0 then
        ui.log("> 📂 **[Sistema]** Detectados " .. #local_paths .. " paths locales. Inyectando contexto...")
        for _, path in ipairs(local_paths) do
          local context = utils.read_local_context(path)
          if context == "" then
             ui.log("> ❌ **[Sistema]** Falló al leer el archivo o carpeta: " .. path)
          else
             ui.log("> 🟢 Archivo inyectado: " .. path)
             current_prompt = current_prompt .. context
          end
        end
      end

      if #urls == 0 then
        on_fetch_done(current_prompt)
        return
      end

      ui.log("> 🌐 **[Sistema]** Detectadas " .. #urls .. " URLs. Obteniendo contexto vía Jina Reader (timeout 10s)...")
      local current_prompt = prompt
      local urls_fetched = 0

      for _, url in ipairs(urls) do
        utils.jina_fetch(url, function(content)
          if content:match("^ERROR") then
            ui.log("> ❌ **[Sistema]** Falló al obtener: " .. url)
          else
            ui.log("> 🟢 Descarga exitosa: " .. url)
            current_prompt = current_prompt .. "\n\n--- CONTENIDO DE " .. url .. " ---\n" .. content
          end
          urls_fetched = urls_fetched + 1
          if urls_fetched == #urls then
            on_fetch_done(current_prompt)
          end
        end)
      end
    end

    process_urls_and_continue(user_prompt, function(final_prompt)
      ui.log("> **[Arquitecto Cloud]** Analizando petición para minimizar tokens...\n")

      local architecture_prompt = "You are an Expert AI Software Architect.\n"
        .. "Analyze this request:\n"
        .. final_prompt
        .. "\n\nDECIDE THE BEST APPROACH:\n"
        .. "If the request is simple and can be done in 1 file with < 100 lines: Output EXACTLY this:\n"
        .. "MODE: FAST\n"
        .. "CODE: [Write the raw code inside markdown blocks]\n\n"
        .. "If the request is strictly about writing massive markdown documentation, READMEs, or manifestos: Output EXACTLY this:\n"
        .. "MODE: DOCS\n"
        .. "[FILE] path/to/doc.md | {description of document}\n\n"
        .. "Otherwise, output a strict execution plan like this:\n"
        .. "[FILE] path/to/file1.lua | {one-line purpose}\n"
        .. "[FILE] path/to/file2.rs | {one-line purpose}\n"
        .. "\nFailure to format as [FILE] path | purpose will BREAK the downstream parser."

      if vim.env.CAVEMAN_MODE == "true" then
        architecture_prompt = architecture_prompt .. "\n\nCAVEMAN MODE: Do NOT add greetings, summaries, or Markdown headings. ONLY output the [FILE] lines."
      end

      local function start_fast_track(arch_response)
        local code = arch_response:match("CODE:%s*```[%w]*\n(.-)```") or arch_response
        utils.save_file_native("fast_track_output.txt", code)
        ui.log("### 💾 Guardado en disco: `fast_track_output.txt`")
      end

      local function execute_architecture(arch_response)
        ui.log("> **[Arquitecto] Plan generado:**\n" .. arch_response .. "\n---\n")

        local files = {}
        local file_purposes = {}

        for line in arch_response:gmatch("[^\r\n]+") do
          local file_path, purpose = line:match("%[FILE%]%s*([^|]+)%|%s*(.+)")
          if file_path and purpose then
            file_path = vim.trim(file_path)
            table.insert(files, file_path)
            file_purposes[file_path] = vim.trim(purpose)
          end
        end

        if #files == 0 and not arch_response:match("^[Mm][Oo][Dd][Ee]:%s*[Ff][Aa][Ss][Tt]") then
          ui.log("> ⚠️ **[Sistema]** No se detectaron archivos [FILE] en el plan. Abortando. Revisa el log del Arquitecto.")
          utils.allow_sleep()
          return
        end

        local function start_relay()
          telegram.start_background_monitor()
          relay.process_chunk(1, files, arch_response, file_purposes, final_prompt, function()
            telegram.stop_background_monitor()
            utils.allow_sleep()
            ui.log("\n> 🎉 **[Orquestador] Tarea completamente finalizada.**")
          end)
        end

        vim.schedule(function()
          vim.cmd("redraw")
          local stop_beep = ui.start_attention_beeper()

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
              ui.log("> **[Usuario] Feedback al Arquitecto:** " .. feedback .. "\n")
              ui.log("> **[Arquitecto Cloud]** Revisando plan...\n")

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

              api.call_cloud(revision_prompt, function(revised_response)
                if revised_response:match("^ERROR") then
                  ui.log(revised_response)
                  ui.log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud en la revisión. Fallback a Ollama...\n")
                  api.call_ollama(utils.get_local_models()[1], revision_prompt, function(fallback_rev)
                    if fallback_rev:match("^ERROR") then
                      ui.log(fallback_rev)
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
                ui.log("> ⚡ **[Fast Track]** Tarea simple detectada. Guardando archivo(s) nativamente...\n")
                start_fast_track(arch_response)
              elseif arch_response:match("^[Mm][Oo][Dd][Ee]:%s*[Dd][Oo][Cc][Ss]") then
                ui.log("> 📚 **[Docs Mode]** Tarea de documentación detectada. Caveman desactivado temporalmente. Iniciando Escuadrón...\n")
                start_relay()
              else
                ui.log("> ✅ **Plan Aprobado por el Usuario. Iniciando Escuadrón (Ollama)...**\n")
                start_relay()
              end
            end
          end

          telegram.poll_for_reply(function(reply)
            process_feedback(reply, true)
          end, function()
            ui.log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
            telegram.stop_polling()
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

      api.call_cloud(architecture_prompt, function(arch_response)
        if arch_response:match("^ERROR") then
          ui.log(arch_response)
          ui.log("\n> ⚠️ **[Sistema]** Falló el Arquitecto Cloud. Fallback a Ollama...\n")
          api.call_ollama(utils.get_local_models()[1], architecture_prompt, function(fallback_arch)
            if fallback_arch:match("^ERROR") then
              ui.log(fallback_arch)
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
