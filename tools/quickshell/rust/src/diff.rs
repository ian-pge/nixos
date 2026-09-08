use crate::process::Runner;
use anyhow::{Context, Result, ensure};
use serde_json::{Map, Value, json};
use std::{
    cmp::Ordering,
    collections::{BTreeMap, BTreeSet},
    path::Path,
    process::Command,
};

const KINDS: [&str; 5] = ["added", "removed", "changed", "upgraded", "downgraded"];

#[derive(Debug, PartialEq, Eq)]
enum Chunk {
    Number(String),
    Text(String),
}

impl Chunk {
    fn compare(&self, other: &Self) -> Ordering {
        use Chunk::{Number, Text};
        match (self, other) {
            (Number(a), Number(b)) => a.len().cmp(&b.len()).then_with(|| a.cmp(b)),
            (Text(a), Text(b)) if a == b => Ordering::Equal,
            (Text(a), _) if a == "pre" => Ordering::Less,
            (_, Text(b)) if b == "pre" => Ordering::Greater,
            (Text(_), Number(_)) => Ordering::Less,
            (Number(_), Text(_)) => Ordering::Greater,
            (Text(a), Text(b)) => a.cmp(b),
        }
    }
}

#[derive(Debug)]
struct Version {
    text: String,
    chunks: Vec<Chunk>,
}

impl Version {
    fn new(text: &str) -> Self {
        let mut chunks = Vec::new();
        let mut remaining = text;
        while let Some(first) = remaining.chars().next() {
            let digit = first.is_ascii_digit();
            let alpha = first.is_alphabetic();
            let end = remaining
                .char_indices()
                .find(|(_, c)| c.is_ascii_digit() != digit || c.is_alphabetic() != alpha)
                .map_or(remaining.len(), |(i, _)| i);
            let run = &remaining[..end];
            if digit {
                let number = run.trim_start_matches('0');
                chunks.push(Chunk::Number(
                    if number.is_empty() { "0" } else { number }.into(),
                ));
            } else if alpha {
                chunks.push(Chunk::Text(run.into()));
            }
            remaining = &remaining[end..];
        }
        Self {
            text: text.into(),
            chunks,
        }
    }

    fn compare(&self, other: &Self) -> Ordering {
        let empty = Chunk::Text(String::new());
        for i in 0..self.chunks.len().max(other.chunks.len()) {
            let order = self
                .chunks
                .get(i)
                .unwrap_or(&empty)
                .compare(other.chunks.get(i).unwrap_or(&empty));
            if order != Ordering::Equal {
                return order;
            }
        }
        Ordering::Equal
    }
}

fn parse_store_name(path: &str) -> Result<(&str, &str)> {
    let base = path.rsplit('/').next().unwrap_or(path);
    ensure!(
        base.len() > 33
            && base.as_bytes()[32] == b'-'
            && base.as_bytes()[..32]
                .iter()
                .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit()),
        "invalid Nix store path name: {path}"
    );
    let name = base[33..].strip_suffix(".drv").unwrap_or(&base[33..]);
    ensure!(!name.is_empty(), "empty Nix store name");
    let version = name
        .as_bytes()
        .windows(2)
        .enumerate()
        .find(|(i, pair)| *i > 0 && pair[0] == b'-' && pair[1].is_ascii_digit());
    Ok(match version {
        Some((i, _)) => (&name[..i], &name[i + 1..]),
        None => (name, ""),
    })
}

type Packages = BTreeMap<String, Vec<Version>>;

fn packages<'a>(names: impl IntoIterator<Item = &'a str>) -> Result<Packages> {
    let mut result: Packages = BTreeMap::new();
    for path in names {
        let (name, version) = parse_store_name(path)?;
        result
            .entry(name.into())
            .or_default()
            .push(Version::new(version));
    }
    for versions in result.values_mut() {
        versions.sort_by(Version::compare);
    }
    Ok(result)
}

fn validate(document: Value) -> Result<Map<String, Value>> {
    ensure!(
        document["version"] == 2,
        "nix path-info did not return JSON format 2"
    );
    ensure!(
        document["storeDir"] == "/nix/store",
        "unexpected Nix store directory"
    );
    document["info"]
        .as_object()
        .cloned()
        .context("nix path-info is missing its info object")
}

fn path_info(path: &Path, recursive: bool, runner: &Runner) -> Result<Map<String, Value>> {
    let mut command = Command::new("nix");
    command.args(["path-info", "--json", "--json-format", "2"]);
    if recursive {
        command.arg("--recursive");
    }
    validate(serde_json::from_str(&runner.capture(command.arg(path))?)?)
}

fn selected(
    root: &Path,
    info: &Map<String, Value>,
    use_sw: bool,
    runner: &Runner,
) -> Result<Packages> {
    let selection = if use_sw {
        root.join("sw")
    } else {
        root.to_path_buf()
    }
    .canonicalize()?;
    let name = selection
        .file_name()
        .and_then(|s| s.to_str())
        .context("invalid selection root")?;
    let extra;
    let entry = match info.get(name).filter(|value| value.is_object()) {
        Some(entry) => entry,
        None => {
            extra = path_info(&selection, false, runner)?;
            extra
                .get(name)
                .context("selection root missing from Nix path-info")?
        }
    };
    let references = entry["references"]
        .as_array()
        .context("invalid Nix references")?;
    let names = references
        .iter()
        .map(|r| r.as_str().context("invalid Nix reference"))
        .collect::<Result<Vec<_>>>()?;
    packages(names)
}

