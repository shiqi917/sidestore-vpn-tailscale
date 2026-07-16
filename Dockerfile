# Build stage
FROM rust:alpine AS builder

RUN apk add --no-cache musl-dev

WORKDIR /app

COPY Cargo.toml Cargo.lock ./
COPY src ./src

RUN cargo build --release

# Combined image: tailscale + reflector (same layout as ghcr.io/xddxdd/sidestore-vpn:tailscale)
FROM tailscale/tailscale:stable

ENV TS_USERSPACE="false"
ENV TS_STATE_DIR="/var/lib/tailscale"
ENV TS_TAILSCALED_EXTRA_ARGS="--verbose=-1"
ENV REFLECT_ADDR="10.7.0.1"

COPY --from=builder /app/target/release/sidestore-vpn /sidestore-vpn
COPY --chmod=755 tailscale-entrypoint.sh /tailscale-entrypoint.sh

ENTRYPOINT ["/tailscale-entrypoint.sh"]
