CREATE TABLE provider_health_states_new (
    id TEXT,
    provider_id TEXT NOT NULL,
    scope TEXT NOT NULL DEFAULT 'global',
    gateway_id TEXT NOT NULL DEFAULT '',
    model TEXT NOT NULL DEFAULT '',
    status TEXT NOT NULL DEFAULT 'healthy',
    failure_streak INTEGER NOT NULL DEFAULT 0,
    success_streak INTEGER NOT NULL DEFAULT 0,
    last_check_at TEXT,
    last_success_at TEXT,
    last_failure_at TEXT,
    last_failure_reason TEXT,
    circuit_open_until TEXT,
    recover_after TEXT,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (provider_id, scope, gateway_id, model),
    FOREIGN KEY (provider_id) REFERENCES providers(id)
);

INSERT INTO provider_health_states_new (
    id,
    provider_id,
    scope,
    gateway_id,
    model,
    status,
    failure_streak,
    success_streak,
    last_check_at,
    last_success_at,
    last_failure_at,
    last_failure_reason,
    circuit_open_until,
    recover_after,
    updated_at
)
SELECT
    provider_id || ':' || COALESCE(scope, 'global') AS id,
    provider_id,
    COALESCE(scope, 'global') AS scope,
    '' AS gateway_id,
    '' AS model,
    status,
    failure_streak,
    success_streak,
    last_check_at,
    last_success_at,
    last_failure_at,
    last_failure_reason,
    circuit_open_until,
    recover_after,
    updated_at
FROM provider_health_states;

DROP TABLE provider_health_states;
ALTER TABLE provider_health_states_new RENAME TO provider_health_states;

CREATE INDEX idx_provider_health_states_provider_scope
ON provider_health_states (provider_id, scope, gateway_id, model);
