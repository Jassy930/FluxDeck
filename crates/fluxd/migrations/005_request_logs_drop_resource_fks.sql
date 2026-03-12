-- no-transaction

PRAGMA foreign_keys=OFF;

CREATE TABLE request_logs_new (
    request_id TEXT PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    model TEXT,
    status_code INTEGER NOT NULL,
    latency_ms INTEGER NOT NULL,
    error TEXT,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    inbound_protocol TEXT,
    upstream_protocol TEXT,
    model_requested TEXT,
    model_effective TEXT,
    stream INTEGER NOT NULL DEFAULT 0,
    first_byte_ms INTEGER,
    input_tokens INTEGER,
    output_tokens INTEGER,
    total_tokens INTEGER,
    usage_json TEXT,
    error_stage TEXT,
    error_type TEXT
);

INSERT INTO request_logs_new (
    request_id,
    gateway_id,
    provider_id,
    model,
    status_code,
    latency_ms,
    error,
    created_at,
    inbound_protocol,
    upstream_protocol,
    model_requested,
    model_effective,
    stream,
    first_byte_ms,
    input_tokens,
    output_tokens,
    total_tokens,
    usage_json,
    error_stage,
    error_type
)
SELECT
    request_id,
    gateway_id,
    provider_id,
    model,
    status_code,
    latency_ms,
    error,
    created_at,
    inbound_protocol,
    upstream_protocol,
    model_requested,
    model_effective,
    stream,
    first_byte_ms,
    input_tokens,
    output_tokens,
    total_tokens,
    usage_json,
    error_stage,
    error_type
FROM request_logs;

DROP TABLE request_logs;
ALTER TABLE request_logs_new RENAME TO request_logs;

PRAGMA foreign_keys=ON;
