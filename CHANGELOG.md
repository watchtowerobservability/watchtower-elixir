## 0.1.1

- Sync with the monorepo: ETS, DETS, Mnesia and Cachex health metrics.

- Logs and metrics over the OTel Erlang SDKs (`opentelemetry_experimental`): `Watchtower.Logs.install/2` adds the OTLP `:logger` handler (trace and span ids from the process metadata), `Config.metrics_env/1` configures a periodic OTLP reader with delta temporality. `WATCHTOWER_LOGS` / `WATCHTOWER_METRICS` switch them (default on). `Watchtower.Spool` now wraps any signal's exporter; with `WT_SPOOL_DIR` logs and metrics spool to `logs/` and `metrics/`.

- Offline file spool: `spool_dir` / `WT_SPOOL_DIR` makes `otel_env/1` use `Watchtower.Spool`, which writes failed span batches as OTLP protobuf and resends them oldest first.

## 0.1.0

- Config and OTel exporter environment, redaction hook, exception capture.
- Logger handler, Plug/Phoenix error capture, Oban failure capture.
