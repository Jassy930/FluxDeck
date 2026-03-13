CREATE TABLE IF NOT EXISTS provider_health_states (
    provider_id TEXT PRIMARY KEY,
    scope TEXT NOT NULL DEFAULT 'global',
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
    FOREIGN KEY (provider_id) REFERENCES providers(id)
);

INSERT INTO provider_health_states (provider_id, scope, status)
SELECT
    providers.id,
    'global',
    'healthy'
FROM providers
WHERE NOT EXISTS (
    SELECT 1
    FROM provider_health_states
    WHERE provider_health_states.provider_id = providers.id
);
