-- katas.solana_rust: provider for the Solana Rust VS Code course.
--
-- The framework (kata.nvim) calls `require("katas.solana_rust")` when
-- the user activates this course via `:Katas`. The returned table
-- satisfies the framework's provider contract; see the framework's
-- README ("Writing a provider") and `:help kata` for the full shape.
--
-- This file uses `kata.provider_factory` to build the provider from a
-- declarative spec. The CLI side is in cli.lua.

local factory = require("kata.provider_factory")
local cli     = require("katas.solana_rust.cli")

---Build the errorformat used by `:make` and the async check.
---
---Starts with a leading panic pattern ("thread '...' panicked at
---<file>:<line>:<col>:") so cargo test failures land in the quickfix
---list with a useful location; cargo's compiler output alone does not
---catch panics. The trailing list is Neovim's stock cargo errorformat
---adapted to also surface `assert_eq!` left/right diffs.
---@return string
local function errorformat()
  local cargo_efm = table.concat({
    "%-G",
    "%-Gerror: aborting %.%#",
    "%-Gerror: Could not compile %.%#",
    "%Eerror: %m",
    "%Eerror[E%n]: %m",
    "%Wwarning: %m",
    "%Inote: %m",
    "%C %#--> %f:%l:%c",
    "%E  left:%m",
    "%C right:%m %f:%l:%c",
    "%Z",
  }, ",")
  return "%Ethread '%.%#' panicked at %f:%l:%c:,%Z%m," .. cargo_efm
end

---Recover the exercise id from the path of an open buffer. Returns nil
---when the path is outside `exercises/<id>/src/`. The framework calls
---this from BufReadPost so per-exercise keymaps can attach.
---@param path string|nil
---@return string|nil
local function exercise_id_from_path(path)
  if not path then return nil end
  return path:match("/exercises/([^/]+)/src/")
end

---Cmdline completion for `:CourseUnmark <arg_lead>`. Pulls ids from the
---loaded item list (cached by activation), filters by prefix, sorts.
---@param arg_lead string|nil
---@return string[]
local function unmark_complete(arg_lead)
  local context = require("kata.context")
  local out = {}
  for _, item in ipairs(context.items()) do
    if vim.startswith(item.id, arg_lead or "") then
      out[#out + 1] = item.id
    end
  end
  table.sort(out)
  return out
end

return factory.new({
  name = "solana_rust",
  cli  = cli,

  config       = { runner = "cargo" },
  default_opts = { runner = "cargo" },
  root         = { marker = "course.toml" },

  paths = {
    exercise = "exercises/{id}/src/lib.rs",
    lesson   = "{lesson}",
    manifest = "exercises/{id}/Cargo.toml",
    pattern  = "exercises/*/src/*.rs",
  },

  compiler = "cargo",
  makeprg  = "cargo test --manifest-path {root}/{manifest} --quiet",

  methods = {
    solution       = { run = "solution",      id = true },
    mark_completed = { run = "progress_mark", id = true },
    list_completed = { run = "progress_list"            },

    list = function(ctx, cb)
      ctx.run("metadata", function(data, _err)
        cb(data and data.exercise or {})
      end)
    end,

    check = function(ctx, item, cb)
      ctx.run("check", item.id, function(ok, stdout, stderr)
        cb(ok, (stdout or "") .. "\n" .. (stderr or ""))
      end)
    end,

    hint = function(ctx, item, n, cb)
      ctx.run("hint", item.id, n, cb)
    end,
  },

  commands = {
    CourseBuild = function(ctx)
      ctx.notify("Building course-runner...")
      ctx.system({ "cargo", "build", "-p", "course-runner" }, function(res)
        if res.code == 0 then
          ctx.state.runner = ctx.root() .. "/target/debug/course-runner"
          ctx.notify("Built. runner -> " .. ctx.state.runner)
        else
          ctx.error("Build failed:\n" .. (res.stderr or ""))
        end
      end)
    end,

    CourseReset = {
      fn = function(ctx, args)
        local function do_reset()
          ctx.notify("Resetting course...")
          ctx.run("reset", function(ok, _stdout, stderr)
            if ok then
              vim.cmd("silent! checktime")
              ctx.notify("Reset complete")
            else
              ctx.error("Reset failed: " .. (stderr or ""))
            end
          end)
        end
        if args and args.bang then do_reset(); return end
        local choice = vim.fn.confirm(
          "Reset overwrites all exercise files with baseline AND clears progress. Continue?",
          "&Yes\n&No", 2, "Warning")
        if choice == 1 then do_reset() end
      end,
      opts = { bang = true },
    },

    CourseUnmark = {
      fn = function(ctx, args)
        local id = args and args.args
        if not id or id == "" then
          ctx.notify("Usage: :CourseUnmark <exercise_id>")
          return
        end
        ctx.run("progress_unmark", id, function(ok)
          if ok then
            ctx.notify("Unmarked: " .. id)
          else
            ctx.error("Failed to unmark: " .. id)
          end
        end)
      end,
      opts = { nargs = 1, complete = unmark_complete },
    },
  },

  extra = function(M)
    M.errorformat            = errorformat
    M.exercise_id_from_path  = exercise_id_from_path
  end,
})
