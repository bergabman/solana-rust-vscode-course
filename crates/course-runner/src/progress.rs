use std::{fs, path::Path};

use anyhow::{Context, Result};

fn progress_path(root: &Path) -> std::path::PathBuf {
    root.join(".course/progress.json")
}

fn load(root: &Path) -> Result<Vec<String>> {
    let path = progress_path(root);
    if !path.exists() {
        return Ok(Vec::new());
    }
    let content = fs::read_to_string(&path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_str(&content).context("failed to parse .course/progress.json")
}

fn save(root: &Path, completed: &[String]) -> Result<()> {
    let path = progress_path(root);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("failed to create {}", parent.display()))?;
    }
    let content = serde_json::to_string_pretty(completed)
        .context("failed to serialize progress")?;
    fs::write(&path, content)
        .with_context(|| format!("failed to write {}", path.display()))
}

pub fn list_completed(root: &Path) -> Result<()> {
    let completed = load(root)?;
    let json = serde_json::to_string(&completed).context("failed to serialize")?;
    println!("{json}");
    Ok(())
}

pub fn mark_completed(root: &Path, id: &str) -> Result<()> {
    let mut completed = load(root)?;
    if !completed.iter().any(|x| x == id) {
        completed.push(id.to_string());
        save(root, &completed)?;
    }
    Ok(())
}

pub fn unmark_completed(root: &Path, id: &str) -> Result<()> {
    let mut completed = load(root)?;
    let before = completed.len();
    completed.retain(|x| x != id);
    if completed.len() != before {
        save(root, &completed)?;
    }
    Ok(())
}

pub fn clear_progress(root: &Path) -> Result<()> {
    let path = progress_path(root);
    if path.exists() {
        fs::remove_file(&path)
            .with_context(|| format!("failed to remove {}", path.display()))?;
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn list_returns_empty_when_no_file() {
        let dir = tempfile::tempdir().unwrap();
        let completed = load(dir.path()).unwrap();
        assert!(completed.is_empty());
    }

    #[test]
    fn mark_creates_file_and_adds_id() {
        let dir = tempfile::tempdir().unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        let completed = load(dir.path()).unwrap();
        assert_eq!(completed, vec!["01_keypairs"]);
    }

    #[test]
    fn mark_is_idempotent() {
        let dir = tempfile::tempdir().unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        let completed = load(dir.path()).unwrap();
        assert_eq!(completed.len(), 1);
    }

    #[test]
    fn mark_multiple_preserves_order() {
        let dir = tempfile::tempdir().unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        mark_completed(dir.path(), "02_airdrop_balance").unwrap();
        let completed = load(dir.path()).unwrap();
        assert_eq!(completed, vec!["01_keypairs", "02_airdrop_balance"]);
    }

    #[test]
    fn unmark_removes_id() {
        let dir = tempfile::tempdir().unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        mark_completed(dir.path(), "02_airdrop_balance").unwrap();
        unmark_completed(dir.path(), "01_keypairs").unwrap();
        let completed = load(dir.path()).unwrap();
        assert_eq!(completed, vec!["02_airdrop_balance"]);
    }

    #[test]
    fn unmark_nonexistent_is_noop() {
        let dir = tempfile::tempdir().unwrap();
        unmark_completed(dir.path(), "01_keypairs").unwrap();
        let completed = load(dir.path()).unwrap();
        assert!(completed.is_empty());
    }

    #[test]
    fn clear_removes_file() {
        let dir = tempfile::tempdir().unwrap();
        mark_completed(dir.path(), "01_keypairs").unwrap();
        clear_progress(dir.path()).unwrap();
        assert!(!progress_path(dir.path()).exists());
    }

    #[test]
    fn clear_is_noop_when_no_file() {
        let dir = tempfile::tempdir().unwrap();
        clear_progress(dir.path()).unwrap();
    }
}
