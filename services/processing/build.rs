fn main() -> Result<(), Box<dyn std::error::Error>> {
    let manifest_dir = std::env::var("CARGO_MANIFEST_DIR")?;
    let proto_root   = format!("{}/../../proto", manifest_dir);
    let out_dir      = std::env::var("OUT_DIR")?;

    // ── Pass 1: ingestion.v1 ─────────────────────────────────────────────
    // Generate ONLY message types (no server/client traits).
    // This produces the real Rust structs at crate::ingestion::v1.
    tonic_build::configure()
        .build_server(false)
        .build_client(false)
        .compile_protos(
            &[&format!("{}/ingestion/v1/events.proto", proto_root)],
            &[&proto_root],
        )?;

    // ── Pass 2: processing.v1 ────────────────────────────────────────────
    // Generate server + client. Use extern_path so prost does NOT re-generate
    // ingestion types here — it references the ones from Pass 1 instead.
    tonic_build::configure()
        .build_server(true)
        .build_client(true)
        .file_descriptor_set_path(
            std::path::PathBuf::from(&out_dir).join("processing_descriptor.bin"),
        )
        .extern_path(".ingestion.v1", "crate::ingestion::v1")
        .compile_protos(
            &[&format!("{}/processing/v1/engine.proto", proto_root)],
            &[&proto_root],
        )?;

    println!("cargo:rerun-if-changed={}/processing/v1/engine.proto", proto_root);
    println!("cargo:rerun-if-changed={}/ingestion/v1/events.proto",  proto_root);
    Ok(())
}
