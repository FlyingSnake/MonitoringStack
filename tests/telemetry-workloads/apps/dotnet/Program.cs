using System.Diagnostics;
using OpenTelemetry.Resources;
using OpenTelemetry.Trace;

var builder = WebApplication.CreateBuilder(args);
var activitySource = new ActivitySource("telemetry.dotnet");
builder.Services.AddOpenTelemetry().WithTracing(tracing => tracing
    .SetResourceBuilder(ResourceBuilder.CreateDefault().AddService("telemetry.dotnet"))
    .AddSource("telemetry.dotnet")
    .AddOtlpExporter(options =>
    {
        options.Endpoint = new Uri($"{Environment.GetEnvironmentVariable("OTEL_EXPORTER_OTLP_ENDPOINT")}/v1/traces");
        options.Protocol = OpenTelemetry.Exporter.OtlpExportProtocol.HttpProtobuf;
    }));

var app = builder.Build();
app.MapGet("/metrics", () => Results.Text("telemetry_workload_heartbeat_total{language=\"dotnet\"} 1\n", "text/plain; version=0.0.4"));
app.MapGet("/", () =>
{
    using var activity = activitySource.StartActivity("dotnet.work");
    app.Logger.LogInformation("telemetry-workload request language=dotnet");
    return Results.Text("dotnet telemetry workload\n");
});
_ = Task.Run(async () =>
{
    while (true)
    {
        using var activity = activitySource.StartActivity("dotnet.heartbeat");
        app.Logger.LogInformation("telemetry-workload heartbeat language=dotnet");
        await Task.Delay(TimeSpan.FromSeconds(10));
    }
});
app.Run("http://0.0.0.0:8080");
