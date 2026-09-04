#!/bin/sh
set -eu

profiler_root="/opt/pyroscope"
case "$(uname -m)" in
  x86_64|amd64) wrapper="${profiler_root}/Pyroscope.Linux.ApiWrapper.x64.so" ;;
  aarch64|arm64) wrapper="${profiler_root}/Pyroscope.Linux.ApiWrapper.arm64.so" ;;
  *) wrapper="" ;;
esac

profiler="${profiler_root}/Pyroscope.Profiler.Native.so"
if [ -n "${wrapper}" ] && [ -r "${profiler}" ] && [ -r "${wrapper}" ]; then
  export PYROSCOPE_PROFILING_ENABLED=1
  export CORECLR_ENABLE_PROFILING=1
  export CORECLR_PROFILER="{BD1A650D-AC5D-4896-B64F-D6FA25D6B26A}"
  export CORECLR_PROFILER_PATH="${profiler}"
  export LD_PRELOAD="${wrapper}${LD_PRELOAD:+:${LD_PRELOAD}}"
  export LD_LIBRARY_PATH="${profiler_root}${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
else
  unset PYROSCOPE_PROFILING_ENABLED CORECLR_ENABLE_PROFILING CORECLR_PROFILER CORECLR_PROFILER_PATH LD_PRELOAD
  echo "Pyroscope .NET profiler is unavailable for $(uname -m); continuing with logs, metrics, and traces only." >&2
fi

exec dotnet DotnetTelemetry.dll
