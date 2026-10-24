# syntax=docker/dockerfile:1

# Fully qualified image names: rootless podman has no default registry.
FROM docker.io/library/golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=0.4.0
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/skedd ./cmd/skedd \
    && mkdir -p /out/data/overrides

# Static binary on distroless: CA certificates for https://rasp.vksit.ru,
# no shell, non-root user 65532.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/skedd /skedd
# /data is owned by the runtime user so a fresh named volume (which copies
# the image's ownership) is writable under both docker and rootless podman.
COPY --from=build --chown=65532:65532 /out/data /data
ENV SKED_ADDR=0.0.0.0:1984 \
    SKED_DATA=/data
VOLUME /data
EXPOSE 1984
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/skedd", "-healthcheck"]
ENTRYPOINT ["/skedd"]
