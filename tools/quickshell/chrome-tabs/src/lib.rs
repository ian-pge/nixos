pub mod process;
use anyhow::{Context, Result};
use rusqlite::{Connection, OpenFlags, OptionalExtension};
use serde_json::{Value, json};
use sha2::{Digest, Sha256};
use std::{env, fs, io::Write, os::unix::fs::DirBuilderExt, path::PathBuf, time::Duration};

pub struct Paths {
    pub database: PathBuf,
    pub cache: PathBuf,
}
impl Paths {
    pub fn from_env() -> Result<Self> {
        let home = PathBuf::from(env::var_os("HOME").context("HOME is unset")?);
        let xdg = |key, fallback| {
            env::var_os(key)
                .filter(|v| !v.is_empty())
                .map(PathBuf::from)
                .unwrap_or(fallback)
        };
        Ok(Self {
            database: xdg("XDG_CONFIG_HOME", home.join(".config"))
                .join("google-chrome/Default/Favicons"),
            cache: xdg("XDG_CACHE_HOME", home.join(".cache")).join("quickshell/chrome-favicons"),
        })
    }
}

const ICON_QUERY: &str = "SELECT bitmap.image_data FROM icon_mapping AS mapping
    JOIN favicon_bitmaps AS bitmap ON bitmap.icon_id = mapping.icon_id
    WHERE mapping.page_url = ?1 AND bitmap.image_data IS NOT NULL
    ORDER BY bitmap.width DESC, bitmap.last_updated DESC LIMIT 1";

fn open_database(paths: &Paths) -> rusqlite::Result<Connection> {
    // Chrome can modify this file while we read it: do not claim it is immutable.
    // READ_ONLY never creates a missing database. Locked/corrupt caches simply
    // yield no icons, without preventing tab listing or holding up the UI.
    let db = Connection::open_with_flags(
        &paths.database,
        OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX,
    )?;
    db.busy_timeout(Duration::ZERO)?;
    Ok(db)
}

fn cached_icon(paths: &Paths, bytes: &[u8]) -> Result<String> {
    fs::DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(&paths.cache)?;
    let destination = paths.cache.join(format!("{:x}.png", Sha256::digest(bytes)));
    if !destination.is_file() {
        // A unique temporary file prevents concurrent listings from colliding.
        let mut temporary = tempfile::NamedTempFile::new_in(&paths.cache)?;
        temporary.write_all(bytes)?;
        temporary.persist(&destination).map_err(|e| e.error)?;
    }
    destination
        .to_str()
        .map(str::to_owned)
        .context("Favicon cache path is not valid UTF-8")
}

pub fn enrich(input: &[u8], paths: &Paths) -> Value {
    let Ok(Value::Array(mut tabs)) = serde_json::from_slice(input) else {
        return json!({"ok":false,"tabs":[],"error":"Invalid TabCtl response"});
    };
    let db = open_database(paths).ok();
    let mut statement = db.as_ref().and_then(|db| db.prepare(ICON_QUERY).ok());
    for tab in &mut tabs {
        let Some(tab) = tab.as_object_mut() else {
            continue;
        };
        tab.insert("iconPath".into(), Value::String(String::new()));
        let url = tab.get("url").and_then(Value::as_str).unwrap_or("");
        let bytes = statement.as_mut().and_then(|stmt| {
            stmt.query_row([url], |row| row.get::<_, Vec<u8>>(0))
                .optional()
                .ok()
                .flatten()
        });
        if let Some(bytes) = bytes.filter(|b| !b.is_empty())
            && let Ok(path) = cached_icon(paths, &bytes)
        {
            tab.insert("iconPath".into(), Value::String(path));
        }
    }
    json!({"ok":true,"tabs":tabs})
}

pub fn failure(message: &str, listing: bool) -> Value {
    let mut value = json!({"ok":false,"error":message});
    if listing {
        value["tabs"] = json!([]);
    }
    value
}

