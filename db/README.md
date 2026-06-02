# FoundryCast — Database

PostgreSQL 16. Migrations are plain SQL, applied in filename order.

## Migration order
| File | Contents |
|------|----------|
| `0001_extensions_and_tenancy.sql` | Extensions, `set_updated_at`/`attach_updated_at`/`enable_tenant_rls` helpers, `tenants`, `users`, `foundry_role`, `tenant_memberships` |
| `0002_master_data.sql` | categories, alloy_grades, materials, parties, work_centres, products, process_route_operations, equipment, furnaces, ladles, tooling |
| `0003_foundry_operations.sql` | heats + charge lines, batches, castings, heat_treatment_logs, weld_logs, shell_tracking, scrap_records, wip_locations |
| `0004_sales_purchasing_inventory.sql` | sales_orders/lines, production_orders, time_bookings, purchase_orders/lines, locations, inventory |
| `0005_costing_engine.sql` | costing_rates, costing_lookups, estimates, estimate_cost_lines |
| `0006_quality_assurance.sql` | certificates (CofC only), batch_test_results, calibration_records |

## The multi-tenancy contract (READ THIS)
Tenant isolation is enforced **in the database** via Row Level Security, not in
app code. Every business table has a `tenant_isolation` policy keyed on the
session GUC `app.current_tenant`.

The API **must** set this inside each request transaction, against a
**non-superuser** role (superusers and table owners bypass RLS unless `FORCE`
is set — it is, here, so even the owner is constrained):

```sql
BEGIN;
SET LOCAL app.current_tenant = '<tenant-uuid-from-jwt>';
-- ... queries run here only see/write this tenant's rows ...
COMMIT;
```

If `app.current_tenant` is unset, queries return **zero rows** (fail-closed).
`tenants` and `users` are intentionally global (not tenant-scoped); access to
them is governed by application RBAC.

## Run locally
```bash
docker compose up -d db        # migrations auto-apply on first boot
# seed dev rates (optional, non-production):
psql "$DATABASE_URL" -f db/seed/0001_dev_seed.sql
```
