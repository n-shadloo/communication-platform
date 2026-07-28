use std::{
    fs,
    path::{Path, PathBuf},
};

const LIBSODIUM_SIGNING_KEY: &str = "RWQf6LRCGA9i53mlYecO4IzT51TGPpvWucNSCh1CBM0QTaLn73Y7GFO3";

fn main() {
    let crate_root = PathBuf::from(
        std::env::var_os("CARGO_MANIFEST_DIR").expect("CARGO_MANIFEST_DIR is set by Cargo"),
    );
    let libsodium_root = crate_root.join("vendor").join("libsodium");
    let libsodium_archive = libsodium_root.join("LATEST.tar.gz");
    let libsodium_signature = libsodium_root.join("LATEST.tar.gz.minisig");
    println!("cargo:rerun-if-changed={}", libsodium_archive.display());
    println!("cargo:rerun-if-changed={}", libsodium_signature.display());
    let public_key = minisign_verify::PublicKey::from_base64(LIBSODIUM_SIGNING_KEY)
        .expect("pinned libsodium signing key must parse");
    let signature = minisign_verify::Signature::from_file(&libsodium_signature)
        .expect("pinned libsodium signature must parse");
    let archive = fs::read(&libsodium_archive).expect("pinned libsodium archive must be readable");
    public_key
        .verify(&archive, &signature, false)
        .expect("pinned libsodium archive signature verification failed");

    let vectors_path = crate_root
        .join("..")
        .join("..")
        .join("..")
        .join("backend")
        .join("devices")
        .join("vectors")
        .join("vectors.json");
    println!("cargo:rerun-if-changed={}", vectors_path.display());
    let mut vectors: serde_json::Value = serde_json::from_slice(
        &fs::read(&vectors_path).expect("backend device vectors must be readable"),
    )
    .expect("backend device vectors must be valid JSON");
    vectors
        .as_object_mut()
        .expect("backend device vectors must be an object")
        .remove("seeds");
    let sanitized_vectors =
        serde_json::to_vec(&vectors).expect("sanitized backend device vectors must serialize");
    let output_vectors =
        PathBuf::from(std::env::var_os("OUT_DIR").expect("OUT_DIR is set by Cargo"))
            .join("backend_device_vectors.json");
    fs::write(output_vectors, sanitized_vectors)
        .expect("sanitized backend device vectors must be written");

    let mlkem_root = crate_root.join("vendor").join("mlkem-native").join("mlkem");
    let source = mlkem_root.join("mlkem_native.c");

    emit_rerun_tree(&mlkem_root);

    let mut build = cc::Build::new();
    build
        .file(source)
        .include(&mlkem_root)
        .define("MLK_CONFIG_PARAMETER_SET", "768")
        .define("MLK_CONFIG_NAMESPACE_PREFIX", "CP_CRYPTO_MLKEM")
        .define("MLK_CONFIG_NO_RANDOMIZED_API", None)
        .define("MLK_CONFIG_NO_SUPERCOP", None)
        .warnings(true)
        .flag_if_supported("-std=c99");
    build.compile("communication_crypto_mlkem768");

    if std::env::var("TARGET").is_ok_and(|target| target.contains("windows")) {
        println!("cargo:rustc-link-lib=dylib=advapi32");
    }
}

fn emit_rerun_tree(root: &Path) {
    let mut entries: Vec<_> = fs::read_dir(root)
        .expect("vendored mlkem-native directory must be readable")
        .map(|entry| entry.expect("vendored mlkem-native entry must be readable"))
        .collect();
    entries.sort_by_key(std::fs::DirEntry::path);

    for entry in entries {
        let path = entry.path();
        if path.is_dir() {
            emit_rerun_tree(&path);
        } else {
            println!("cargo:rerun-if-changed={}", path.display());
        }
    }
}
