//! The release workflow reads the version from tauri.conf.json and checks the
//! tag against it; everything else that names a version has to agree.

fn field<'a>(text: &'a str, prefix: &str) -> &'a str {
    let line = text.lines().find(|l| l.starts_with(prefix)).unwrap_or_else(|| panic!("keine Zeile {prefix:?}"));
    line[prefix.len()..].trim_end_matches(',').trim_matches('"')
}

/// Kern, Fenster und Installer tragen dieselbe Version.
#[test]
fn versions_match() {
    let version = env!("CARGO_PKG_VERSION");
    let tauri = include_str!("../app/tauri.conf.json");
    assert_eq!(field(tauri, r#"  "version": "#), version, "app/tauri.conf.json");
    let app = include_str!("../app/Cargo.toml");
    assert_eq!(field(app, "version = "), version, "app/Cargo.toml");
}

/// Zu jeder Version gehört ein Abschnitt im CHANGELOG, aus dem das Release
/// seinen Text nimmt.
#[test]
fn changelog_has_this_version() {
    let heading = format!("## {}", env!("CARGO_PKG_VERSION"));
    assert!(include_str!("../CHANGELOG.md").lines().any(|l| l == heading), "{heading} fehlt in CHANGELOG.md");
}
