-- =============================================================================
-- FoundryCast — Migration 0008: Auth bootstrap functions
-- =============================================================================
-- Identity resolution happens BEFORE a tenant context exists, so these run as
-- SECURITY DEFINER (as the owner, bypassing RLS) and are the ONLY sanctioned
-- way the app reads identity/membership without a tenant GUC set. Each is
-- narrow, parameterised, and granted only to the app role.
-- =============================================================================

-- Resolve an external IdP subject (Auth0/Supabase `sub`) to a local user.
CREATE OR REPLACE FUNCTION app_user_by_external_id(p_external_id text)
RETURNS users
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT * FROM users WHERE external_idp_id = p_external_id AND status = 'active';
$$;

-- Return the user's role within a tenant, or NULL if not a member.
CREATE OR REPLACE FUNCTION app_membership_role(p_user uuid, p_tenant uuid)
RETURNS foundry_role
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT role FROM tenant_memberships
  WHERE user_id = p_user AND tenant_id = p_tenant
  LIMIT 1;
$$;

-- List every tenant the user belongs to (for the tenant switcher / GET /me).
CREATE OR REPLACE FUNCTION app_user_memberships(p_user uuid)
RETURNS TABLE (tenant_id uuid, tenant_name text, slug citext, role foundry_role)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public AS $$
  SELECT t.id, t.name, t.slug, m.role
  FROM tenant_memberships m
  JOIN tenants t ON t.id = m.tenant_id
  WHERE m.user_id = p_user
  ORDER BY t.name;
$$;

REVOKE ALL ON FUNCTION app_user_by_external_id(text) FROM PUBLIC;
REVOKE ALL ON FUNCTION app_membership_role(uuid, uuid) FROM PUBLIC;
REVOKE ALL ON FUNCTION app_user_memberships(uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION app_user_by_external_id(text) TO foundrycast_app;
GRANT EXECUTE ON FUNCTION app_membership_role(uuid, uuid) TO foundrycast_app;
GRANT EXECUTE ON FUNCTION app_user_memberships(uuid) TO foundrycast_app;
