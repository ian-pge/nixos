//! Offline Fast Pair protocol preparation for one owner-confirmed headset.
//! No firmware, Find Hub, account removal, debug or audio control commands.
use aes::{
    Aes128,
    cipher::{BlockDecrypt, BlockEncrypt, KeyInit},
};
use anyhow::{Result, ensure};
use p256::{PublicKey, ecdh::EphemeralSecret, elliptic_curve::sec1::ToEncodedPoint};
use rand_core::{OsRng, RngCore};
use sha2::{Digest, Sha256};
use zeroize::Zeroizing;

/// Filename only, never the key contents, may be overridden for a deliberate
/// new setup. Default matches Home Manager and the production reader.
pub fn account_key_path() -> Result<std::path::PathBuf> {
    let path = if let Some(path) = std::env::var_os("FAST_PAIR_ACCOUNT_KEY_FILE") {
        path.into()
    } else {
        let base = std::env::var_os("XDG_STATE_HOME")
            .map(std::path::PathBuf::from)
            .or_else(|| {
                std::env::var_os("HOME")
                    .map(|home| std::path::PathBuf::from(home).join(".local/state"))
            })
            .ok_or_else(|| anyhow::anyhow!("No state directory; set FAST_PAIR_ACCOUNT_KEY_FILE"))?;
        base.join("battery-relay/pixel-buds.account-key")
    };
    ensure!(
        path.is_absolute() && !path.starts_with("/nix/store"),
        "Key path must be absolute and outside the Nix store"
    );
    Ok(path)
}

pub const OWNER_HEADSET: [u8; 6] = [0x44, 0x10, 0x30, 0x25, 0x8f, 0x4f];
pub const OWNER_HEADSET_TEXT: &str = "44:10:30:25:8F:4F";
pub const MODEL_ID: [u8; 3] = [0xc5, 0x5c, 0x79];
// Public model key, NOT a user's account key or any private key.
// Published dataset: KULeuven-COSIC/WhisperPair/toolkit-server/device-info.json,
// entry 12934265, "Pixel Buds Pro 2", "Porcelain". Only the public metadata is
// used; no exploit, credential or provisioning code is used or executed.
pub const MODEL_PUBLIC_KEY: &str = "fb029035b47f8615bf94bcabf7e970307340308daf55c5c832661adf42a7c4d4110b649ee90fa8c53ee38ab4e04ff052354849ec425083bb72ea6627ab93228b";

/// Exact model in either Google's original or newer model/capability format.
/// Capability 0 means neither LE-sharing support nor factory-new state; it does
/// NOT mean "not pairable". Only used with the owner's physical pairing-mode
/// confirmation and pinned address. Idle account-data is never accepted.
pub fn is_pairing_advertisement(data: &[u8]) -> bool {
    data == MODEL_ID || data == [0, 0x37, 0xc5, 0x5c, 0x79, 0x18, 0]
}

pub fn model_public_key() -> Result<PublicKey> {
    let mut sec1 = vec![4];
    sec1.extend(hex::decode(MODEL_PUBLIC_KEY)?);
    Ok(PublicKey::from_sec1_bytes(&sec1)?)
}

pub fn encrypt_block(key: &[u8; 16], plaintext: &[u8; 16]) -> [u8; 16] {
    let cipher = Aes128::new_from_slice(key).expect("fixed AES-128 key size");
    let mut block = (*plaintext).into();
    cipher.encrypt_block(&mut block);
    block.into()
}

pub fn decrypt_block(key: &[u8; 16], ciphertext: &[u8]) -> Result<Zeroizing<[u8; 16]>> {
    ensure!(ciphertext.len() == 16, "Wrong encrypted response length");
    let cipher = Aes128::new_from_slice(key).expect("fixed AES-128 key size");
    let mut block = <[u8; 16]>::try_from(ciphertext)?.into();
    cipher.decrypt_block(&mut block);
    Ok(Zeroizing::new(block.into()))
}

/// Ephemeral secrets are not serialized, printed or written to log files.
pub struct Handshake {
    key: Zeroizing<[u8; 16]>,
    public: [u8; 64],
    authenticated: bool,
    passkey_verified: bool,
    account_key_prepared: bool,
}

