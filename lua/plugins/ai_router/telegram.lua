local M = {}
local curl = require("plenary.curl")
local utils = require("plugins.ai_router.utils")

local last_update_id = 0
local active_poll_id = 0
local polling_mode = nil -- "reply", "background", or nil

local last_msg_len = 0
local function check_neovim_errors()
  local ok, msgs = pcall(vim.fn.execute, "messages")
  if not ok or type(msgs) ~= "string" then return end

  if #msgs < last_msg_len then last_msg_len = 0 end

  if #msgs > last_msg_len then
    local new_msgs = msgs:sub(last_msg_len + 1)
    last_msg_len = #msgs

    if new_msgs:match("Error") or new_msgs:match("stack traceback:") or new_msgs:match("attempt to") then
      local safe_msg = new_msgs:sub(1, 3500)
      M.send_message("🔥 **[NVIM ERROR]**\n```text\n" .. safe_msg .. "\n```")
    end
  end
end

function M.is_enabled()
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local chat_id = utils.get_env("TELEGRAM_CHAT_ID")
  return token ~= "" and chat_id ~= ""
end

function M.send_message(text)
  if not M.is_enabled() then return end
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local chat_id = utils.get_env("TELEGRAM_CHAT_ID")
  local url = "https://api.telegram.org/bot" .. token .. "/sendMessage"

  local clean_text = text:gsub("```", ""):gsub("%*%*", "")
  local chunk_size = 4000
  
  local function send_chunk(start_idx)
    if start_idx > #clean_text then return end
    local chunk = clean_text:sub(start_idx, start_idx + chunk_size - 1)
    
    curl.post(url, {
      body = vim.json.encode({ chat_id = chat_id, text = chunk }),
      headers = { ["Content-Type"] = "application/json" },
      callback = function() send_chunk(start_idx + chunk_size) end,
      on_error = function(err) end,
    })
  end

  send_chunk(1)
end

local function run_poll_loop(mode_id, start_time, on_reply_cb, on_kill_cb)
  if polling_mode == nil or active_poll_id ~= mode_id then return end
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local chat_id = utils.get_env("TELEGRAM_CHAT_ID")
  local url = "https://api.telegram.org/bot" .. token .. "/getUpdates"

  check_neovim_errors()

  curl.get(url .. "?offset=" .. (last_update_id + 1) .. "&timeout=10", {
    callback = function(res)
      vim.schedule(function()
        if polling_mode == nil or active_poll_id ~= mode_id then return end
        
        if res.status == 200 then
          local ok, data = pcall(vim.json.decode, res.body)
          if ok and data.ok and data.result then
            for _, update in ipairs(data.result) do
              last_update_id = update.update_id
              if update.message and update.message.chat and tostring(update.message.chat.id) == tostring(chat_id) and update.message.text then
                local msg_time = update.message.date or 0
                if msg_time >= start_time - 30 then
                  local text = update.message.text
                  if text:match("^/cat ") or text:match("^/get ") then
                    local file_path = text:match("^/%a+ (.+)$")
                    if file_path then
                      file_path = vim.trim(file_path)
                      local stat = vim.loop.fs_stat(file_path)
                      if stat and stat.type == "file" then
                        local cmd = string.format("curl -s -X POST https://api.telegram.org/bot%s/sendDocument -F chat_id=%s -F document=@%s", token, chat_id, vim.fn.shellescape(file_path))
                        vim.fn.jobstart(cmd)
                      else
                        M.send_message("❌ Error: '" .. file_path .. "' no es un archivo válido o es una carpeta completa.")
                      end
                    end
                  elseif text == "/kill" then
                    polling_mode = nil
                    if on_kill_cb then on_kill_cb() end
                    return
                  elseif polling_mode == "reply" then
                    if text == "/approve" or text == "/ok" or text:lower() == "ok" or text:lower() == "si" or text:lower() == "yes" or text:lower() == "y" then
                      polling_mode = nil
                      if on_reply_cb then on_reply_cb("") end
                      return
                    else
                      polling_mode = nil
                      if on_reply_cb then on_reply_cb(text) end
                      return
                    end
                  end
                end
              end
            end
          end
        end
        if polling_mode ~= nil and active_poll_id == mode_id then
          vim.defer_fn(function() run_poll_loop(mode_id, start_time, on_reply_cb, on_kill_cb) end, 1000)
        end
      end)
    end,
    on_error = function(err)
      if polling_mode ~= nil and active_poll_id == mode_id then
        vim.defer_fn(function() run_poll_loop(mode_id, start_time, on_reply_cb, on_kill_cb) end, 2000)
      end
    end
  })
end

function M.poll_for_reply(callback, on_kill)
  if not M.is_enabled() then return end
  active_poll_id = active_poll_id + 1
  polling_mode = "reply"
  run_poll_loop(active_poll_id, os.time(), callback, on_kill)
end

function M.stop_polling()
  if polling_mode == "reply" then polling_mode = nil end
end

function M.start_background_monitor()
  if not M.is_enabled() then return end
  active_poll_id = active_poll_id + 1
  polling_mode = "background"
  run_poll_loop(active_poll_id, os.time(), nil, function()
    require("plugins.ai_router.api").kill_all()
    require("plugins.ai_router.ui").log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
  end)
end

function M.stop_background_monitor()
  if polling_mode == "background" then polling_mode = nil end
end

function M.update_bot_commands()
  if not M.is_enabled() then
    vim.notify("Telegram no está configurado en .env", vim.log.levels.WARN)
    return
  end
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local url = "https://api.telegram.org/bot" .. token .. "/setMyCommands"
  local commands = {
    commands = {
      {command = "kill", description = "Abortar ejecución remotamente"},
      {command = "approve", description = "Aprobar archivo actual"},
      {command = "get", description = "Descargar archivo local (/get <ruta>)"},
      {command = "cat", description = "Descargar archivo local (/cat <ruta>)"},
      {command = "q", description = "Hacer pregunta al Arquitecto (/q <pregunta>)"}
    }
  }

  curl.post(url, {
    body = vim.json.encode(commands),
    headers = { ["Content-Type"] = "application/json" },
    callback = function(res)
      if res.status == 200 then
        vim.schedule(function() vim.notify("Comandos de Telegram actualizados con éxito", vim.log.levels.INFO) end)
      else
        vim.schedule(function() vim.notify("Error al actualizar comandos Telegram: " .. tostring(res.body), vim.log.levels.ERROR) end)
      end
    end
  })
end

return M