fn texts(versions: &[Version]) -> Vec<&str> {
    let mut seen = BTreeSet::new();
    versions
        .iter()
        .filter_map(|v| seen.insert(v.text.as_str()).then_some(v.text.as_str()))
        .collect()
}

fn compare(
    old: &Packages,
    new: &Packages,
    old_selected: &Packages,
    new_selected: &Packages,
) -> Value {
    let names: BTreeSet<_> = old.keys().chain(new.keys()).collect();
    let mut changes = Vec::new();
    for name in names {
        let a = old.get(name).map_or(&[][..], Vec::as_slice);
        let b = new.get(name).map_or(&[][..], Vec::as_slice);
        let equal = a.len() == b.len() && a.iter().zip(b).all(|(a, b)| a.chunks == b.chunks);
        if equal && old_selected.contains_key(name) == new_selected.contains_key(name) {
            continue;
        }
        let kind = if a.is_empty() {
            "added"
        } else if b.is_empty() {
            "removed"
        } else if a.last().unwrap().compare(&b[0]) == Ordering::Less {
            "upgraded"
        } else if a[0].compare(b.last().unwrap()) == Ordering::Greater {
            "downgraded"
        } else {
            "changed"
        };
        changes
            .push(json!({"name":name,"kind":kind,"oldVersions":texts(a),"newVersions":texts(b)}));
    }
    changes.sort_by_key(|c| {
        (
            KINDS.iter().position(|k| c["kind"] == *k).unwrap(),
            c["name"].as_str().unwrap().to_lowercase(),
        )
    });
    let counts: Map<_, _> = KINDS
        .iter()
        .map(|k| {
            (
                k.to_string(),
                json!(changes.iter().filter(|c| c["kind"] == *k).count()),
            )
        })
        .collect();
    json!({"total":changes.len(),"changes":changes,"counts":counts})
}

pub fn build(old: &Path, new: &Path, runner: &Runner) -> Result<Value> {
    let old = old.canonicalize()?;
    let new = new.canonicalize()?;
    let a = path_info(&old, true, runner)?;
    let b = path_info(&new, true, runner)?;
    let use_sw = old.join("sw").is_dir() && new.join("sw").is_dir();
    Ok(compare(
        &packages(a.keys().map(String::as_str))?,
        &packages(b.keys().map(String::as_str))?,
        &selected(&old, &a, use_sw, runner)?,
        &selected(&new, &b, use_sw, runner)?,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;
    fn set(names: &[&str]) -> Packages {
        let paths: Vec<_> = names
            .iter()
            .map(|n| format!("{}-{n}", "0".repeat(32)))
            .collect();
        packages(paths.iter().map(String::as_str)).unwrap()
    }
    #[test]
    fn store_names() {
        for (input, expected) in [
            ("libressl-4.3.2-man", ("libressl", "4.3.2-man")),
            (
                "nixos-system-nixos-26.11.abc",
                ("nixos-system-nixos", "26.11.abc"),
            ),
            ("source", ("source", "")),
            ("foo-1.drv", ("foo", "1")),
        ] {
            assert_eq!(
                parse_store_name(&format!("/nix/store/{}-{input}", "0".repeat(32))).unwrap(),
                expected
            );
        }
        assert!(parse_store_name("not-a-store-name").is_err());
    }
    #[test]
    fn versions() {
        for (a, b) in [
            ("1.9", "1.10"),
            ("1.0pre", "1.0"),
            ("", "1"),
            ("1a", "1.1"),
            ("9999999999999999999999999", "10000000000000000000000000"),
        ] {
            assert_eq!(
                Version::new(a).compare(&Version::new(b)),
                Ordering::Less,
                "{a} < {b}"
            );
        }
        assert_eq!(Version::new("1.0").chunks, Version::new("01-0").chunks);
    }
    #[test]
    fn document_format() {
        assert!(validate(json!({"version":2,"storeDir":"/nix/store","info":{}})).is_ok());
        for bad in [
            json!({"version":1}),
            json!({"version":2,"storeDir":"/tmp","info":{}}),
            json!({"version":2,"storeDir":"/nix/store","info":[]}),
        ] {
            assert!(validate(bad).is_err());
        }
    }
    #[test]
    fn changes_and_selection() {
        let old = set(&[
            "foo-1", "foo-1", "bar-3", "gone-2", "keep-1", "pick-1", "mixed-1", "mixed-3",
        ]);
        let new = set(&["foo-2", "bar-2", "added-1", "keep-01", "pick-1", "mixed-2"]);
        let diff = compare(&old, &new, &set(&["pick-1"]), &set(&[]));
        assert_eq!(
            diff["counts"],
            json!({"added":1,"removed":1,"changed":2,"upgraded":1,"downgraded":1})
        );
        assert_eq!(diff["total"], 6);
        assert_eq!(diff["changes"][4]["oldVersions"], json!(["1"]));
        assert_eq!(compare(&old, &old, &old, &old)["total"], 0);
    }
}