impl Handshake {
    pub fn new() -> Result<Self> {
        let ephemeral = EphemeralSecret::random(&mut OsRng);
        let public = PublicKey::from(&ephemeral).to_encoded_point(false);
        let shared = ephemeral.diffie_hellman(&model_public_key()?);
        let digest = Zeroizing::new(Sha256::digest(shared.raw_secret_bytes()).to_vec());
        Ok(Self {
            key: Zeroizing::new(digest[..16].try_into()?),
            public: public.as_bytes()[1..].try_into()?,
            authenticated: false,
            passkey_verified: false,
            account_key_prepared: false,
        })
    }

    /// Legacy/BR-EDR Fast Pair request. No provider-initiated pairing,
    /// personalized-name change, retroactive flag, or LE Audio/Find Hub claims.
    pub fn request(&self, advertiser: [u8; 6]) -> [u8; 80] {
        self.request_with_flags(advertiser, 0)
    }

    pub fn request_le(&self, advertiser: [u8; 6]) -> [u8; 80] {
        // Google's bit numbering starts at MSB: BLE=bit 4, LEA=bit 5.
        self.request_with_flags(advertiser, 0x0c)
    }

    fn request_with_flags(&self, advertiser: [u8; 6], flags: u8) -> [u8; 80] {
        let mut raw = Zeroizing::new([0u8; 16]);
        raw[1] = flags;
        raw[2..8].copy_from_slice(&advertiser);
        OsRng.fill_bytes(&mut raw[8..]);
        let mut result = [0u8; 80];
        result[..16].copy_from_slice(&encrypt_block(&self.key, &raw));
        result[16..].copy_from_slice(&self.public);
        result
    }

    /// Reject every other identity, even if it is the same product/model.
    pub fn accept_response(&mut self, response: &[u8]) -> Result<()> {
        self.authenticated = false;
        self.passkey_verified = false;
        let raw = decrypt_block(&self.key, response)?;
        ensure!(
            raw[0] == 1,
            "Unsupported response type: stop without pairing"
        );
        ensure!(
            raw[1..7] == OWNER_HEADSET,
            "Headset identity mismatch: abort"
        );
        self.authenticated = true;
        Ok(())
    }

    pub fn accept_le_response(&mut self, response: &[u8]) -> Result<()> {
        self.authenticated = false;
        self.passkey_verified = false;
        let raw = decrypt_block(&self.key, response)?;
        ensure!(
            raw[0] == 2,
            "Provider did not select extended LE pairing; stop"
        );
        ensure!(
            raw[1] & 0x40 != 0,
            "Provider does not prefer LE bonding; stop"
        );
        ensure!(
            raw[2] == 1,
            "Additional-component bonding required; not implemented, stop"
        );
        ensure!(
            raw[3..9] == OWNER_HEADSET,
            "Headset identity mismatch: abort"
        );
        self.authenticated = true;
        Ok(())
    }

    pub fn passkey_request(&self, passkey: u32) -> Result<[u8; 16]> {
        ensure!(
            self.authenticated,
            "Authenticate headset before passkey exchange"
        );
        ensure!(passkey <= 999_999, "Invalid six-digit passkey");
        let mut raw = Zeroizing::new([0u8; 16]);
        raw[0] = 2;
        raw[1..4].copy_from_slice(&passkey.to_be_bytes()[1..]);
        OsRng.fill_bytes(&mut raw[4..]);
        Ok(encrypt_block(&self.key, &raw))
    }

    pub fn accept_passkey(&mut self, response: &[u8], expected: u32) -> Result<()> {
        self.passkey_verified = false;
        ensure!(
            self.authenticated && expected <= 999_999,
            "Passkey precondition"
        );
        let raw = decrypt_block(&self.key, response)?;
        ensure!(raw[0] == 3, "Wrong provider passkey message");
        let actual = u32::from_be_bytes([0, raw[1], raw[2], raw[3]]);
        ensure!(
            actual == expected,
            "Passkey mismatch: pairing must be rejected"
        );
        self.passkey_verified = true;
        Ok(())
    }

