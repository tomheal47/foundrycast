-- =============================================================================
-- FoundryCast — Migration 0005: Costing engine
-- =============================================================================
-- Built from the Costing Addendum, which SUPERSEDES the build plan's
-- "Costing & Estimating" assumptions. Two estimate types share a markup ->
-- selling-price -> margin tail but branch on the cost build-up:
--   * manufactured — process times x rates + material + consumables
--   * imported     — landed cost in foreign currency + freight + duty
-- Rates/lookups are tenant-configurable, versioned, with an effective date.
-- NOTE: addendum §5 — only the formula logic, structure and rate *categories*
-- were taken from NovaCast's sheets, never their live commercial prices.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- costing_rates — scalar, dated reference constants.
-- -----------------------------------------------------------------------------
CREATE TABLE costing_rates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  rate_key       text NOT NULL,        -- 'fuel_per_litre','labour_per_min','overhead_per_min',
                                        -- 'linishing_per_min','sand_per_kg','sand_skip_5t',
                                        -- 'ht_per_kg','ht_delivery_per_kg','filter_cost', ...
  value          numeric NOT NULL,
  uom            text,
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  notes          text,
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  -- one active value per key per effective date; engine picks latest <= quote date
  UNIQUE (tenant_id, rate_key, effective_from)
);
SELECT attach_updated_at('costing_rates');
SELECT enable_tenant_rls('costing_rates');
CREATE INDEX idx_rates_key ON costing_rates(tenant_id, rate_key, effective_from DESC);

-- -----------------------------------------------------------------------------
-- costing_lookups — table-valued / stepped reference data.
--   'sleeve_price'        keyed by key_text ('2"','2.5"',...)
--   'material_price'      keyed by key_text ('LM25TF',...)
--   'fx_rate'             keyed by key_text ('USD',...)
--   'labour_by_weight'    stepped by band_min/band_max (kg)
--   'overhead_by_subtotal' stepped by band_min/band_max (£)
--   'crucible'            meta jsonb {life_heats, kg_per_heat}
-- -----------------------------------------------------------------------------
CREATE TABLE costing_lookups (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  lookup         text NOT NULL,
  key_text       text,
  band_min       numeric,
  band_max       numeric,
  value          numeric,
  meta           jsonb DEFAULT '{}',
  effective_from date NOT NULL DEFAULT CURRENT_DATE,
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('costing_lookups');
SELECT enable_tenant_rls('costing_lookups');
CREATE INDEX idx_lookups_key ON costing_lookups(tenant_id, lookup, key_text);
CREATE INDEX idx_lookups_band ON costing_lookups(tenant_id, lookup, band_min, band_max);

-- -----------------------------------------------------------------------------
-- estimates — header for both types.
-- -----------------------------------------------------------------------------
CREATE TABLE estimates (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  estimate_type  text NOT NULL CHECK (estimate_type IN ('manufactured','imported')),
  template_ref   text,                            -- e.g. 'COS014-V2.0'
  product_id     uuid REFERENCES products(id),
  part_no        text,
  issue          text,
  description    text,
  customer_id    uuid REFERENCES parties(id),
  supplier_id    uuid REFERENCES parties(id),      -- imported only (overseas foundry)
  material       text,
  quantity       integer,
  currency       text NOT NULL DEFAULT 'GBP',
  fx_rate        numeric,                          -- imported: foreign -> GBP
  commodity_code text,                             -- imported: duty classification
  duty_pct       numeric,
  cost_total     numeric,                          -- computed cost per casting (£)
  markup_pct     numeric,
  selling_price  numeric,
  gp_margin_pct  numeric,                          -- gross profit margin
  np_margin_pct  numeric,                          -- net profit margin
  status         text NOT NULL DEFAULT 'draft'
                 CHECK (status IN ('draft','quoted','won','lost')),
  params         jsonb NOT NULL DEFAULT '{}',      -- type-specific inputs (see addendum §3)
  created_by     uuid REFERENCES users(id),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  -- supplier_id only meaningful for imported estimates
  CHECK (estimate_type = 'imported' OR supplier_id IS NULL)
);
SELECT attach_updated_at('estimates');
SELECT enable_tenant_rls('estimates');
CREATE INDEX idx_estimates_customer ON estimates(customer_id);
CREATE INDEX idx_estimates_product ON estimates(product_id);

-- -----------------------------------------------------------------------------
-- estimate_cost_lines — the build-up, one row per component (both models).
-- basis/source record how each value was derived so the engine/UI can recompute.
-- -----------------------------------------------------------------------------
CREATE TABLE estimate_cost_lines (
  id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  estimate_id    uuid NOT NULL REFERENCES estimates(id) ON DELETE CASCADE,
  line_name      text NOT NULL,
  cost_amount    numeric,
  markup_pct     numeric,                          -- imported model marks up each process line
  selling_amount numeric,
  basis          text CHECK (basis IN ('per_part','per_kg','per_mould','fixed')),
  source         text CHECK (source IN ('computed','entered','lookup')),
  sort_order     integer NOT NULL DEFAULT 0,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('estimate_cost_lines');
SELECT enable_tenant_rls('estimate_cost_lines');
CREATE INDEX idx_cost_lines_estimate ON estimate_cost_lines(estimate_id);
