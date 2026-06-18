local M = {}
local utils = require("plugins.ai_router.utils")
local telegram = require("plugins.ai_router.telegram")

local floating_buf = nil
local floating_win = nil

function M.create_floating_window()
  if floating_buf and vim.api.nvim_buf_is_valid(floating_buf) then
    if floating_win and vim.api.nvim_win_is_valid(floating_win) then
      return floating_buf, floating_win
    end
  else
    floating_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(floating_buf, "bufhidden", "hide")
    vim.api.nvim_buf_set_option(floating_buf, "filetype", "markdown")
    vim.api.nvim_buf_set_keymap(floating_buf, "n", "q", "<cmd>hide<CR>", { noremap = true, silent = true })
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local row = math.floor((vim.o.lines - height) / 2)
  local col = math.floor((vim.o.columns - width) / 2)

  floating_win = vim.api.nvim_open_win(floating_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = row,
    col = col,
    style = "minimal",
    border = "rounded",
    title = " 🤖 AI Router (Orquestador Multi-Agente) [q=Ocultar] ",
    title_pos = "center",
  })

  vim.api.nvim_win_set_option(floating_win, "wrap", true)
  return floating_buf, floating_win
end

function M.toggle_floating_window()
  if floating_win and vim.api.nvim_win_is_valid(floating_win) then
    vim.api.nvim_win_hide(floating_win)
  else
    if floating_buf and vim.api.nvim_buf_is_valid(floating_buf) then
      M.create_floating_window()
    else
      vim.notify("No hay ninguna sesión activa del Orquestador", vim.log.levels.INFO)
    end
  end
end

function M.log(msg)
  local buf = floating_buf
  
  -- Reenviar silenciosamente a Telegram
  telegram.send_message(msg)
  
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  local lines = vim.split(msg, "\n")
  vim.schedule(function()
    vim.api.nvim_buf_set_lines(buf, -1, -1, false, lines)
    if floating_win and vim.api.nvim_win_is_valid(floating_win) then
      local line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(floating_win, { line_count, 0 })
    end
  end)
end

function M.log_stream(msg)
  local buf = floating_buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then return end
  
  vim.schedule(function()
    local line_count = vim.api.nvim_buf_line_count(buf)
    local last_line = vim.api.nvim_buf_get_lines(buf, line_count - 1, line_count, false)[1] or ""
    
    local new_text = last_line .. msg
    local new_lines = vim.split(new_text, "\n")
    
    vim.api.nvim_buf_set_lines(buf, line_count - 1, line_count, false, new_lines)
    
    if floating_win and vim.api.nvim_win_is_valid(floating_win) then
      local current_line_count = vim.api.nvim_buf_line_count(buf)
      vim.api.nvim_win_set_cursor(floating_win, { current_line_count, 0 })
    end
  end)
end

function M.start_attention_beeper()
  local noisy = utils.get_env("AGENT_NOISY_MODE", "false")
  if noisy ~= "true" then return function() end end

  local sound_path = utils.get_env("AGENT_SOUND_PATH", "/usr/share/sounds/freedesktop/stereo/message.oga")
  local interval = tonumber(utils.get_env("AGENT_SOUND_INTERVAL", "5")) or 5
  local timer = vim.loop.new_timer()
  local is_running = true

  local function beep()
    if is_running then
      os.execute("paplay " .. sound_path .. " &")
      timer:start(interval * 1000, 0, vim.schedule_wrap(beep))
    end
  end

  beep()

  return function()
    is_running = false
    timer:stop()
    timer:close()
  end
end

function M.dump_state(current_file, chunk_index, arch_response, files)
  local state = "# 🧠 Memoria del Orquestador\n\n"
  state = state .. "## Plan del Arquitecto\n" .. (arch_response or "") .. "\n\n"
  state = state .. "## Memoria a Corto Plazo (Archivos Aprobados)\n"
  if chunk_index and files and chunk_index > 1 then
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

return M
