# syntax=docker/dockerfile:1

# ---- build ------------------------------------------------------------------
# The build stage runs natively and cross-compiles, so a multi-platform image
# does not compile Go under emulation.
FROM --platform=$BUILDPLATFORM golang:1.27-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

# git lets the toolchain stamp the release from .git (see util.Version), so a
# server reports what it was built from without anyone passing a version.
RUN apk add --no-cache git

# CGO off: the SQLite driver is modernc's pure-Go one, so the result is a static
# binary and the runtime image needs nothing but CA certificates.
# Without .git the toolchain stamps nothing, so the release workflow passes the
# release in instead.
# A stack built from a git checkout (Portainer, `docker compose up --build`)
# passes nothing, so the release is read from the checkout's tags here: the
# toolchain's own stamp is a pseudo-version, or nothing at all when the clone is
# shallow, and the server would report `dev`. Set REVOKED_VERSION in the stack's
# environment when the checkout has no .git.
ARG REVOKED_VERSION=""
ARG TARGETOS TARGETARCH
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    VERSION="$REVOKED_VERSION"; \
    if [ -z "$VERSION" ] && [ -d .git ]; then \
      git config --global --add safe.directory /src; \
      VERSION="$(git describe --tags --always 2>/dev/null || true)"; \
    fi; \
    CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH go build -trimpath \
      -ldflags="-s -w -X revoked/util.releaseVersion=${VERSION}" \
      -o /out/revoked ./cmd/revoked

# ---- runtime ----------------------------------------------------------------
FROM alpine:3.22

# ca-certificates: outbound DNS-over-HTTPS verification and callback delivery.
# wget: the healthcheck below. tzdata: expiry timestamps in local time.
RUN apk add --no-cache ca-certificates tzdata wget \
    && adduser -D -H -u 10001 revoked

WORKDIR /pb
COPY --from=build /out/revoked /pb/revoked

# pb_data holds server_root.pem and server_cert.json — the CA private key that
# signs every identity certificate this server issues. It is the one directory
# whose loss or disclosure cannot be recovered from, so it is owned by the
# unprivileged user and readable by nobody else.
RUN mkdir -p /pb/pb_data \
    && chown -R revoked:revoked /pb \
    && chmod 700 /pb/pb_data

USER revoked

# No EXPOSE: the listen port comes from the command below, which compose
# overrides, so naming one here would only ever be right by coincidence.
HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD wget -qO- http://127.0.0.1:3000/healthz >/dev/null || exit 1

ENTRYPOINT ["/pb/revoked"]
CMD ["serve", "--http=0.0.0.0:3000", "--dir=/pb/pb_data"]
