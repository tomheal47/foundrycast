-- =============================================================================
-- FoundryCast — Migration 0004: Sales, production, purchasing, inventory
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Sales orders + lines (line-level due dates feed the back-scheduler).
-- -----------------------------------------------------------------------------
CREATE TABLE sales_orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  order_no            text NOT NULL,
  customer_id         uuid NOT NULL REFERENCES parties(id),
  status              text NOT NULL DEFAULT 'open'
                      CHECK (status IN ('draft','open','in_production','despatched','complete','cancelled')),
  delivery_address    jsonb,
  created_by          uuid REFERENCES users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, order_no)
);
SELECT attach_updated_at('sales_orders');
SELECT enable_tenant_rls('sales_orders');
CREATE INDEX idx_so_customer ON sales_orders(customer_id);

CREATE TABLE sales_order_lines (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sales_order_id uuid NOT NULL REFERENCES sales_orders(id) ON DELETE CASCADE,
  line_no        integer NOT NULL,
  product_id     uuid NOT NULL REFERENCES products(id),
  quantity       integer NOT NULL,
  due_date       date,
  unit_price     numeric,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (sales_order_id, line_no)
);
SELECT attach_updated_at('sales_order_lines');
SELECT enable_tenant_rls('sales_order_lines');
CREATE INDEX idx_sol_order ON sales_order_lines(sales_order_id);

-- -----------------------------------------------------------------------------
-- Production orders — what the shop floor actually makes; back-scheduled.
-- -----------------------------------------------------------------------------
CREATE TABLE production_orders (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  order_no            text NOT NULL,
  sales_order_line_id uuid REFERENCES sales_order_lines(id),
  product_id          uuid NOT NULL REFERENCES products(id),
  quantity            integer NOT NULL,
  scheduled_start     timestamptz,
  scheduled_complete  timestamptz,
  status              text NOT NULL DEFAULT 'planned'
                      CHECK (status IN ('planned','released','in_progress','complete','closed','cancelled')),
  created_by          uuid REFERENCES users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, order_no)
);
SELECT attach_updated_at('production_orders');
SELECT enable_tenant_rls('production_orders');
CREATE INDEX idx_po_product ON production_orders(product_id);

-- Wire the deferred batches -> production_orders FK now that the table exists.
ALTER TABLE batches
  ADD CONSTRAINT fk_batches_production_order
  FOREIGN KEY (production_order_id) REFERENCES production_orders(id);

-- -----------------------------------------------------------------------------
-- SFDC time bookings — labour/process time recorded against an operation.
-- Feeds costing actuals vs estimate and operator scrap attribution.
-- -----------------------------------------------------------------------------
CREATE TABLE time_bookings (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  production_order_id uuid REFERENCES production_orders(id) ON DELETE CASCADE,
  batch_id            uuid REFERENCES batches(id),
  operation_id        uuid REFERENCES process_route_operations(id),
  work_centre_id      uuid REFERENCES work_centres(id),
  operator_id         uuid REFERENCES users(id),
  minutes             numeric NOT NULL,
  booked_at           timestamptz NOT NULL DEFAULT now(),
  -- offline shop-floor sync support
  client_uuid         uuid,                          -- idempotency key from the tablet
  synced_at           timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, client_uuid)
);
SELECT attach_updated_at('time_bookings');
SELECT enable_tenant_rls('time_bookings');
CREATE INDEX idx_time_po ON time_bookings(production_order_id);

-- -----------------------------------------------------------------------------
-- Purchase orders + lines.
-- -----------------------------------------------------------------------------
CREATE TABLE purchase_orders (
  id              uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  order_no        text NOT NULL,
  supplier_id     uuid NOT NULL REFERENCES parties(id),
  status          text NOT NULL DEFAULT 'draft'
                  CHECK (status IN ('draft','sent','acknowledged','part_received','received','closed','cancelled')),
  created_by      uuid REFERENCES users(id),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, order_no)
);
SELECT attach_updated_at('purchase_orders');
SELECT enable_tenant_rls('purchase_orders');
CREATE INDEX idx_purch_supplier ON purchase_orders(supplier_id);

CREATE TABLE purchase_order_lines (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  purchase_order_id uuid NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  line_no           integer NOT NULL,
  material_id       uuid NOT NULL REFERENCES materials(id),
  quantity          numeric NOT NULL,
  unit_price        numeric,
  due_date          date,
  qty_received      numeric NOT NULL DEFAULT 0,
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now(),
  UNIQUE (purchase_order_id, line_no)
);
SELECT attach_updated_at('purchase_order_lines');
SELECT enable_tenant_rls('purchase_order_lines');
CREATE INDEX idx_pol_order ON purchase_order_lines(purchase_order_id);

-- -----------------------------------------------------------------------------
-- Inventory — stock by material and location.
-- -----------------------------------------------------------------------------
CREATE TABLE locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code        text NOT NULL,
  name        text NOT NULL,
  kind        text NOT NULL DEFAULT 'warehouse'
              CHECK (kind IN ('warehouse','floor','transit','port','customer')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('locations');
SELECT enable_tenant_rls('locations');

CREATE TABLE inventory (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  material_id    uuid NOT NULL REFERENCES materials(id),
  location_id    uuid NOT NULL REFERENCES locations(id),
  qty_on_hand    numeric NOT NULL DEFAULT 0,
  qty_allocated  numeric NOT NULL DEFAULT 0,
  qty_available  numeric GENERATED ALWAYS AS (qty_on_hand - qty_allocated) STORED,
  last_count_date date,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, material_id, location_id)
);
SELECT attach_updated_at('inventory');
SELECT enable_tenant_rls('inventory');
CREATE INDEX idx_inventory_material ON inventory(material_id);
