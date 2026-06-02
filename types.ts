import type { FoundryRole } from "./auth/rbac.js";

declare module "fastify" {
  interface FastifyRequest {
    user?: { id: string; email: string; fullName: string };
    tenant?: { id: string; role: FoundryRole };
  }
  interface FastifyInstance {
    authenticate: import("fastify").preHandlerHookHandler;
    requireTenant: import("fastify").preHandlerHookHandler;
  }
}

export {};
