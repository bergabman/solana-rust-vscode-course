mod check;
mod fs_utils;
mod manifest;
mod platform;
mod progress;
mod reset;
mod surfpool;
mod ui;

use std::path::PathBuf;

use anyhow::Result;
use clap::{Parser, Subcommand};

use check::check_exercise;
use manifest::{
    describe_course, find_course_root, find_exercise, list_exercises, load_manifest, print_hint,
    print_metadata, print_solution,
};
use reset::reset_course;
use ui::start_course_ui;

#[derive(Parser)]
#[command(name = "course-runner")]
#[command(about = "Compact Rust course runner for Solana client-side exercises")]
struct Cli {
    #[command(subcommand)]
    command: CommandKind,
}

#[derive(Subcommand)]
enum CommandKind {
    List,
    Check {
        exercise: String,
    },
    Describe,
    Metadata,
    Hint {
        exercise: String,
        number: usize,
    },
    Solution {
        exercise: String,
    },
    Reset {
        #[arg(long)]
        yes: bool,
    },
    Progress {
        #[command(subcommand)]
        action: ProgressAction,
    },
    StartUi {
        #[arg(long)]
        vscode_exec: Option<String>,
        #[arg(long)]
        workspace: Option<PathBuf>,
        #[arg(long)]
        dry_run: bool,
        #[arg(long)]
        no_open: bool,
    },
}

#[derive(Subcommand)]
enum ProgressAction {
    List,
    Mark { exercise: String },
    Unmark { exercise: String },
}

#[tokio::main]
async fn main() -> Result<()> {
    let cli = Cli::parse();
    let root = find_course_root()?;
    let manifest = load_manifest(&root)?;

    match cli.command {
        CommandKind::List => list_exercises(&manifest),
        CommandKind::Describe => describe_course(&manifest),
        CommandKind::Metadata => print_metadata(&manifest)?,
        CommandKind::Hint { exercise, number } => {
            let exercise = find_exercise(&manifest, &exercise)?;
            print_hint(exercise, number)?;
        }
        CommandKind::Solution { exercise } => {
            let exercise = find_exercise(&manifest, &exercise)?;
            print_solution(exercise)?;
        }
        CommandKind::Reset { yes } => {
            reset_course(&root, yes)?;
        }
        CommandKind::Check { exercise } => {
            let exercise = find_exercise(&manifest, &exercise)?;
            check_exercise(&root, exercise).await?;
        }
        CommandKind::Progress { action } => match action {
            ProgressAction::List => progress::list_completed(&root)?,
            ProgressAction::Mark { exercise } => progress::mark_completed(&root, &exercise)?,
            ProgressAction::Unmark { exercise } => progress::unmark_completed(&root, &exercise)?,
        },
        CommandKind::StartUi {
            vscode_exec,
            workspace,
            dry_run,
            no_open,
        } => {
            start_course_ui(&root, vscode_exec, workspace, dry_run, no_open)?;
        }
    }

    Ok(())
}
