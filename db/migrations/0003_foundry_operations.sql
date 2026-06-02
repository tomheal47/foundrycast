-- =============================================================================
-- FoundryCast — Migration 0003: Foundry shop-floor operations
-- =============================================================================
-- The transactional heart that makes this foundry-specific:
-- heats -> batches -> (serialised) castings, plus HT / weld / shell / scrap.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- Heats / melts — a single furnace melt with its charge mix and pour window.
-- charge_mix held as line rows (heat_charge_lines) for proper FK + reporting.
-- -----------------------------------------------------------------------------
CREATE TABLE heats (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  heat_no        text NOT NULL,                 -- human-facing heat number
  furnace_id     uuid REFERENCES furnaces(id),
  ladle_id       uuid REFERENCES ladles(id),
  alloy_grade_id uuid REFERENCES alloy_grades(id),
  tap_temp_c     numeric,
  pour_start     timestamptz,
  pour_end       timestamptz,
  power_kwh      numeric,                        -- furnace power consumption
  status         text NOT NULL DEFAULT 'open'
                 CHECK (status IN ('open','melting','poured','closed')),
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, heat_no)
);
SELECT attach_updated_at('heats');
SELECT enable_tenant_rls('heats');
CREATE INDEX idx_heats_furnace ON heats(furnace_id);
CREATE INDEX idx_heats_alloy ON heats(alloy_grade_id);

CREATE TABLE heat_charge_lines (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  heat_id     uuid NOT NULL REFERENCES heats(id) ON DELETE CASCADE,
  material_id uuid NOT NULL REFERENCES materials(id),
  weight_kg   numeric NOT NULL,
  unit_cost   numeric,                           -- captured at charge time for traceable cost
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('heat_charge_lines');
SELECT enable_tenant_rls('heat_charge_lines');
CREATE INDEX idx_charge_heat ON heat_charge_lines(heat_id);

-- -----------------------------------------------------------------------------
-- Batches — a production batch of a product poured (wholly/partly) from a heat.
-- This is the "casting batch" the build plan & addendum reference as batches(id).
-- -----------------------------------------------------------------------------
CREATE TABLE batches (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  batch_no           text NOT NULL,
  product_id         uuid NOT NULL REFERENCES products(id),
  heat_id            uuid REFERENCES heats(id),
  production_order_id uuid,                       -- FK added in 0004 (deferred to avoid cycle)
  quantity_poured    integer NOT NULL DEFAULT 0,
  quantity_good      integer NOT NULL DEFAULT 0,
  quantity_scrapped  integer NOT NULL DEFAULT 0,
  status             text NOT NULL DEFAULT 'open'
                     CHECK (status IN ('open','in_progress','complete','closed')),
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, batch_no)
);
SELECT attach_updated_at('batches');
SELECT enable_tenant_rls('batches');
CREATE INDEX idx_batches_product ON batches(product_id);
CREATE INDEX idx_batches_heat ON batches(heat_id);

-- -----------------------------------------------------------------------------
-- Castings — individual serialised pieces (one-piece UID traceability).
-- Non-serialised products track at batch level and may have zero casting rows.
-- weld_logs and shell_tracking attach to a specific casting.
-- -----------------------------------------------------------------------------
CREATE TABLE castings (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id    uuid NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  product_id  uuid NOT NULL REFERENCES products(id),
  uid         text NOT NULL,                      -- unique identifier stamped on the part
  status      text NOT NULL DEFAULT 'in_process'
              CHECK (status IN ('in_process','good','scrapped','despatched')),
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, uid)                          -- supports UID lookup & swap auditing
);
SELECT attach_updated_at('castings');
SELECT enable_tenant_rls('castings');
CREATE INDEX idx_castings_batch ON castings(batch_id);

-- -----------------------------------------------------------------------------
-- Heat treatment logs — oven cycles against a batch.
-- -----------------------------------------------------------------------------
CREATE TABLE heat_treatment_logs (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  casting_batch_id uuid NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  oven_id          uuid REFERENCES equipment(id),
  treatment_type   text,                            -- e.g. 'T6', 'solution + age', 'stress relieve'
  cycle_start      timestamptz,
  cycle_end        timestamptz,
  soak_temp_c      numeric,
  atmosphere       text,
  created_by       uuid REFERENCES users(id),
  created_at       timestamptz NOT NULL DEFAULT now(),
  updated_at       timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('heat_treatment_logs');
SELECT enable_tenant_rls('heat_treatment_logs');
CREATE INDEX idx_ht_batch ON heat_treatment_logs(casting_batch_id);

-- -----------------------------------------------------------------------------
-- Weld logs — repair welds on structural castings, per individual casting.
-- -----------------------------------------------------------------------------
CREATE TABLE weld_logs (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  casting_id         uuid NOT NULL REFERENCES castings(id) ON DELETE CASCADE,
  welder_id          uuid REFERENCES users(id),    -- welder qualification checked in app layer
  weld_spec          text,
  filler_material_id uuid REFERENCES materials(id),
  pre_heat_temp_c    numeric,
  pwht               boolean NOT NULL DEFAULT false, -- post-weld heat treatment performed
  welded_at          timestamptz,
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('weld_logs');
SELECT enable_tenant_rls('weld_logs');
CREATE INDEX idx_weld_casting ON weld_logs(casting_id);

-- -----------------------------------------------------------------------------
-- Shell tracking — investment casting wax/ceramic build stages, per casting.
-- -----------------------------------------------------------------------------
CREATE TABLE shell_tracking (
  id           uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  casting_id   uuid NOT NULL REFERENCES castings(id) ON DELETE CASCADE,
  stage        text NOT NULL
               CHECK (stage IN ('wax','prime','stucco','dewax','sinter')),
  completed_at timestamptz,
  operator_id  uuid REFERENCES users(id),
  created_at   timestamptz NOT NULL DEFAULT now(),
  updated_at   timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('shell_tracking');
SELECT enable_tenant_rls('shell_tracking');
CREATE INDEX idx_shell_casting ON shell_tracking(casting_id);

-- -----------------------------------------------------------------------------
-- Scrap records — scrap by operation/cause/operator for Pareto + AI root-cause.
-- -----------------------------------------------------------------------------
CREATE TABLE scrap_records (
  id                 uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  casting_batch_id   uuid NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  operation_id       uuid REFERENCES process_route_operations(id),
  operator_id        uuid REFERENCES users(id),
  scrap_code         text NOT NULL,               -- e.g. 'POROSITY','MISRUN','COLD_SHUT'
  quantity           integer NOT NULL,
  root_cause         text,
  corrective_action  text,
  recorded_at        timestamptz NOT NULL DEFAULT now(),
  created_by         uuid REFERENCES users(id),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('scrap_records');
SELECT enable_tenant_rls('scrap_records');
CREATE INDEX idx_scrap_batch ON scrap_records(casting_batch_id);
CREATE INDEX idx_scrap_code ON scrap_records(tenant_id, scrap_code);

-- -----------------------------------------------------------------------------
-- WIP location (Stack & Rack) — where a batch/casting physically sits.
-- -----------------------------------------------------------------------------
CREATE TABLE wip_locations (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id    uuid REFERENCES batches(id) ON DELETE CASCADE,
  casting_id  uuid REFERENCES castings(id) ON DELETE CASCADE,
  location    text NOT NULL,                       -- rack/tray identifier
  moved_at    timestamptz NOT NULL DEFAULT now(),
  moved_by    uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CHECK ( (batch_id IS NOT NULL) OR (casting_id IS NOT NULL) )
);
SELECT attach_updated_at('wip_locations');
SELECT enable_tenant_rls('wip_locations');
