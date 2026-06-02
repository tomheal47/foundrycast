import type { FastifyPluginAsync } from "fastify";
import { z } from "zod";
import { withTenant } from "../db/index.js";
import { requireRole } from "../auth/rbac.js";

const CreateProduct = z.object({
  code: z.string().min(1),
  description: z.string().min(1),
  alloyGradeId: z.string().uuid().optional(),
  categoryId: z.string().uuid().optional(),
  serialised: z.boolean().default(false),
  netWeightKg: z.number().positive().optional(),
  drawingRef: z.string().optional(),
});

export const productRoutes: FastifyPluginAsync = async (app) => {
  const auth = { preHandler: [app.authenticate, app.requireTenant] };

  // List — any member of the tenant may read.
  app.get("/v1/products", auth, async (req) => {
    const products = await withTenant(req.tenant!.id, (tx) =>
      tx`select id, code, description, alloy_grade_id, category_id,
                status, serialised, net_weight_kg, drawing_ref
         from products order by code`
    );
    return { products };
  });

  // Create — restricted to roles that own master data.
  app.post(
    "/v1/products",
    { preHandler: [...auth.preHandler, requireRole("production_manager", "sales")] },
    async (req, reply) => {
      const parsed = CreateProduct.safeParse(req.body);
      if (!parsed.success) {
        return reply.code(400).send({ error: "validation", issues: parsed.error.issues });
      }
      const p = parsed.data;
      try {
        const rows = await withTenant(req.tenant!.id, (tx) =>
          tx`insert into products
               (tenant_id, code, description, alloy_grade_id, category_id,
                serialised, net_weight_kg, drawing_ref, created_by)
             values
               (${req.tenant!.id}, ${p.code}, ${p.description},
                ${p.alloyGradeId ?? null}, ${p.categoryId ?? null},
                ${p.serialised}, ${p.netWeightKg ?? null}, ${p.drawingRef ?? null},
                ${req.user!.id})
             returning id, code, description, status, serialised`
        );
        return reply.code(201).send({ product: rows[0] });
      } catch (err: any) {
        if (err?.code === "23505") {
          return reply.code(409).send({ error: "duplicate_code", code: p.code });
        }
        throw err;
      }
    }
  );
};
