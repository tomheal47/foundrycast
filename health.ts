import type { FastifyPluginAsync } from "fastify";
import { sql } from "../db/index.js";

export const healthRoutes: FastifyPluginAsync = async (app) => {
  app.get("/health", async () => {
    const rows = await sql<{ now: string }[]>`select now()`;
    return { status: "ok", db_time: rows[0]?.now };
  });
};

export const meRoutes: FastifyPluginAsync = async (app) => {
  // Authenticated, but tenant-agnostic: returns the user and every foundry
  // they can act in (drives the tenant switcher).
  app.get("/v1/me", { preHandler: [app.authenticate] }, async (req) => {
    const memberships = await sql`
      select tenant_id, tenant_name, slug, role
      from app_user_memberships(${req.user!.id})`;
    return { user: req.user, memberships };
  });
};
