local M = {}
local ui = require("plugins.ai_router.ui")

local function run_cmd(cmd)
  local output = vim.fn.system(cmd)
  local err = vim.v.shell_error
  return err == 0, output
end

local function get_worktree_path()
  local cwd = vim.fn.getcwd()
  -- Use a simple hash to avoid path collisions, or just replace slashes
  local safe_cwd = cwd:gsub("[^%w]", "_")
  return vim.fn.stdpath("data") .. "/ai_router_nightly/" .. safe_cwd
end

function M.ensure_ready()
  local cwd = vim.fn.getcwd()
  
  -- 1. Check if git repo exists
  if vim.fn.isdirectory(cwd .. "/.git") == 0 then
    run_cmd("git init")
    ui.log("> 🛠️ **[Git Safety]** Inicializado nuevo repositorio git en " .. cwd)
  end

  -- 2. Check if HEAD is valid (repo has at least one commit)
  local ok, _ = run_cmd("git rev-parse HEAD")
  if not ok then
    run_cmd("git commit --allow-empty -m 'Initial commit'")
    ui.log("> 🛠️ **[Git Safety]** Creado commit inicial vacío para habilitar ramas.")
  end

  -- 3. Check if nightly branch exists
  local has_nightly, _ = run_cmd("git show-ref --verify refs/heads/nightly")
  if not has_nightly then
    run_cmd("git branch nightly")
    ui.log("> 🛠️ **[Git Safety]** Creada rama 'nightly'.")
  end

  -- 4. Setup worktree
  local wt_path = get_worktree_path()
  if vim.fn.isdirectory(wt_path) == 0 then
    -- Ensure parent dir exists
    vim.fn.mkdir(vim.fn.stdpath("data") .. "/ai_router_nightly", "p")
    local success, out = run_cmd("git worktree add " .. vim.fn.shellescape(wt_path) .. " nightly")
    if success then
      ui.log("> 🛠️ **[Git Safety]** Worktree montado en " .. wt_path)
    else
      ui.log("> ⚠️ **[Git Safety]** Fallo al montar worktree: " .. (out or ""))
    end
  end
  return wt_path
end

function M.commit_nightly(filepath, purpose)
  if not require("plugins.ai_router.utils").is_midnight_monster_active() then
    return -- Only auto-commit during midnight monster
  end

  local wt_path = M.ensure_ready()
  local cwd = vim.fn.getcwd()
  
  -- The filepath could be absolute or relative. Let's make sure we have the relative path.
  local rel_path = filepath
  if vim.startswith(filepath, cwd) then
    rel_path = filepath:sub(#cwd + 2)
  end

  -- Copy the newly saved file to the worktree
  local source_file = cwd .. "/" .. rel_path
  local target_file = wt_path .. "/" .. rel_path

  -- Ensure directory exists in worktree
  local target_dir = vim.fn.fnamemodify(target_file, ":h")
  if vim.fn.isdirectory(target_dir) == 0 then
    vim.fn.mkdir(target_dir, "p")
  end

  -- Copy file content
  local f_in = io.open(source_file, "r")
  if not f_in then return false end
  local content = f_in:read("*a")
  f_in:close()

  local f_out = io.open(target_file, "w")
  if not f_out then return false end
  f_out:write(content)
  f_out:close()

  -- Git add and commit inside worktree
  local add_cmd = "cd " .. vim.fn.shellescape(wt_path) .. " && git add " .. vim.fn.shellescape(rel_path)
  run_cmd(add_cmd)

  local msg = "Auto-approved by MidnightMonster: " .. rel_path .. "\n\nPurpose: " .. (purpose or "N/A")
  local commit_cmd = "cd " .. vim.fn.shellescape(wt_path) .. " && git commit -m " .. vim.fn.shellescape(msg)
  local success, out = run_cmd(commit_cmd)

  if success then
    ui.log("> 🛡️ **[Auditoría]** Auto-commit realizado en rama `nightly`: `" .. rel_path .. "`")
  else
    ui.log("> ⚠️ **[Auditoría]** Falló el commit nocturno: " .. (out or ""))
  end

  return success
end

return M
