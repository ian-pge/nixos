//! Connection-free Pixel Buds Battery All The Time (BATT), version 1.
//! Reverse-engineering evidence and setup: ../../pairing/README.md.
//! No pairing, key provisioning, account API or device writes in this module.
use crate::EarbudLevel;
use aes::{
    Aes128,
    cipher::{BlockEncrypt, KeyInit},
};
use anyhow::{Context, Result, ensure};
use hkdf::Hkdf;
use sha2::{Digest, Sha256};
use std::{
    fs::OpenOptions,
    io::Read,
    os::unix::fs::{MetadataExt, OpenOptionsExt},
    path::Path,
};
use zeroize::Zeroizing;

pub const SERVICE: &str = "0000fe2c-0000-1000-8000-00805f9b34fb";

/// Deliberately no Debug/Serialize implementation. Never put this in Nix/Git,
/// an environment value, command-line argument, log or QML object.
pub struct AccountKey(Zeroizing<[u8; 16]>);

impl AccountKey {
    pub fn load(path: &Path) -> Result<Self> {
        ensure!(
            path.is_absolute() && !path.starts_with("/nix/store"),
            "Use an absolute private key-file path outside the Nix store"
        );
        let mut file = OpenOptions::new()
            .read(true)
            .custom_flags(libc::O_NOFOLLOW | libc::O_CLOEXEC)
            .open(path)
            .context("Cannot open Fast Pair account-key file")?;
        let metadata = file.metadata()?;
        // SAFETY: geteuid has no arguments or memory side effects.
        ensure!(
            metadata.is_file()
                && metadata.uid() == unsafe { libc::geteuid() }
                && metadata.mode() & 0o077 == 0
                && metadata.len() == 16,
            "Fast Pair key must be a private, user-owned regular 16-byte file (0600)"
        );
        let mut key = Zeroizing::new([0; 16]);
        file.read_exact(&mut *key)?;
        ensure!(
            file.read(&mut [0; 1])? == 0 && key[0] == 4,
            "Invalid Fast Pair account-key file"
        );
        Ok(Self(key))
    }

    pub fn decode(&self, data: &[u8]) -> Option<Reading> {
        let fields = fields(data)?;
        let find = |kind| fields.iter().find(|(k, _)| *k == kind).map(|(_, v)| *v);
        let filter = find(0).or_else(|| find(2))?;
        let salt = find(1)?;
        if !(4..=15).contains(&filter.len()) || salt.len() != 2 {
            return None;
        }
        let (kind, encrypted) = if let Some(v) = find(10) {
            (10, v)
        } else {
            (9, find(9)?)
        };
        // Match the original Account Key, trying Google's default/recent/in-use
        // prefixes only for the Bloom filter, NOT for the decryption key.
        let mut tail = salt.to_vec();
        if let Some(rrd) = find(6) {
            tail.push(((rrd.len() as u8) << 4) | 6);
            tail.extend(rrd);
        }
        tail.push((((encrypted.len() / 4) as u8) << 4) | kind);
        tail.extend(encrypted);
        let matched = [4, 5, 6].iter().any(|prefix| {
            let mut input = Zeroizing::new(self.0.to_vec());
            input[0] = *prefix;
            input.extend(&tail);
            Sha256::digest(&*input)
                .as_chunks::<4>()
                .0
                .iter()
                .all(|bytes| {
                    let bit = u32::from_be_bytes(*bytes) as usize % (filter.len() * 8);
                    filter[bit / 8] & (1 << (bit % 8)) != 0
                })
        });
        if !matched {
            return None;
        }
        let mut key = Zeroizing::new([0; 16]);
        Hkdf::<Sha256>::new(None, &*self.0)
            .expand(b"SASS-RRD-KEY", &mut *key)
            .ok()?;
        let mut iv = [0; 16];
        iv[..2].copy_from_slice(salt);
        let mask = Zeroizing::new(aes_block(&key, &iv));
        let mut valid = None;
        for encrypted in encrypted.as_chunks::<4>().0 {
            let plain = Zeroizing::new(std::array::from_fn::<_, 4, _>(|i| encrypted[i] ^ mask[i]));
            if plain[0] != 0 || plain[1..].iter().any(|b| b & 127 > 100 && b & 127 != 127) {
                continue;
            }
            let level = |byte: u8| {
                if byte & 127 == 127 {
                    EarbudLevel::default()
                } else {
                    EarbudLevel {
                        percent: Some(byte & 127),
                        charging: Some(byte & 128 != 0),
                    }
                }
            };
            let reading = Reading {
                left: level(plain[1]),
                right: level(plain[2]),
                case: level(plain[3]),
                case_advertisement: plain[3] != 255,
            };
            // A zero header alone is NOT authentication. Ambiguous candidate
            // plaintexts are rejected; never choose arbitrary plausible bytes.
            if valid.is_some_and(|prior| prior != reading) {
                return None;
            }
            valid = Some(reading);
        }
        valid
    }
}

fn aes_block(key: &[u8; 16], input: &[u8; 16]) -> [u8; 16] {
    let aes = Aes128::new_from_slice(key).expect("fixed AES key length");
    let mut block = (*input).into();
    aes.encrypt_block(&mut block);
    block.into()
}