    pub fn encrypt_account_key(&mut self, key: &[u8; 16], bonded: bool) -> Result<[u8; 16]> {
        ensure!(
            !self.account_key_prepared,
            "Only one account key is allowed per handshake"
        );
        ensure!(
            self.authenticated && self.passkey_verified && bonded,
            "Account key forbidden until identity, passkey and bond are verified"
        );
        ensure!(
            key[0] == 4,
            "Only a persistent standard account key is supported"
        );
        self.account_key_prepared = true;
        Ok(encrypt_block(&self.key, key))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn public_model_key_is_valid_curve_point() {
        model_public_key().unwrap();
    }

    #[test]
    fn correct_model_formats_only_and_never_idle_account_data() {
        assert!(is_pairing_advertisement(&MODEL_ID));
        assert!(is_pairing_advertisement(
            &hex::decode("0037c55c791800").unwrap()
        ));
        // Factory-new marker or unverified sharing capabilities are not part
        // of this already-owned headset's narrowly scoped test.
        assert!(!is_pairing_advertisement(
            &hex::decode("0037c55c791801").unwrap()
        ));
        assert!(!is_pairing_advertisement(
            &hex::decode("10400243290121b3f71a4ce3a963").unwrap()
        ));
        assert!(!is_pairing_advertisement(&[0xda, 0x2d, 0xb1]));
    }

    #[test]
    fn aes_known_answer() {
        let key: [u8; 16] = hex::decode("000102030405060708090a0b0c0d0e0f")
            .unwrap()
            .try_into()
            .unwrap();
        let plain: [u8; 16] = hex::decode("00112233445566778899aabbccddeeff")
            .unwrap()
            .try_into()
            .unwrap();
        let encrypted = encrypt_block(&key, &plain);
        assert_eq!(hex::encode(encrypted), "69c4e0d86a7b0430d8cdb78070b4c55a");
        assert_eq!(*decrypt_block(&key, &encrypted).unwrap(), plain);
        assert!(decrypt_block(&key, &[0; 15]).is_err());
    }

    #[test]
    fn different_headset_cannot_be_paired() {
        let mut hs = Handshake::new().unwrap();
        let mut wrong = [0; 16];
        wrong[0] = 1;
        assert!(hs.accept_response(&encrypt_block(&hs.key, &wrong)).is_err());
        assert!(hs.passkey_request(123456).is_err());
    }

    #[test]
    fn account_key_requires_full_verified_sequence() {
        let mut hs = Handshake::new().unwrap();
        let key = [4; 16]; // Synthetic key only.
        assert!(hs.encrypt_account_key(&key, true).is_err());
        let mut identity = [0; 16];
        identity[0] = 1;
        identity[1..7].copy_from_slice(&OWNER_HEADSET);
        hs.accept_response(&encrypt_block(&hs.key, &identity))
            .unwrap();
        assert!(hs.encrypt_account_key(&key, true).is_err());
        let request = hs.passkey_request(123456).unwrap();
        let mut response = *decrypt_block(&hs.key, &request).unwrap();
        response[0] = 3;
        let encrypted = encrypt_block(&hs.key, &response);
        assert!(hs.accept_passkey(&encrypted, 123455).is_err());
        hs.accept_passkey(&encrypted, 123456).unwrap();
        assert!(hs.encrypt_account_key(&key, false).is_err());
        assert!(hs.encrypt_account_key(&key, true).is_ok());
        assert!(hs.encrypt_account_key(&key, true).is_err());
    }

    #[test]
    fn fresh_handshakes_use_distinct_keys_and_salts() {
        let a = Handshake::new().unwrap();
        let b = Handshake::new().unwrap();
        assert_ne!(a.public, b.public);
        assert_ne!(a.request(OWNER_HEADSET), a.request(OWNER_HEADSET));
    }

    #[test]
    fn le_pairing_requires_single_verified_primary() {
        let mut hs = Handshake::new().unwrap();
        let mut response = [0; 16];
        response[0] = 2;
        response[1] = 0x40;
        response[2] = 1;
        response[3..9].copy_from_slice(&OWNER_HEADSET);
        hs.accept_le_response(&encrypt_block(&hs.key, &response))
            .unwrap();
        response[2] = 2;
        assert!(
            hs.accept_le_response(&encrypt_block(&hs.key, &response))
                .is_err()
        );
        assert!(hs.passkey_request(123456).is_err());
        response[2] = 1;
        response[1] = 0;
        assert!(
            hs.accept_le_response(&encrypt_block(&hs.key, &response))
                .is_err()
        );
    }
}
