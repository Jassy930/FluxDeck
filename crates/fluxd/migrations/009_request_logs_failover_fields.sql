ALTER TABLE request_logs ADD COLUMN failover_performed INTEGER NOT NULL DEFAULT 0;
ALTER TABLE request_logs ADD COLUMN route_attempt_count INTEGER NOT NULL DEFAULT 0;
ALTER TABLE request_logs ADD COLUMN provider_id_initial TEXT;
