# solana_rust kata provider

A Neovim provider plugin that drives this Solana Rust course through
[kata.nvim](https://github.com/cds-io/kata-framework). It is a thin
adapter over the `course-runner` CLI in `crates/course-runner`; the
framework owns the picker, popups, quickfix wiring, and buffer
keymaps, so this plugin's job is just to know how to talk to the
runner and what to advertise to the framework.

## What it ships

Two modules under `lua/katas/solana_rust/`:

- `cli.lua`: async wrappers around the course-runner subcommands
  (`metadata`, `progress {list,mark,unmark}`, `reset`, `check`,
  `hint`, `solution`) via `vim.system`. Stateless; the caller threads
  `{ runner, cwd }` through `opts` so the same wrapper works whether
  you are invoking `cargo run -p course-runner` during development or
  a prebuilt binary in everyday use.
- `init.lua`: the provider definition, built from
  `kata.provider_factory`. Wires the CLI into the framework's method
  shape, declares the cargo compiler, pins `makeprg` to the per-
  exercise `Cargo.toml`, and ships an `errorformat` tuned for cargo
  with a leading panic pattern so test panics populate the quickfix
  list. Adds three user commands (`:CourseBuild`, `:CourseReset`,
  `:CourseUnmark`) on activation.

The full UI surface (picker, hint cycling, quickfix-driven check,
buffer-local `<localleader>c{c,h,s,l}`, `:make` integration) comes
from the framework. See its README and `:help kata` for that.

## Requirements

- Neovim 0.10+ (uses `vim.system`)
- [cds-io/kata-framework](https://github.com/cds-io/kata-framework)
- A clone of this course repo with `course.toml` at the root, plus
  either a Rust toolchain (so `cargo run -p course-runner` works) or
  a prebuilt `course-runner` binary

## Installation

The provider lives in this repo under `neovim/`, alongside the course
content. With lazy.nvim, point at the `neovim/` subdirectory as a
local plugin and let the framework spec own the kata wiring:

```lua
return {
  -- 1) Framework. opts.katas is the source of truth for what courses
  --    are installed; lazy passes opts to require('kata').setup(opts).
  {
    "cds-io/kata-framework",
    opts = {
      katas = {
        solana_rust = "~/dev/solana-rust-vscode-course",
      },
    },
    keys = {
      { "<leader>sk", "<cmd>Katas<CR>", desc = "Pick kata course" },
    },
  },

  -- 2) This provider. Pure provider module on rtp; no setup, no
  --    triggers. The framework requires `katas.solana_rust` when the
  --    user activates the course via :Katas.
  {
    dir          = "~/dev/solana-rust-vscode-course/neovim",
    dependencies = {
      "cds-io/kata-framework",
      "MeanderingProgrammer/render-markdown.nvim",
    },
  },
}
```

The provider has no `setup()` function. It returns the provider table
directly, and the framework calls `require("katas.solana_rust")` at
activation time.

## Configuration

The provider exposes a single per-entry option:

| Key      | Default   | Meaning |
| -------- | --------- | ------- |
| `runner` | `"cargo"` | Either `"cargo"` (which means `cargo run -p course-runner --`) or an absolute path to a prebuilt `course-runner` binary. `:CourseBuild` rewrites this in-process to point at `target/debug/course-runner`. |

Pass it via the framework's per-entry `opts` if you want a non-default
runner from the start:

```lua
opts = {
  katas = {
    solana_rust = {
      location = "~/dev/solana-rust-vscode-course",
      opts     = { runner = "/usr/local/bin/course-runner" },
    },
  },
},
```

## Commands

Registered when the course is active (i.e. after `:Katas` picks it):

| Command              | Effect |
| -------------------- | ------ |
| `:CourseBuild`       | Compile course-runner and cache the binary path so subsequent calls bypass `cargo run`. |
| `:CourseReset[!]`    | Restore exercises from baseline and clear progress. Prompts unless `!` is given. Triggers `checktime` so open buffers reload. |
| `:CourseUnmark <id>` | Clear progress for one exercise. Tab-completes from the framework's loaded item list. |

The framework also registers `:CourseOpen` (the picker) and the
buffer-local `<localleader>c{c,h,s,l}` keymaps; this provider just
contributes to that surface.

## Open question: embedded provider, or its own plugin?

Right now the provider lives inside the course repo, under `neovim/`.
That is convenient for whoever is authoring the course (one repo, one
PR per change to either side; the Lua wrappers and the
`course-runner` CLI they call stay in lockstep). lazy.nvim happily
consumes it via `dir = ".../neovim"`.

The friction is the GitHub install path. lazy.nvim assumes a plugin's
runtime path is the cloned repo root: it puts that root on the
runtimepath and looks for `lua/`, `plugin/`, `doc/` directly under
it. This repo's shape is `neovim/lua/...`, so a naive
`"<owner>/solana-rust-vscode-course"` spec does not work; lazy would
put the wrong directory on the rtp.

Workarounds, roughly in order of how invasive they are:

1. **Local clone plus `dir = `.** Users clone the course repo
   themselves (which they need to do anyway, for the exercises) and
   point lazy at the `neovim/` subdirectory. This is what the
   snippet above does, and it is the only path supported today.
2. **Promote `neovim/` contents to repo root.** Move `lua/` (and
   eventually `plugin/`, `doc/`) to the top level of the course
   repo. The GitHub spec then works directly. Cost: Lua source sits
   alongside Rust crates, a `pnpm` workspace, and the exercise
   directory at the root, which is messy but not broken.
3. **User-side symlink.** A `dir = ` pointing at a symlink the user
   maintains into `.../neovim`. Adds setup per user; not really
   better than (1).
4. **Split into a separate `katas-solana-rust.nvim` repo.** The
   provider becomes a standalone Neovim plugin that depends on the
   course repo being present (the framework's per-entry `location`
   already knows where the course lives, so the provider can read
   from `${location}/exercises/...` without owning the content).
   GitHub install via lazy works trivially. Cost: two repos to keep
   in sync; the provider's CLI wrappers and the `course-runner` CLI
   surface area now have to be versioned across a boundary.

(1) is fine while the audience is people who already clone the repo;
moving to (2) buys a one-line GitHub install at the cost of a noisier
root, and (4) is the clean answer if the course is ever meant to be
installed without cloning. The decision is not urgent: the provider
contract is small and the CLI it talks to is in this same repo, so
splitting later is mostly a mechanical move. We do not need to commit
to a shape now.
