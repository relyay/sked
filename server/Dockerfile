# syntax=docker/dockerfile:1

FROM golang:1.27-alpine AS build
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/skedd ./cmd/skedd

# Static binary on distroless: CA certificates for https://rasp.vksit.ru,
# no shell. Runs as the non-root user unless compose overrides it.
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/skedd /skedd
ENV SKED_ADDR=0.0.0.0:1984 \
    SKED_DATA=/data
VOLUME /data
EXPOSE 1984
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 CMD ["/skedd", "-healthcheck"]
ENTRYPOINT ["/skedd"]
