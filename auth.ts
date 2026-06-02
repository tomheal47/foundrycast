import fp from "fastify-plugin";
import type { FastifyPluginAsync } from "fastify";
import { verifyToken } from "../auth/jwt.js";
import { sql } from "../db/index.js";
import { config } from "../config.js";
import type { FoundryRole } from "../auth/rbac.js";

const plugin: FastifyPluginAsync = async (app) => {
  // ---- authenticate: verify bearer token, resolve the local user ----------
  app.decorate("authenticate", async (req, reply) => {
    const header = req.headers.authorization;
    if (!header?.startsWith("Bearer ")) {
      return reply.code(401).send({ error: "missing_bearer_token" });
    }
    let claims;
    try {
      claims = await verifyToken(header.slice(7));
    } catch {
      return reply.code(401).send({ error: "invalid_token" });
    }

    // dev: `sub` is the user UUID directly. jwks: `sub` is the IdP subject.
    const rows =
      config.AUTH_MODE === "dev"
        ? await sql`select id, email, full_name from users
                    where id = ${claims.sub} and status = 'active'`
        : await sql`select id, email, full_name from app_user_by_external_id(${claims.sub})`;

    const u = rows[0];
    if (!u) return reply.code(401).send({ error: "unknown_user" });

    req.user = { id: u.id, email: u.email, fullName: u.full_name };
    // stash the requested tenant for requireTenant (claim or header)
    (req as any)._tenantHint =
      claims.tenant_id ?? req.headers["x-tenant-id"];
  });

  // ---- requireTenant: resolve active tenant + verify membership -----------
  app.decorate("requireTenant", async (req, reply) => {
    if (!req.user) return reply.code(401).send({ error: "not_authenticated" });
    const tenantId = (req as any)._tenantHint as string | undefined;
    if (!tenantId) {
      return reply.code(400).send({ error: "no_tenant_specified" });
    }
    const rows = await sql<{ role: FoundryRole | null }[]>`
      select app_membership_role(${req.user.id}, ${tenantId}) as role`;
    const role = rows[0]?.role;
    if (!role) return reply.code(403).send({ error: "not_a_member" });
    req.tenant = { id: tenantId, role };
  });
};

export default fp(plugin, { name: "auth" });
