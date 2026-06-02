-- =============================================================================
-- FoundryCast — Migration 0007: Application DB role
-- =============================================================================
-- The API connects as a NON-superuser, NON-owner role so Row Level Security
-- genuinely constrains it. (Superusers and table owners bypass RLS unless the
-- table is FORCEd — ours are — but a least-privilege app role is correct regardless.)
--
-- DEV password below is intentionally trivial. In production, create this role
-- out-of-band with a managed secret and DO NOT ship a password in a migration.
-- =============================================================================

DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'foundrycast_app') THEN
    CREATE ROLE foundrycast_app LOGIN PASSWORD 'app';
  END IF;
END $$;

GRANT USAGE ON SCHEMA public TO foundrycast_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO foundrycast_app;
GRANT USAGE, SELECT ON ALL SEQUENCES IN SCHEMA public TO foundrycast_app;

-- Apply to tables/sequences created by later migrations too.
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO foundrycast_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  GRANT USAGE, SELECT ON SEQUENCES TO foundrycast_app;
