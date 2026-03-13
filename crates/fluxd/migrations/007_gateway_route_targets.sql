CREATE TABLE IF NOT EXISTS gateway_route_targets (
    id TEXT PRIMARY KEY,
    gateway_id TEXT NOT NULL,
    provider_id TEXT NOT NULL,
    priority INTEGER NOT NULL,
    enabled INTEGER NOT NULL DEFAULT 1,
    created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
    FOREIGN KEY (gateway_id) REFERENCES gateways(id),
    FOREIGN KEY (provider_id) REFERENCES providers(id),
    UNIQUE (gateway_id, priority),
    UNIQUE (gateway_id, provider_id)
);

INSERT INTO gateway_route_targets (id, gateway_id, provider_id, priority, enabled)
SELECT
    gateways.id || '__route__0',
    gateways.id,
    gateways.default_provider_id,
    0,
    1
FROM gateways
WHERE NOT EXISTS (
    SELECT 1
    FROM gateway_route_targets
    WHERE gateway_route_targets.gateway_id = gateways.id
);
