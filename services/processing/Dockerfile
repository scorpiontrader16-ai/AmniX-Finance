# ╔══════════════════════════════════════════════════════════════════════╗
# ║  Full path: services/processing/Dockerfile                          ║
# ║  Multi-arch Rust build via QEMU — F-DC06 fix                        ║
# ║                                                                      ║
# ║  Cross-compilation approach:                                         ║
# ║    All stages run on $TARGETPLATFORM.                                ║
# ║    When building linux/arm64 on an amd64 host, Docker BuildKit uses  ║
# ║    QEMU emulation transparently via `docker buildx build --platform` ║
# ║                                                                      ║
# ║  Why not --platform=$BUILDPLATFORM + TARGETARCH cross-compile:       ║
# ║    rdkafka (cmake-build + ssl) requires C cross-toolchain + cross-   ║
# ║    compiled system libs (libssl, libsasl2) for the target arch.      ║
# ║    The QEMU approach is slower but correct and maintenance-free.     ║
# ║                                                                      ║
# ║  cargo-chef still provides layer caching benefits within a single    ║
# ║  platform build — the recipe.json fingerprints Cargo.lock changes.  ║
# ╚══════════════════════════════════════════════════════════════════════╝

# ── Stage 1: chef installer — runs on TARGETPLATFORM ─────────────────────
FROM rust:1.88-slim AS chef
RUN apt-get update && apt-get install -y --no-install-recommends \
    cmake make gcc g++ pkg-config \
    libssl-dev libsasl2-dev libcurl4-openssl-dev \
    protobuf-compiler curl \
    && rm -rf /var/lib/apt/lists/*
RUN cargo install cargo-chef --version 0.1.67 --locked
WORKDIR /app

# ── Stage 2: dependency fingerprint ──────────────────────────────────────
FROM chef AS planner
COPY services/processing/ .
COPY proto/ ../../proto/
RUN cargo chef prepare --recipe-path recipe.json

# ── Stage 3: compile dependencies (cached layer) ─────────────────────────
FROM chef AS builder-deps
COPY --from=planner /app/recipe.json recipe.json
RUN cargo chef cook --release --recipe-path recipe.json

# ── Stage 4: compile service binary ──────────────────────────────────────
FROM builder-deps AS builder
ARG BUILD_VERSION=dev
COPY services/processing/ .
COPY proto/ ../../proto/
RUN cargo build \
    --release \
    && strip target/release/processing

# ── Stage 5: minimal runtime image ───────────────────────────────────────
FROM gcr.io/distroless/cc-debian12:nonroot
COPY --from=builder /app/target/release/processing /processing
LABEL org.opencontainers.image.title="processing-service"
LABEL org.opencontainers.image.description="Rust analytical processing engine"
USER 65532:65532
EXPOSE 50051
EXPOSE 9090
ENTRYPOINT ["/processing"]
