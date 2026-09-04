package monitoring.stack;

import com.sun.net.httpserver.HttpServer;
import io.opentelemetry.api.GlobalOpenTelemetry;
import io.opentelemetry.api.common.AttributeKey;
import io.opentelemetry.api.common.Attributes;
import io.opentelemetry.api.trace.Tracer;
import io.opentelemetry.exporter.otlp.http.trace.OtlpHttpSpanExporter;
import io.opentelemetry.sdk.OpenTelemetrySdk;
import io.opentelemetry.sdk.resources.Resource;
import io.opentelemetry.sdk.trace.SdkTracerProvider;
import io.opentelemetry.sdk.trace.export.BatchSpanProcessor;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.time.Duration;

public class App {
  public static void main(String[] args) throws Exception {
    String endpoint = System.getenv("OTEL_EXPORTER_OTLP_ENDPOINT") + "/v1/traces";
    var exporter = OtlpHttpSpanExporter.builder().setEndpoint(endpoint).setTimeout(Duration.ofSeconds(5)).build();
    var provider = SdkTracerProvider.builder().addSpanProcessor(BatchSpanProcessor.builder(exporter).build())
      .setResource(Resource.getDefault().merge(Resource.create(Attributes.of(AttributeKey.stringKey("service.name"), "telemetry.java")))).build();
    OpenTelemetrySdk.builder().setTracerProvider(provider).buildAndRegisterGlobal();
    Tracer tracer = GlobalOpenTelemetry.getTracer("telemetry.java");
    HttpServer server = HttpServer.create(new InetSocketAddress(8080), 0);
    server.createContext("/metrics", exchange -> { byte[] body = "telemetry_workload_heartbeat_total{language=\"java\"} 1\n".getBytes(StandardCharsets.UTF_8); exchange.sendResponseHeaders(200, body.length); exchange.getResponseBody().write(body); exchange.close(); });
    server.createContext("/", exchange -> { var span = tracer.spanBuilder("java.work").startSpan(); System.out.println("telemetry-workload request language=java"); byte[] body = "java telemetry workload\n".getBytes(StandardCharsets.UTF_8); exchange.sendResponseHeaders(200, body.length); exchange.getResponseBody().write(body); exchange.close(); span.end(); });
    server.start();
    Thread.ofVirtual().start(() -> { while (true) { var span = tracer.spanBuilder("java.heartbeat").startSpan(); System.out.println("telemetry-workload heartbeat language=java"); span.end(); try { Thread.sleep(10000); } catch (InterruptedException ignored) { return; } } });
  }
}
