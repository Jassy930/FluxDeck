ALTER TABLE gateways
ADD COLUMN upstream_protocol TEXT NOT NULL DEFAULT 'provider_default';

ALTER TABLE gateways
ADD COLUMN protocol_config_json TEXT NOT NULL DEFAULT '{}';