fn fields(data: &[u8]) -> Option<Vec<(u8, &[u8])>> {
    if data.first() != Some(&0x10) || data.len() > 255 {
        return None;
    }
    let mut fields = Vec::new();
    let mut pos = 1;
    while pos < data.len() {
        let kind = data[pos] & 15;
        let units = usize::from(data[pos] >> 4);
        // BATT's length is in four-byte blocks, not bytes.
        let len = if matches!(kind, 9 | 10) {
            units * 4
        } else {
            units
        };
        pos += 1;
        if len == 0 || pos + len > data.len() || fields.iter().any(|(k, _)| *k == kind) {
            return None;
        }
        fields.push((kind, &data[pos..pos + len]));
        pos += len;
    }
    Some(fields)
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Reading {
    pub case: EarbudLevel,
    pub left: EarbudLevel,
    pub right: EarbudLevel,
    pub case_advertisement: bool,
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Levels {
    pub case: EarbudLevel,
    pub left: EarbudLevel,
    pub right: EarbudLevel,
    pub observed_at: Option<u64>,
}
impl Levels {
    pub fn available(&self) -> bool {
        [self.case, self.left, self.right]
            .iter()
            .any(|v| v.percent.is_some())
    }
    pub fn event(self, received_at: u64) -> crate::Event {
        crate::Event::Earbuds {
            mode: "passive",
            available: self.available(),
            case: self.case,
            left: self.left,
            right: self.right,
            observed_at: if self.available() {
                self.observed_at
            } else {
                None
            },
            received_at,
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    fn key() -> AccountKey {
        AccountKey(Zeroizing::new([4; 16]))
    }
    fn packet(plain: [u8; 4], kind: u8, prefix: u8) -> Vec<u8> {
        let key = key();
        let salt = [0xaa, 0xbb];
        let mut derived = [0; 16];
        Hkdf::<Sha256>::new(None, &*key.0)
            .expand(b"SASS-RRD-KEY", &mut derived)
            .unwrap();
        let mut iv = [0; 16];
        iv[..2].copy_from_slice(&salt);
        let mask = aes_block(&derived, &iv);
        let encrypted: Vec<u8> = (0..4).map(|i| plain[i] ^ mask[i]).collect();
        let mut input = key.0.to_vec();
        input[0] = prefix;
        input.extend(salt);
        input.push(0x10 | kind);
        input.extend(&encrypted);
        let mut filter = [0u8; 4];
        for v in Sha256::digest(&input).as_chunks::<4>().0 {
            let bit = u32::from_be_bytes(*v) % 32;
            filter[bit as usize / 8] |= 1 << (bit % 8);
        }
        let mut out = vec![0x10, 0x40];
        out.extend(filter);
        out.extend([0x21, 0xaa, 0xbb, 0x10 | kind]);
        out.extend(encrypted);
        out
    }
    #[test]
    fn encrypted_vectors_require_key_filter_and_valid_plaintext() {
        for kind in [9, 10] {
            for prefix in [4, 5, 6] {
                let data = packet([0, 0, 19, 0xe4], kind, prefix);
                let reading = key().decode(&data).unwrap();
                assert_eq!(reading.left.percent, Some(0));
                assert_eq!(reading.right.percent, Some(19));
                assert_eq!(
                    reading.case,
                    EarbudLevel {
                        percent: Some(100),
                        charging: Some(true)
                    }
                );
                assert!(reading.case_advertisement);
                assert!(AccountKey(Zeroizing::new([5; 16])).decode(&data).is_none());
                let mut wrong_filter = data.clone();
                wrong_filter[2..6].fill(0);
                assert!(key().decode(&wrong_filter).is_none());
            }
        }
        for plain in [[1, 100, 100, 100], [0, 101, 100, 100], [0, 100, 100, 126]] {
            assert!(key().decode(&packet(plain, 10, 4)).is_none());
        }
    }
    #[test]
    fn unknown_case_is_not_zero_or_an_aggregate() {
        let reading = key().decode(&packet([0, 0xff, 100, 0xff], 9, 4)).unwrap();
        assert!(!reading.case_advertisement);
        assert_eq!(reading.case, EarbudLevel::default());
        assert_eq!(reading.left, EarbudLevel::default());
    }
    #[test]
    fn reject_other_versions_truncations_and_duplicate_fields() {
        let data = packet([0, 100, 100, 100], 10, 4);
        for length in 0..data.len() {
            assert!(key().decode(&data[..length]).is_none());
        }
        let mut other = data.clone();
        other[0] = 0;
        assert!(key().decode(&other).is_none());
        let mut duplicate = data;
        duplicate.extend([0x21, 1, 2]);
        assert!(key().decode(&duplicate).is_none());
    }
    #[test]
    fn a_known_zero_header_without_a_matching_filter_is_not_sufficient() {
        let mut data = packet([0, 100, 100, 100], 10, 4);
        data[2..6].fill(0);
        assert!(key().decode(&data).is_none());
    }
    #[test]
    fn key_loader_rejects_public_files_wrong_lengths_and_symlinks() {
        use std::os::unix::fs::PermissionsExt;
        let directory =
            std::env::temp_dir().join(format!("fastpair-key-test-{}", std::process::id()));
        std::fs::create_dir(&directory).unwrap();
        let path = directory.join("key");
        std::fs::write(&path, [4; 16]).unwrap();
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o644)).unwrap();
        assert!(AccountKey::load(&path).is_err());
        std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o600)).unwrap();
        assert!(AccountKey::load(&path).is_ok());
        let link = directory.join("link");
        std::os::unix::fs::symlink(&path, &link).unwrap();
        assert!(AccountKey::load(&link).is_err());
        std::fs::write(&path, [4; 15]).unwrap();
        assert!(AccountKey::load(&path).is_err());
        std::fs::remove_file(link).unwrap();
        std::fs::remove_file(path).unwrap();
        std::fs::remove_dir(directory).unwrap();
    }
}
