# @foundrycast/api

Node + TypeScript + Fastify API. PostgreSQL via `postgres.js`. Auth via `jose`
(dev HS256 / prod JWKS for Auth0 or Supabase).

## The security model
Three layers, each independently enforced:

1. **Authentication** (`plugins/auth.ts` → `authenticate`) — verifies the bearer
   JWT and resolves it to a local user. `users` is a global table.
2. **Tenant membership** (`plugins/auth.ts` → `requireTenant`) — reads the active
   tenant from the token claim / `x-tenant-id` header and confirms the user is a
   member via the `app_membership_role` SECURITY DEFINER function, attaching their
   role for that foundry.
3. **Row Level Security** (`db/index.ts` → `withTenant`) — every tenant-scoped
   query runs inside a transaction with `app.current_tenant` set, so Postgres
   itself filters to one foundry. The API connects as a non-superuser role, so
   this cannot be bypassed.

RBAC (`auth/rbac.ts` → `requireRole`) layers function-level permissions on top
(`admin` is a superset).

## Run locally
```bash
# from repo root
docker compose up -d db redis            # migrations auto-apply, incl. app role
cd apps/api && npm install

export DATABASE_URL="postgresql://foundrycast_app:app@127.0.0.1:5432/foundrycast"
export AUTH_MODE=dev AUTH_DEV_SECRET=test-secret
npm run dev

# mint a dev token (AUTH_MODE=dev): tsx scripts/mint-dev-token.ts <userId> [tenantId]
```

## Verified end-to-end (against live Postgres 16)
- auth 401 on missing/invalid token; 403 for non-members and disallowed roles
- the **same user** in two tenants sees only the active tenant's rows (RLS)
- product create gated to `production_manager` / `sales`

## Endpoints so far
| Method | Path | Auth | Notes |
|---|---|---|---|
| GET | `/health` | none | DB liveness |
| GET | `/v1/me` | user | user + all tenant memberships |
| GET | `/v1/products` | member | tenant-scoped list |
| POST | `/v1/products` | production_manager/sales | create, unique code per tenant |
