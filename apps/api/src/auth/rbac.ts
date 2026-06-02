import type { FastifyReply, FastifyRequest } from "fastify";

export const ROLES = [
  "admin",
  "production_manager",
  "supervisor",
  "operator",
  "qa",
  "sales",
  "finance",
] as const;

export type FoundryRole = (typeof ROLES)[number];

/**
 * Route guard: require the caller's role in the active tenant to be one of
 * `allowed`. `admin` always passes. Use as a preHandler.
 */
export function requireRole(...allowed: FoundryRole[]) {
  return async (req: FastifyRequest, reply: FastifyReply) => {
    const role = req.tenant?.role;
    if (!role) return reply.code(401).send({ error: "no_tenant_context" });
    if (role === "admin" || allowed.includes(role)) return;
    return reply
      .code(403)
      .send({ error: "forbidden", required: allowed, role });
  };
}
