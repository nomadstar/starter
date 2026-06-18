local M = {}
local curl = require("plenary.curl")
local utils = require("plugins.ai_router.utils")

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

  -- Limpiar el markdown complejo que telegram no soporta bien
  local clean_text = text:gsub("```", ""):gsub("%*%(%*%", ""):gsub("%*%)%*%", "")

  curl.post(url, {
    body = vim.json.encode({
      chat_id = chat_id,
      text = clean_text,
    }),
    headers = {
      ["Content-Type"] = "application/json",
    },
    callback = function() end, -- Fire and forget
  })
end

local is_polling = false
local last_update_id = 0

function M.poll_for_reply(callback, on_kill)
  if not M.is_enabled() then return end
  if is_polling then return end

  is_polling = true
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local chat_id = utils.get_env("TELEGRAM_CHAT_ID")
  local url = "https://api.telegram.org/bot" .. token .. "/getUpdates"
  
  local start_time = os.time()

  local function do_poll()
    if not is_polling then return end

    curl.get(url .. "?offset=" .. (last_update_id + 1) .. "&timeout=10", {
      callback = function(res)
        if not is_polling then return end
        
        if res.status == 200 then
          local ok, data = pcall(vim.json.decode, res.body)
          if ok and data.ok and data.result then
            for _, update in ipairs(data.result) do
              last_update_id = update.update_id
              if update.message and update.message.chat and tostring(update.message.chat.id) == tostring(chat_id) and update.message.text then
                local msg_time = update.message.date or 0
                if msg_time >= start_time - 5 then
                  local text = update.message.text
                  if text == "/kill" then
                    is_polling = false
                    if on_kill then
                      vim.schedule(function() on_kill() end)
                    end
                    return
                  elseif text == "/approve" or text == "/ok" then
                    is_polling = false
                    vim.schedule(function() callback("") end)
                    return
                  else
                    -- Enviar cualquier otro texto como feedback
                    is_polling = false
                    vim.schedule(function() callback(text) end)
                    return
                  end
                end
              end
            end
          end
        end

        -- Continuar el poll si sigue activo
        if is_polling then
          vim.defer_fn(do_poll, 1000)
        end
      end
    })
  end

  do_poll()
end

function M.stop_polling()
  is_polling = false
end

local bg_polling = false

function M.start_background_monitor()
  if not M.is_enabled() then return end
  if is_polling or bg_polling then return end
  
  bg_polling = true
  local token = utils.get_env("TELEGRAM_BOT_TOKEN")
  local chat_id = utils.get_env("TELEGRAM_CHAT_ID")
  local url = "https://api.telegram.org/bot" .. token .. "/getUpdates"
  local start_time = os.time()
  
  local function do_bg_poll()
    if not bg_polling then return end
    curl.get(url .. "?offset=" .. (last_update_id + 1) .. "&timeout=10", {
      callback = function(res)
        if not bg_polling then return end
        if res.status == 200 then
          local ok, data = pcall(vim.json.decode, res.body)
          if ok and data.ok and data.result then
            for _, update in ipairs(data.result) do
              last_update_id = update.update_id
              if update.message and update.message.chat and tostring(update.message.chat.id) == tostring(chat_id) and update.message.text then
                local msg_time = update.message.date or 0
                if msg_time >= start_time - 5 then
                  if update.message.text == "/kill" then
                    bg_polling = false
                    require("plugins.ai_router.api").kill_all()
                    require("plugins.ai_router.ui").log("\n> 💀 **[Sistema]** Ejecución abortada remotamente vía Telegram (/kill).")
                    return
                  end
                end
              end
            end
          end
        end
        if bg_polling then vim.defer_fn(do_bg_poll, 1000) end
      end
    })
  end
  do_bg_poll()
end

function M.stop_background_monitor()
  bg_polling = false
end

return M
