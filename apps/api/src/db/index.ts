import postgres from "postgres";
import { config } from "../config.js";

// Single pool, connecting as the least-privilege app role (FORCE RLS applies).
export const sql = postgres(config.DATABASE_URL, {
  max: 10,
  // BigInt-safe: keep numerics as strings to avoid float drift in costing maths.
  types: {
    numeric: {
      to: 0,
      from: [1700],
      serialize: (v: unknown) => String(v),
      parse: (v: string) => v,
    },
  },
});

export type Sql = typeof sql;

/**
 * Run `fn` inside a transaction with `app.current_tenant` set, so every query
 * is constrained by Row Level Security to a single foundry. This is THE
 * enforcement point for multi-tenancy — all tenant-scoped data access goes
 * through here. `set_config(..., true)` scopes the setting to the transaction.
 */
export async function withTenant<T>(
  tenantId: string,
  fn: (tx: Sql) => Promise<T>
): Promise<T> {
  return sql.begin(async (tx) => {
    await tx`select set_config('app.current_tenant', ${tenantId}, true)`;
    return fn(tx as unknown as Sql);
  }) as Promise<T>;
}
