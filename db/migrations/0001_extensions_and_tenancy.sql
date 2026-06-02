-- =============================================================================
-- FoundryCast — Migration 0001: Extensions, Tenancy, RBAC, shared helpers
-- =============================================================================
-- Multi-tenant foundry SaaS. Every business table carries:
--   tenant_id, created_by, created_at, updated_at
-- Tenant isolation is enforced at the database level via Row Level Security,
-- keyed off the session GUC `app.current_tenant`. The API sets this per request
-- (e.g. `SET LOCAL app.current_tenant = '<uuid>'` inside the request transaction).
-- This is backend-agnostic: it works the same whether the API is Node or Python.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;   -- gen_random_uuid()
CREATE EXTENSION IF NOT EXISTS citext;      -- case-insensitive text (emails, codes)

-- -----------------------------------------------------------------------------
-- Shared helper: updated_at auto-touch trigger
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS trigger AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION attach_updated_at(p_table regclass)
RETURNS void AS $$
BEGIN
  EXECUTE format(
    'CREATE TRIGGER trg_%s_updated_at BEFORE UPDATE ON %s
       FOR EACH ROW EXECUTE FUNCTION set_updated_at()',
    replace(p_table::text, '.', '_'), p_table);
END;
$$ LANGUAGE plpgsql;

-- -----------------------------------------------------------------------------
-- Shared helper: enable tenant Row Level Security on a table
-- Assumes the table has a `tenant_id uuid` column.
-- -----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION enable_tenant_rls(p_table regclass)
RETURNS void AS $$
BEGIN
  EXECUTE format('ALTER TABLE %s ENABLE ROW LEVEL SECURITY', p_table);
  EXECUTE format('ALTER TABLE %s FORCE ROW LEVEL SECURITY', p_table);
  EXECUTE format(
    'CREATE POLICY tenant_isolation ON %s
       USING (tenant_id = current_setting(''app.current_tenant'', true)::uuid)
       WITH CHECK (tenant_id = current_setting(''app.current_tenant'', true)::uuid)',
    p_table);
END;
$$ LANGUAGE plpgsql;

-- =============================================================================
-- Tenancy & identity
-- =============================================================================

-- Tenants are the only table NOT tenant-scoped (they define the tenants).
CREATE TABLE tenants (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  name         text NOT NULL,
  slug         citext NOT NULL UNIQUE,
  status       text NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'suspended', 'trial')),
  settings     jsonb NOT NULL DEFAULT '{}',   -- per-foundry Yes/No console + terminology overrides
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('tenants');

-- Users are global identities; membership binds a user to a tenant with a role.
CREATE TABLE users (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  email         citext NOT NULL UNIQUE,
  full_name     text NOT NULL,
  external_idp_id text,                 -- Auth0/Supabase subject; auth lives outside the DB
  status        text NOT NULL DEFAULT 'active'
                CHECK (status IN ('active', 'disabled')),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('users');

-- Roles per the build plan §4.1 (RBAC). Function-level grants layered on top later.
CREATE TYPE foundry_role AS ENUM (
  'admin',
  'production_manager',
  'supervisor',
  'operator',
  'qa',
  'sales',
  'finance'
);

CREATE TABLE tenant_memberships (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  role        foundry_role NOT NULL,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, user_id, role)
);
SELECT attach_updated_at('tenant_memberships');
SELECT enable_tenant_rls('tenant_memberships');
CREATE INDEX idx_memberships_user ON tenant_memberships(user_id);
CREATE INDEX idx_memberships_tenant ON tenant_memberships(tenant_id);