pub fn response(args: &[String], paths: &Paths, runner: &process::Runner) -> Result<Value> {
    let listing = args[0] == "list";
    let command = match args[0].as_str() {
        "list" => vec!["--format", "json", "list"],
        "activate" => vec!["activate", "--focused", args[1].as_str()],
        "close" => vec!["close", args[1].as_str()],
        _ => unreachable!("CLI validated before dispatch"),
    };
    let output = match runner.capture(&command) {
        Ok(output) => output,
        Err(error) => return Ok(failure(&format!("{error:#}"), listing)),
    };
    if !output.status.success() {
        let diagnostic = if output.stderr.is_empty() {
            &output.stdout
        } else {
            &output.stderr
        };
        let text = String::from_utf8_lossy(diagnostic);
        let first = text.lines().next().unwrap_or("Unable to contact Chrome");
        return Ok(failure(
            first.strip_prefix("Error: ").unwrap_or(first),
            listing,
        ));
    }
    Ok(if listing {
        enrich(&output.stdout, paths)
    } else {
        json!({"ok":true})
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;
    fn fixture() -> (tempfile::TempDir, Paths) {
        let temp = tempfile::tempdir().unwrap();
        let paths = Paths {
            database: temp.path().join("Favicons ?#% é"),
            cache: temp.path().join("cache"),
        };
        (temp, paths)
    }
    fn database(paths: &Paths) -> Connection {
        let db = Connection::open(&paths.database).unwrap();
        db.execute_batch("CREATE TABLE icon_mapping(page_url TEXT, icon_id INTEGER);
            CREATE TABLE favicon_bitmaps(icon_id INTEGER,image_data BLOB,width INTEGER,last_updated INTEGER);
            INSERT INTO icon_mapping VALUES ('https://example.test/',1);
            INSERT INTO favicon_bitmaps VALUES(1,x'01',16,10),(1,x'0203',32,1),(1,x'0405',32,2);").unwrap();
        db
    }
    const TABS: &[u8] = br#"[{"id":"7","url":"https://example.test/","title":"Example"},{"id":"8","url":"chrome://newtab"}]"#;
    #[test]
    fn selects_largest_then_newest_icon_and_keeps_fields() {
        let (_temp, p) = fixture();
        drop(database(&p));
        let before = fs::read(&p.database).unwrap();
        let value = enrich(TABS, &p);
        assert_eq!(value["ok"], true);
        assert_eq!(value["tabs"][0]["id"], "7");
        assert_eq!(value["tabs"][0]["title"], "Example");
        let icon = PathBuf::from(value["tabs"][0]["iconPath"].as_str().unwrap());
        assert_eq!(fs::read(&icon).unwrap(), vec![4, 5]);
        assert_eq!(value["tabs"][1]["iconPath"], "");
        assert_eq!(fs::read(&p.database).unwrap(), before);
        assert_eq!(enrich(TABS, &p), value);
        assert_eq!(fs::read_dir(&p.cache).unwrap().count(), 1);
        assert_eq!(
            fs::metadata(icon).unwrap().permissions().mode() & 0o777,
            0o600
        );
        assert_eq!(
            fs::metadata(&p.cache).unwrap().permissions().mode() & 0o777,
            0o700
        );
        assert!(
            open_database(&p)
                .unwrap()
                .execute("DELETE FROM icon_mapping", [])
                .is_err()
        );
    }
    #[test]
    fn missing_corrupt_wrong_schema_and_locked_databases_are_optional() {
        let (_temp, p) = fixture();
        let check = || {
            let result = enrich(TABS, &p);
            assert_eq!(result["ok"], true);
            assert_eq!(result["tabs"][0]["iconPath"], "");
        };
        check();
        assert!(!p.database.exists());
        fs::write(&p.database, b"not sqlite").unwrap();
        check();
        fs::remove_file(&p.database).unwrap();
        drop(Connection::open(&p.database).unwrap());
        check();
        let db = database(&p);
        db.execute_batch("BEGIN EXCLUSIVE").unwrap();
        check();
        db.execute_batch("ROLLBACK").unwrap();
        assert_ne!(enrich(TABS, &p)["tabs"][0]["iconPath"], "");
    }
    #[test]
    fn malformed_responses_and_unavailable_cache() {
        let (_temp, p) = fixture();
        for input in [b"not json".as_slice(), b"{}", b"null"] {
            assert_eq!(enrich(input, &p)["ok"], false);
        }
        assert_eq!(enrich(b"[]", &p), json!({"ok":true,"tabs":[]}));
        drop(database(&p));
        fs::write(&p.cache, b"not a directory").unwrap();
        assert_eq!(enrich(TABS, &p)["tabs"][0]["iconPath"], "");
    }
    #[test]
    fn concurrent_listings_share_atomic_cache() {
        let (_temp, p) = fixture();
        drop(database(&p));
        std::thread::scope(|scope| {
            let jobs: Vec<_> = (0..8).map(|_| scope.spawn(|| enrich(TABS, &p))).collect();
            for job in jobs {
                assert_ne!(job.join().unwrap()["tabs"][0]["iconPath"], "");
            }
        });
        assert_eq!(fs::read_dir(&p.cache).unwrap().count(), 1);
    }

    #[test]
    fn reads_committed_icons_from_a_live_wal_database() {
        let (_temp, p) = fixture();
        let writer = database(&p);
        writer
            .execute_batch(
                "PRAGMA journal_mode=WAL;
            INSERT INTO favicon_bitmaps VALUES(1,x'0607',64,3);",
            )
            .unwrap();
        let result = enrich(TABS, &p);
        let path = result["tabs"][0]["iconPath"].as_str().unwrap();
        assert_eq!(fs::read(path).unwrap(), vec![6, 7]);
        // Keep the writer alive: this must work without a close/checkpoint.
        assert!(writer.is_autocommit());
    }
}
