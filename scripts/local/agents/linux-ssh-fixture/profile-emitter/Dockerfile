FROM golang:1.25.0-bookworm AS build

WORKDIR /src
COPY go.mod ./
RUN go mod download
COPY main.go ./
RUN go mod tidy && CGO_ENABLED=0 go build -o /out/profile-emitter ./main.go

FROM gcr.io/distroless/static-debian12:nonroot

COPY --from=build /out/profile-emitter /profile-emitter
USER nonroot:nonroot
ENTRYPOINT ["/profile-emitter"]
