# syntax=docker/dockerfile:1

# ---- build ------------------------------------------------------------------
FROM golang:1.25-alpine AS build

WORKDIR /src

COPY go.mod go.sum ./
RUN --mount=type=cache,target=/go/pkg/mod go mod download

COPY . .

# CGO off: the SQLite driver is modernc's pure-Go one, so the result is a static
# binary and the runtime image needs nothing but CA certificates.
RUN --mount=type=cache,target=/go/pkg/mod \
    --mount=type=cache,target=/root/.cache/go-build \
    CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" -o /out/revoked ./cmd/revoked

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
