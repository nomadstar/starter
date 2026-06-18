local M = {}
local api = require("plugins.ai_router.api")
local ui = require("plugins.ai_router.ui")
local utils = require("plugins.ai_router.utils")

function M.process_chunk(chunk_index, files, arch_response, file_purposes, final_prompt, on_complete)
  if chunk_index > #files then
    ui.log("\n> 🎯 **Todos los archivos han sido generados y guardados en disco.**")
    ui.log("> 📄 El estado final de la memoria se ha guardado en `.ai_router_state.md`")
    ui.dump_state(nil, chunk_index, arch_response, files)
    on_complete()
    return
  end

  local current_file = files[chunk_index]
  ui.log("\n> 📦 **Procesando archivo (" .. chunk_index .. "/" .. #files .. "):** `" .. current_file .. "`")
  ui.dump_state(current_file, chunk_index, arch_response, files)

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
  local max_iter = tonumber(utils.get_env("AGENT_MAX_ITERATIONS", "3")) or 3

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
      .. "Overall Project Goal: " .. final_prompt .. "\n\n"
      .. "CRITICAL INSTRUCTIONS FOR MODE STANDARD:\n"
      .. "- Do NOT use placeholders or omit ANY code. Write the full file.\n"
      .. "- Ensure the code strictly adheres to the architecture plan.\n"
      .. approved_context
  end

  local function do_iteration(comments, previous_code, force_model)
    local local_models = utils.get_local_models()
    if force_model then
      local_models = { force_model }
    end

    local model_idx = 1
    local current_code = previous_code

    local function run_next_model()
      if model_idx > #local_models then
        -- Forward declare or call finish_relay
        M.finish_relay(current_code, current_file, file_purposes, iter_count, max_iter, approved_context, comments, local_models, function(next_action, patch, best_model, suggested_subtasks)
          vim.schedule(function()
            vim.cmd("redraw")
            local stop_beep = ui.start_attention_beeper()
            local telegram = require("plugins.ai_router.telegram")
            local code_logged = false

            local process_human_feedback
            local ask_human_approval
            local process_subtasks_feedback
            local ask_subtasks_approval

            process_human_feedback = function(feedback, from_telegram)
              stop_beep()
              telegram.stop_polling()

              if from_telegram then
                vim.schedule(function()
                  local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
                  vim.api.nvim_feedkeys(esc, "n", false)
                end)
              end

              if feedback == false then return end -- Aborted locally

              if feedback and (feedback:match("^/question") or feedback:match("^/q ")) then
                local question = feedback:gsub("^/question%s*", ""):gsub("^/q%s*", "")
                ui.log("\n> 🗣️ **[Humano -> Arquitecto]**: " .. question)
                local q_prompt = "You are the Cloud Architect. The user asks a question about the code for " .. current_file .. ".\n\nUSER QUESTION:\n" .. question .. "\n\nCODE CONTEXT:\n" .. patch
                require("plugins.ai_router.api").call_cloud(q_prompt, function(ans)
                   ui.log("\n> ☁️ **[Arquitecto Responde]**:\n" .. ans .. "\n")
                   ask_human_approval()
                end)
                return
              end

              if feedback and feedback ~= "" and feedback ~= "/approve" and feedback ~= "/ok" then
                ui.log("> 🧑‍💼 **[Director Humano]** Rechaza el archivo y exige: " .. feedback)
                ui.log("\n---\n")
                -- Treat human feedback as a retry constraint
                iter_count = iter_count + 1
                telegram.start_background_monitor()
                do_iteration(feedback, current_code, nil)
              else
                -- Human approved (Empty feedback or /approve)
                if next_action == "next_chunk" then
                  if suggested_subtasks and #suggested_subtasks > 0 then
                    ask_subtasks_approval(suggested_subtasks)
                  else
                    M.process_chunk(chunk_index + 1, files, arch_response, file_purposes, final_prompt, on_complete)
                  end
                elseif next_action == "retry" then
                  iter_count = iter_count + 1
                  if iter_count > max_iter then
                    ui.log("\n### ⚠️ [Sistema] Máximo de iteraciones alcanzado para " .. current_file .. ". Aceptando tal como está.")
                    if utils.save_file_native(current_file, patch) then
                       ui.log("### 💾 Guardado en disco: `" .. current_file .. "`")
                    end
                    M.process_chunk(chunk_index + 1, files, arch_response, file_purposes, final_prompt, on_complete)
                  else
                    ui.log("\n---\n")
                    telegram.start_background_monitor()
                    do_iteration(patch, current_code, best_model)
                  end
                end
              end
            end

            ask_human_approval = function()
              local prompt_msg = "¿Aprobar " .. current_file .. "? (Vacío=SI, Texto=Corregir, /q=Duda): "
              if next_action == "retry" then
                prompt_msg = "Reescribir " .. current_file .. " (Vacío=Permitir, Texto=Añadir feedback, /q=Duda): "
              end
              
              telegram.stop_background_monitor()

              if not code_logged then
                ui.log("\n### 📝 Contenido Propuesto para `" .. current_file .. "`:\n```\n" .. (patch or "") .. "\n```\n")
                code_logged = true
              end
              ui.log("⏳ **Esperando decisión del Director Humano...** (Responde en Neovim o envía /approve en Telegram)\n")

              local feedback_processed = false
              telegram.poll_for_reply(function(reply)
                if feedback_processed then return end
                feedback_processed = true
                process_human_feedback(reply, true)
              end, function()
                ui.log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
                telegram.stop_polling()
                if not feedback_processed then
                   feedback_processed = true
                   local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
                   vim.api.nvim_feedkeys(esc, "n", false)
                end
              end)

              vim.ui.input({ prompt = prompt_msg }, function(feedback)
                if feedback_processed then return end
                feedback_processed = true
                process_human_feedback(feedback, false)
              end)
            end
            
            process_subtasks_feedback = function(feedback, from_telegram, subtasks)
              stop_beep()
              telegram.stop_polling()

              if from_telegram then
                vim.schedule(function()
                  local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
                  vim.api.nvim_feedkeys(esc, "n", false)
                end)
              end
              
              if feedback == false then return end -- Aborted locally

              if feedback and (feedback:match("^/question") or feedback:match("^/q ")) then
                local question = feedback:gsub("^/question%s*", ""):gsub("^/q%s*", "")
                ui.log("\n> 🗣️ **[Humano -> Arquitecto]**: " .. question)
                local q_prompt = "You are the Cloud Architect. The user asks a question about the suggested subtasks:\n" .. question
                require("plugins.ai_router.api").call_cloud(q_prompt, function(ans)
                   ui.log("\n> ☁️ **[Arquitecto Responde]**:\n" .. ans .. "\n")
                   ask_subtasks_approval(subtasks)
                end)
                return
              end
              
              if feedback and feedback:match("^[Nn][Oo]") then
                ui.log("> 🧑‍💼 **[Director Humano]** Descarta las subtareas sugeridas.")
              else
                ui.log("> 🧑‍💼 **[Director Humano]** Aprueba añadir las " .. #subtasks .. " nuevas tareas a la cola.")
                -- Insert directly into the array after chunk_index
                for i = #subtasks, 1, -1 do
                  local subtask = subtasks[i]
                  if subtask.file and subtask.purpose then
                    table.insert(files, chunk_index + 1, subtask.file)
                    file_purposes[subtask.file] = subtask.purpose
                  end
                end
              end
              
              M.process_chunk(chunk_index + 1, files, arch_response, file_purposes, final_prompt, on_complete)
            end

            ask_subtasks_approval = function(subtasks)
              local prompt_msg = "¿Añadir " .. #subtasks .. " nuevas tareas? (Vacío=SI, No=Descartar, /q=Duda): "
              
              telegram.stop_background_monitor()

              ui.log("\n### 💡 El Arquitecto Cloud sugiere añadir " .. #subtasks .. " nuevas tareas derivadas de este archivo:")
              for _, st in ipairs(subtasks) do
                ui.log("- **" .. (st.file or "Unknown") .. "**: " .. (st.purpose or ""))
              end
              ui.log("\n⏳ **¿Añadirlas a la cola de trabajo?** (Vacío=SI, No=Descartar, /q=Preguntar algo)\n")

              local feedback_processed = false
              telegram.poll_for_reply(function(reply)
                if feedback_processed then return end
                feedback_processed = true
                process_subtasks_feedback(reply, true, subtasks)
              end, function()
                ui.log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
                telegram.stop_polling()
                if not feedback_processed then
                   feedback_processed = true
                   local esc = vim.api.nvim_replace_termcodes("<C-c>", true, false, true)
                   vim.api.nvim_feedkeys(esc, "n", false)
                end
              end)

              vim.ui.input({ prompt = prompt_msg }, function(feedback)
                if feedback_processed then return end
                feedback_processed = true
                process_subtasks_feedback(feedback, false, subtasks)
              end)
            end

            ask_human_approval()
          end)
        end)
        return
      end

      local current_model = local_models[model_idx]
      ui.log("> **[Ollama Local (" .. current_model .. ")]** Iteración " .. iter_count .. "/" .. max_iter .. ". Paso " .. model_idx .. "/" .. #local_models .. "...\n")

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

      api.call_ollama(current_model, ollama_prompt, function(code_response)
        if code_response:match("^ERROR") then
          ui.log("> ⚠️ **[Sistema]** Error (" .. code_response .. "). Saltando el modelo " .. current_model .. "...")
          model_idx = model_idx + 1
          run_next_model()
          return
        end
        current_code = code_response
        model_idx = model_idx + 1
        run_next_model()
      end)
    end

    run_next_model()
  end

  do_iteration(nil, nil)
end

function M.finish_relay(final_code, current_file, file_purposes, iter_count, max_iter, approved_context, comments, local_models, callback)
  final_code = final_code or ""
  ui.log("> **[Ollama Local]** Cadena completada (" .. current_file .. "). Auto-evaluando...\n")

  local self_review_prompt = "You are an AI Self-Reviewer. Review the code you just generated for " .. current_file .. ".\n\nCODE:\n" .. final_code .. "\n\nIdentify any obvious bugs, missing implementations, or placeholders. You MUST reply with a raw JSON object: {\"score\": 100, \"fixes\": \"list of fixes or empty\"}. Score 90-100 if perfect, <90 if there are issues."
  
  if vim.env.CAVEMAN_MODE == "true" then
    self_review_prompt = self_review_prompt .. "\nCAVEMAN MODE: Output ONLY the raw JSON object."
  end

  api.call_ollama(local_models[#local_models], self_review_prompt, function(self_review_response)
    local self_json_str = self_review_response:match("{.*}") or self_review_response
    local ok, data = pcall(vim.json.decode, self_json_str)
    local self_fixes = ""
    if ok and type(data) == "table" then
      self_fixes = data.fixes or ""
      if type(self_fixes) == "table" then self_fixes = vim.json.encode(self_fixes) end
    end

    ui.log("> **[Ollama Auto-Review]** Evaluado localmente. Enviando defensa al Arquitecto Cloud para veredicto final...\n")

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

    local model_list_str = table.concat(local_models, ", ")
    review_prompt = review_prompt .. "\n\nYou MUST reply with a raw JSON object and nothing else. Format:\n{\n  \"score\": 100,\n  \"fixes\": [\"list of fixes if any\"],\n  \"cooperation_notes\": \"notas breves sobre como colaboraron los modelos locales\",\n  \"cooperation_scores\": \"model1=80, model2=90\",\n  \"suggested_subtasks\": [{\"file\": \"path/to/new_file.md\", \"purpose\": \"reason for creation\"}]\n}\nIMPORTANT: Use the ACTUAL model names that participated (" .. model_list_str .. ") in the cooperation_scores string. If the code introduces concepts that are too dense and deserve their own dedicated file, propose them in suggested_subtasks (can be empty). If the code works perfectly, give a score of 90 to 100. If it has minor bugs, give 80 to 89. If it has major bugs, give < 80. The score MUST be a NUMERIC INTEGER."

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
      local suggested_subtasks = {}
      if ok2 and type(data2) == "table" then
        score = tonumber(data2.score) or 0
        fixes = data2.fixes or "Unknown error"
        coop_notes = data2.cooperation_notes or ""
        coop_scores = data2.cooperation_scores or ""
        if type(data2.suggested_subtasks) == "table" then
          suggested_subtasks = data2.suggested_subtasks
        end
        if type(fixes) == "table" then
          fixes = vim.json.encode(fixes)
        elseif type(fixes) ~= "string" then
          fixes = tostring(fixes)
        end
      else
        ui.log("\n> ⚠️ **[Sistema]** Falló el parseo JSON del Revisor. Asumiendo score 0.")
      end

      if coop_notes ~= "" then ui.log("> 🤝 **[Cooperación]** Notas: " .. coop_notes) end
      if coop_scores ~= "" then ui.log("> 📊 **[Cooperación]** Puntajes: " .. coop_scores) end

      if score >= 90 then
        ui.log("### ✅ [Arquitecto] Archivo `" .. current_file .. "` APROBADO (Score: " .. score .. ") en iteración " .. iter_count .. "!")
        if utils.save_file_native(current_file, final_code) then
           ui.log("### 💾 Guardado en disco: `" .. current_file .. "`")
        end
        callback("next_chunk", final_code, nil, suggested_subtasks)
      elseif score >= 80 then
        ui.log("### 🩹 [Arquitecto] Errores menores en " .. current_file .. " (Score: " .. score .. "). Delegando parche a Cloud Developer...")
        local patch_prompt = "You are a Developer. The code below has these minor issues:\n"
          .. fixes
          .. "\n\nCODE:\n"
          .. final_code
          .. "\n\nFix the code. Return the fixed code inside a markdown block. BEFORE the code block, briefly list the exact changes you made (verbose log)."

        api.call_cloud(patch_prompt, function(patch_response)
          if patch_response:match("^ERROR") then
            ui.log("\n> ⚠️ **[Sistema]** Falló el parche en la nube. Forzando iteración local...")
            callback("retry", fixes, nil)
            return
          end

          ui.log("\n> ☁️ **[Cloud Developer]** Cambios aplicados en `" .. current_file .. "`:\n" .. patch_response)
          local patched_code = patch_response:match("```[%w]*\n(.-)```") or patch_response
          ui.log("\n### ✅ [Sistema] Archivo `" .. current_file .. "` APROBADO vía parche Cloud!")
          if utils.save_file_native(current_file, patched_code) then
             ui.log("### 💾 Guardado en disco: `" .. current_file .. "`")
          end
          callback("next_chunk", patched_code, nil, suggested_subtasks)
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
        
        ui.log("### ❌ [Arquitecto] Revisión fallida para " .. current_file .. " (Score: " .. score .. "). Comentarios:\n" .. fixes)
        if best_model then
          ui.log("> 👑 El modelo **" .. best_model .. "** obtuvo el mejor puntaje de cooperación y liderará el parcheo.")
        end

        callback("retry", fixes, best_model, suggested_subtasks)
      end
    end

    api.call_cloud(review_prompt, function(review_response)
      if review_response:match("^ERROR") then
        ui.log(review_response)
        ui.log("\n> ⚠️ **[Sistema]** Falló el Revisor Cloud. Fallback a Ollama...\n")
        api.call_ollama(local_models[1], review_prompt, function(fallback_review)
          if fallback_review:match("^ERROR") then
            ui.log(fallback_review)
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

return M
