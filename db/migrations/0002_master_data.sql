-- =============================================================================
-- FoundryCast — Migration 0002: Master / reference data
-- =============================================================================
-- Slow-changing reference entities that transactional records point at.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Product taxonomy
-- -----------------------------------------------------------------------------
CREATE TABLE categories (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text NOT NULL,
  parent_id   uuid REFERENCES categories(id) ON DELETE SET NULL,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);
SELECT attach_updated_at('categories');
SELECT enable_tenant_rls('categories');

-- -----------------------------------------------------------------------------
-- Alloy grades — the metallurgical spec a casting is made to.
-- target_composition is element -> {min,max,aim} percentages.
-- -----------------------------------------------------------------------------
CREATE TABLE alloy_grades (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name               text NOT NULL,               -- e.g. 'LM25', '316 stainless'
  standard_ref       text,                         -- e.g. 'BS EN 1563', 'BS EN 1706'
  target_composition jsonb NOT NULL DEFAULT '{}',  -- {"Si":{"min":6.5,"max":7.5,"aim":7.0}, ...}
  melt_temp_min_c    numeric,
  melt_temp_max_c    numeric,
  pour_temp_min_c    numeric,
  pour_temp_max_c    numeric,
  notes              text,
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);
SELECT attach_updated_at('alloy_grades');
SELECT enable_tenant_rls('alloy_grades');

-- -----------------------------------------------------------------------------
-- Materials — anything consumed: metals/virgin/scrap, sand, coatings, sleeves,
-- filters, crucibles. Drives both inventory/MRP and the costing charge mix.
-- -----------------------------------------------------------------------------
CREATE TABLE materials (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code          text NOT NULL,
  description   text NOT NULL,
  material_type text NOT NULL
                CHECK (material_type IN
                  ('virgin_metal','scrap_metal','alloy_addition','sand',
                   'coating','sleeve','filter','crucible','consumable','other')),
  alloy_grade_id uuid REFERENCES alloy_grades(id),  -- for metal returns/virgin tied to a grade
  uom           text NOT NULL DEFAULT 'kg',
  composition   jsonb DEFAULT '{}',                  -- element % for FRO charge-mix solving
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('materials');
SELECT enable_tenant_rls('materials');

-- -----------------------------------------------------------------------------
-- Trading parties. customers & suppliers share a table (a foundry's customer
-- can also be a supplier); BRM treats suppliers as first-class entities.
-- -----------------------------------------------------------------------------
CREATE TABLE parties (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name          text NOT NULL,
  account_ref   text,
  is_customer   boolean NOT NULL DEFAULT false,
  is_supplier   boolean NOT NULL DEFAULT false,
  payment_terms text,
  currency      text NOT NULL DEFAULT 'GBP',
  contacts      jsonb NOT NULL DEFAULT '[]',   -- [{name,email,phone,role}]
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, account_ref)
);
SELECT attach_updated_at('parties');
SELECT enable_tenant_rls('parties');

-- -----------------------------------------------------------------------------
-- Work centres — moulding, coremaking, melting, fettling, knockout, HT, etc.
-- Route operations and SFDC time bookings post against these.
-- -----------------------------------------------------------------------------
CREATE TABLE work_centres (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code           text NOT NULL,
  name           text NOT NULL,
  daily_capacity numeric,            -- units of capacity per day (for back-scheduler)
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('work_centres');
SELECT enable_tenant_rls('work_centres');

-- -----------------------------------------------------------------------------
-- Products — the casting being made. Supports batch and serialised (UID) parts.
-- -----------------------------------------------------------------------------
CREATE TABLE products (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code           text NOT NULL,
  description    text NOT NULL,
  alloy_grade_id uuid REFERENCES alloy_grades(id),
  category_id    uuid REFERENCES categories(id),
  status         text NOT NULL DEFAULT 'active'
                 CHECK (status IN ('active','obsolete','development','on_hold')),
  serialised     boolean NOT NULL DEFAULT false,   -- true => one-piece UID traceability
  net_weight_kg  numeric,                           -- finished casting weight
  drawing_ref    text,
  images         jsonb NOT NULL DEFAULT '[]',       -- S3/R2 object keys
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('products');
SELECT enable_tenant_rls('products');

-- -----------------------------------------------------------------------------
-- Process routes — ordered operations a product passes through. Each operation
-- can be in-house (work_centre) or subcontracted (supplier party).
-- -----------------------------------------------------------------------------
CREATE TABLE process_route_operations (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  product_id         uuid NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  sequence           integer NOT NULL,
  operation_name     text NOT NULL,
  work_centre_id     uuid REFERENCES work_centres(id),
  subcon_supplier_id uuid REFERENCES parties(id),    -- set => out-of-house operation
  lead_days          numeric NOT NULL DEFAULT 0,     -- back-scheduler input
  std_minutes        numeric,                         -- standard time, feeds costing labour/overhead
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (product_id, sequence),
  CHECK ( (work_centre_id IS NOT NULL) OR (subcon_supplier_id IS NOT NULL) )
);
SELECT attach_updated_at('process_route_operations');
SELECT enable_tenant_rls('process_route_operations');
CREATE INDEX idx_route_ops_product ON process_route_operations(product_id);

-- -----------------------------------------------------------------------------
-- Equipment register — furnaces, ovens, moulding machines, metrology gear.
-- Specialised furnace/oven attributes hang off the operations tables; this is
-- the maintenance/calibration anchor.
-- -----------------------------------------------------------------------------
CREATE TABLE equipment (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  code                text NOT NULL,
  name                text NOT NULL,
  equipment_type      text NOT NULL
                      CHECK (equipment_type IN
                        ('furnace','oven','moulding_machine','metrology','crane','other')),
  status              text NOT NULL DEFAULT 'available'
                      CHECK (status IN ('available','in_use','maintenance','down','retired')),
  last_maintenance_at date,
  requires_calibration boolean NOT NULL DEFAULT false,
  created_by          uuid REFERENCES users(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('equipment');
SELECT enable_tenant_rls('equipment');

-- Furnaces — induction/cupola/arc. Extends equipment with melt-specific attrs.
CREATE TABLE furnaces (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  equipment_id  uuid REFERENCES equipment(id),
  name          text NOT NULL,
  furnace_type  text NOT NULL CHECK (furnace_type IN ('induction','cupola','arc','crucible','other')),
  capacity_kg   numeric,
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);
SELECT attach_updated_at('furnaces');
SELECT enable_tenant_rls('furnaces');

-- Ladles — transfer/pouring vessels logged against heats.
CREATE TABLE ladles (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text NOT NULL,
  capacity_kg numeric,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, name)
);
SELECT attach_updated_at('ladles');
SELECT enable_tenant_rls('ladles');

-- -----------------------------------------------------------------------------
-- Tooling — patterns, core boxes, cope/drag, frames, boxes. Lifecycle tracked.
-- -----------------------------------------------------------------------------
CREATE TABLE tooling (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  product_id         uuid REFERENCES products(id),
  code               text NOT NULL,
  tooling_type       text NOT NULL
                     CHECK (tooling_type IN ('cope','drag','core_box','frame','box','pattern','other')),
  status             text NOT NULL DEFAULT 'available'
                     CHECK (status IN ('available','in_use','repair','scrapped','at_customer')),
  condition_rating   integer CHECK (condition_rating BETWEEN 1 AND 5),
  last_inspection_at date,
  location           text,
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, code)
);
SELECT attach_updated_at('tooling');
SELECT enable_tenant_rls('tooling');
CREATE INDEX idx_tooling_product ON tooling(product_id);
