package main

import (
  "context"
  "fmt"
  "log"
  "net/http"
  "os"
  "time"

  "github.com/grafana/pyroscope-go"
  "go.opentelemetry.io/otel"
  "go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
  "go.opentelemetry.io/otel/sdk/resource"
  "go.opentelemetry.io/otel/sdk/trace"
  semconv "go.opentelemetry.io/otel/semconv/v1.26.0"
)

func main() {
  ctx := context.Background()
  endpoint := os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
  exporter, err := otlptracehttp.New(ctx, otlptracehttp.WithEndpointURL(endpoint+"/v1/traces"))
  if err != nil { log.Fatal(err) }
  provider := trace.NewTracerProvider(trace.WithBatcher(exporter), trace.WithResource(resource.NewWithAttributes("", semconv.ServiceName("telemetry.go"))))
  defer provider.Shutdown(ctx)
  otel.SetTracerProvider(provider)
  _, err = pyroscope.Start(pyroscope.Config{ApplicationName: "telemetry.go", ServerAddress: os.Getenv("PYROSCOPE_SERVER_ADDRESS")})
  if err != nil { log.Printf("pyroscope start: %v", err) }

  http.HandleFunc("/metrics", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "telemetry_workload_heartbeat_total{language=\"go\"} 1") })
  http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
    _, span := otel.Tracer("telemetry.go").Start(r.Context(), "go.work")
    defer span.End()
    fmt.Fprintln(w, "go telemetry workload")
  })
  go func() { for range time.Tick(10 * time.Second) { _, span := otel.Tracer("telemetry.go").Start(ctx, "go.heartbeat"); span.End(); log.Print("telemetry-workload heartbeat language=go") } }()
  log.Fatal(http.ListenAndServe(":8080", nil))
}
