FROM golang:1.25.0-bookworm AS build
WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN go mod tidy && CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -o /out/app ./main.go

FROM gcr.io/distroless/base-debian12:nonroot
COPY --from=build /out/app /app
USER nonroot:nonroot
ENTRYPOINT ["/app"]
