const http = require('http');
const { NodeSDK } = require('@opentelemetry/sdk-node');
const { OTLPTraceExporter } = require('@opentelemetry/exporter-trace-otlp-http');
const { trace } = require('@opentelemetry/api');
const Pyroscope = require('@pyroscope/nodejs');

const otlpEndpoint = `${process.env.OTEL_EXPORTER_OTLP_ENDPOINT}/v1/traces`;
const sdk = new NodeSDK({ traceExporter: new OTLPTraceExporter({ url: otlpEndpoint }) });
sdk.start();
Pyroscope.init({ serverAddress: process.env.PYROSCOPE_SERVER_ADDRESS, appName: process.env.PYROSCOPE_APPLICATION_NAME });
Pyroscope.start();

const tracer = trace.getTracer('telemetry.nodejs');
http.createServer((request, response) => {
  if (request.url === '/metrics') {
    response.writeHead(200, { 'content-type': 'text/plain; version=0.0.4' });
    response.end('telemetry_workload_heartbeat_total{language="nodejs"} 1\n');
    return;
  }
  tracer.startActiveSpan('nodejs.work', (span) => {
    console.log('telemetry-workload request language=nodejs');
    response.end('nodejs telemetry workload\n');
    span.end();
  });
}).listen(8080, () => console.log('telemetry-workload listening language=nodejs'));

setInterval(() => tracer.startActiveSpan('nodejs.heartbeat', (span) => { console.log('telemetry-workload heartbeat language=nodejs'); span.end(); }), 10000);
