-- Async wrappers around the course-runner CLI subcommands.
--
-- Stateless: every function takes an `opts` table that says which
-- runner binary to invoke and which directory to invoke it in. The
-- provider in init.lua threads that table through automatically; you
-- only call this module directly if you are scripting against the CLI
-- from outside the provider (tests, ad hoc commands).
--
-- All callbacks fire on the main loop (vim.schedule) so it is safe to
-- touch the UI from inside them.

---@class katas.solana_rust.cli.Opts
---@field runner string  Either the literal "cargo" (use `cargo run -p course-runner --`) or an absolute path to a prebuilt course-runner binary.
---@field cwd    string  Absolute path to the course root (the directory containing course.toml).

local M = {}

---Build the argv that runs `course-runner <args...>`, choosing between
---`cargo run` and a direct binary call based on `runner`.
---@param runner string
---@param args   string[]
---@return string[]
local function build_cmd(runner, args)
  if runner == "cargo" then
    local full = { "cargo", "run", "-p", "course-runner", "--" }
    for _, a in ipairs(args) do full[#full + 1] = a end
    return full
  else
    local full = { runner }
    for _, a in ipairs(args) do full[#full + 1] = a end
    return full
  end
end

---Spawn the runner with `args`, then fire `callback(exit_code, stdout, stderr)`
---on the main loop.
---@param opts     katas.solana_rust.cli.Opts
---@param args     string[]
---@param callback fun(code: integer, stdout: string, stderr: string)
local function run(opts, args, callback)
  vim.system(build_cmd(opts.runner, args), { cwd = opts.cwd, text = true },
    function(result)
      vim.schedule(function()
        callback(result.code, result.stdout or "", result.stderr or "")
      end)
    end)
end

---Fetch the parsed `metadata` JSON (course title, exercise list, etc.).
---On failure, `data` is nil and `err` carries a short reason.
---@param opts     katas.solana_rust.cli.Opts
---@param callback fun(data: table|nil, err: string|nil)
function M.metadata(opts, callback)
  run(opts, { "metadata" }, function(code, stdout, _stderr)
    if code ~= 0 then callback(nil, "metadata failed (exit " .. code .. ")") return end
    local ok, data = pcall(vim.json.decode, stdout)
    if ok then callback(data, nil) else callback(nil, "json parse failed") end
  end)
end

---List the ids of completed exercises. Returns an empty list on any
---failure (the CLI handles the missing-file case itself).
---@param opts     katas.solana_rust.cli.Opts
---@param callback fun(ids: string[])
function M.progress_list(opts, callback)
  run(opts, { "progress", "list" }, function(code, stdout, _stderr)
    if code ~= 0 then callback({}) return end
    local ok, data = pcall(vim.json.decode, stdout)
    callback(ok and data or {})
  end)
end

---Mark `id` as completed. Idempotent on the CLI side.
---@param opts     katas.solana_rust.cli.Opts
---@param id       string
---@param callback fun(ok: boolean)|nil
function M.progress_mark(opts, id, callback)
  run(opts, { "progress", "mark", id }, function(code, _stdout, _stderr)
    if callback then callback(code == 0) end
  end)
end

---Remove `id` from the completed set. No-op on the CLI side if the id
---was not present.
---@param opts     katas.solana_rust.cli.Opts
---@param id       string
---@param callback fun(ok: boolean)|nil
function M.progress_unmark(opts, id, callback)
  run(opts, { "progress", "unmark", id }, function(code, _stdout, _stderr)
    if callback then callback(code == 0) end
  end)
end

---Restore exercises from the baseline and clear progress.
---@param opts     katas.solana_rust.cli.Opts
---@param callback fun(ok: boolean, stdout: string, stderr: string)|nil
function M.reset(opts, callback)
  run(opts, { "reset", "--yes" }, function(code, stdout, stderr)
    if callback then callback(code == 0, stdout, stderr) end
  end)
end

---Run `check` against `id` and report success plus the merged
---stdout/stderr stream the framework wants to feed into quickfix.
---@param opts     katas.solana_rust.cli.Opts
---@param id       string
---@param callback fun(ok: boolean, stdout: string, stderr: string)
function M.check(opts, id, callback)
  run(opts, { "check", id }, function(code, stdout, stderr)
    callback(code == 0, stdout, stderr)
  end)
end

---Fetch hint number `n` for exercise `id`. The callback receives the
---hint text on success or nil on failure.
---@param opts     katas.solana_rust.cli.Opts
---@param id       string
---@param n        integer
---@param callback fun(text: string|nil)
function M.hint(opts, id, n, callback)
  run(opts, { "hint", id, tostring(n) }, function(code, stdout, _stderr)
    callback(code == 0 and stdout or nil)
  end)
end

---Fetch the canonical solution for exercise `id`.
---@param opts     katas.solana_rust.cli.Opts
---@param id       string
---@param callback fun(text: string|nil)
function M.solution(opts, id, callback)
  run(opts, { "solution", id }, function(code, stdout, _stderr)
    callback(code == 0 and stdout or nil)
  end)
end

return M
