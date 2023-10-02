# -----------------------------
# Build Kdash base image
# -----------------------------

# force older version due to https://github.com/rust-lang/rust/issues/116348
FROM rust:1.71 as builder
WORKDIR /usr/src

# Prepare for static linking with musl
RUN apt-get update && \
    apt-get dist-upgrade -y && \
    apt-get install -y musl-tools && \
    # rustup default nightly && \
    rustup target add x86_64-unknown-linux-musl 

# Download and compile Rust dependencies in an empty project and cache as a separate Docker layer
RUN USER=root cargo new --bin kdash-temp
WORKDIR /usr/src/kdash-temp
COPY ./Cargo.lock ./Cargo.lock
COPY ./Cargo.toml ./Cargo.toml
RUN cargo build --release --target x86_64-unknown-linux-musl
# remove src form empty project
RUN rm -r src

# Copy actual source files and Build the app binary
COPY src ./src
# remove previous deps
RUN rm ./target/x86_64-unknown-linux-musl/release/deps/kdash*
# due to cargo bug https://github.com/rust-lang/rust/issues/25289
RUN apt-get install -y -qq pkg-config libssl-dev libxcb1-dev libxcb-render0-dev libxcb-shape0-dev libxcb-xfixes0-dev

RUN RUST_BACKTRACE=1 cargo build --release --target x86_64-unknown-linux-musl

# -----------------------------
# build final Kdash image
# -----------------------------

FROM alpine:latest

ARG KUBECTL_VERSION="v1.20.5"
# Copy the compiled binary from the builder container
COPY --from=builder /usr/src/kdash-temp/target/x86_64-unknown-linux-musl/release/kdash /usr/local/bin

# Install dependencies like kubectl
RUN apk add --update ca-certificates \
    && apk add --update -t deps curl vim \
    && curl -L https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl -o /usr/local/bin/kubectl \
    && chmod +x /usr/local/bin/kubectl \
    && apk del --purge deps \
    && rm /var/cache/apk/*

ENTRYPOINT [ "/usr/local/bin/kdash" ]
