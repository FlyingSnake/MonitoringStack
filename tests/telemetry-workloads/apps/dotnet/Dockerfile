FROM mcr.microsoft.com/dotnet/sdk:8.0.414-bookworm-slim AS build
WORKDIR /src
COPY DotnetTelemetry.csproj ./
RUN dotnet restore
COPY Program.cs ./
RUN dotnet publish -c Release -o /out --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0.21-bookworm-slim
ARG TARGETARCH
ARG PYROSCOPE_DOTNET_VERSION=1.4.0
WORKDIR /app
RUN apt-get update \
 && apt-get install -y --no-install-recommends curl \
 && mkdir -p /opt/pyroscope \
 && case "${TARGETARCH:-$(dpkg --print-architecture)}" in \
      amd64|x86_64) profiler_arch=x64 ;; \
      arm64|aarch64) profiler_arch=aarch64 ;; \
      *) echo "Unsupported .NET profiler architecture: ${TARGETARCH}" >&2; exit 1 ;; \
    esac \
 && curl -fsSL "https://github.com/grafana/pyroscope-dotnet/releases/download/pyroscope-${PYROSCOPE_DOTNET_VERSION}/pyroscope.${PYROSCOPE_DOTNET_VERSION}-glibc-${profiler_arch}.tar.gz" | tar -xz -C /opt/pyroscope \
 && rm -rf /var/lib/apt/lists/*
COPY --from=build /out ./
COPY entrypoint.sh /usr/local/bin/telemetry-entrypoint
RUN chmod 0755 /usr/local/bin/telemetry-entrypoint
EXPOSE 8080
ENTRYPOINT ["/usr/local/bin/telemetry-entrypoint"]
