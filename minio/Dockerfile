# Bouw een lokale MinIO-image uit de officieel ondertekende releasebinary.
FROM golang:1.24-alpine AS verify-release

ARG TARGETARCH
ARG MINIO_VERSION

RUN apk add --no-cache ca-certificates curl && \
    go install aead.dev/minisign/cmd/minisign@v0.2.1

RUN curl --fail --silent --show-error --location \
      "https://dl.min.io/server/minio/release/linux-${TARGETARCH}/archive/minio.${MINIO_VERSION}" \
      --output /usr/local/bin/minio && \
    curl --fail --silent --show-error --location \
      "https://dl.min.io/server/minio/release/linux-${TARGETARCH}/archive/minio.${MINIO_VERSION}.minisig" \
      --output /tmp/minio.minisig && \
    chmod +x /usr/local/bin/minio && \
    minisign -Vqm /usr/local/bin/minio \
      -x /tmp/minio.minisig \
      -P RWTx5Zr1tiHQLwG9keckT0c45M3AGeHD6IvimQHpyRywVWGbP1aVSGav

FROM alpine:3.22

RUN apk add --no-cache ca-certificates curl

COPY --from=verify-release /usr/local/bin/minio /usr/local/bin/minio

EXPOSE 9000 9001

ENTRYPOINT ["/usr/local/bin/minio"]
CMD ["server", "/data"]
