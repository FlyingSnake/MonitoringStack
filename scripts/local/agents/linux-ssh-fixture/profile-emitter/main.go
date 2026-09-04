package main

import (
  "log"
  "os"
  "time"

  "github.com/grafana/pyroscope-go"
)

func main() {
  serverAddress := os.Getenv("PYROSCOPE_SERVER_ADDRESS")
  if serverAddress == "" {
    log.Fatal("PYROSCOPE_SERVER_ADDRESS is required")
  }

  _, err := pyroscope.Start(pyroscope.Config{
    ApplicationName: "linux-alloy-fixture-profile",
    ServerAddress:   serverAddress,
  })
  if err != nil {
    log.Fatalf("start Pyroscope profiler: %v", err)
  }

  for {
    deadline := time.Now().Add(time.Second)
    var work uint64
    for time.Now().Before(deadline) {
      work++
    }
    log.Printf("profile-emitter heartbeat work=%d", work)
    time.Sleep(time.Second)
  }
}
