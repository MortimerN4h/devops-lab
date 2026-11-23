# ---- Stage 1 "build": the Go compiler (~300 MB) turns the source into ONE binary file ----
FROM golang:1.25-alpine AS build
WORKDIR /src
# Dependencies first (only re-downloaded when go.mod/go.sum change = Docker layer cache)
COPY go.mod go.sum ./
RUN go mod download
COPY . .
# CGO_ENABLED=0: pure Go, no C library needed -> the binary runs on an EMPTY image
# -trimpath: no build-machine paths inside the binary; -ldflags "-s -w": drop debug info (smaller)
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w" -o /out/server .

# ---- Stage 2: image cuối = binary + almost nothing else (~15 MB, no shell, no package manager) ----
FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/server /server
ENV GIN_MODE=release
EXPOSE 8080
# The ":nonroot" image already runs as user 65532 (not root)
ENTRYPOINT ["/server"]
