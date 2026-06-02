-- =============================================================================
-- FoundryCast — Dev seed (NON-PRODUCTION)
-- =============================================================================
-- Seeds a demo tenant and the costing rate CATEGORIES from the Costing Addendum.
-- Per addendum §5, these are rate *categories* with illustrative default values
-- for development/testing only — NOT any real customer's commercial prices.
-- Run as superuser (RLS is bypassed for the seed inserts).
-- =============================================================================

DO $$
DECLARE
  t uuid := '00000000-0000-0000-0000-0000000000aa';  -- demo tenant
BEGIN
  INSERT INTO tenants (id,name,slug)
  VALUES (t,'Demo Foundry','demo')
  ON CONFLICT (slug) DO NOTHING;

  -- scalar rates ---------------------------------------------------------------
  INSERT INTO costing_rates (tenant_id, rate_key, value, uom, notes) VALUES
    (t,'labour_per_min',     0.4778,   'GBP/min', 'shop labour'),
    (t,'overhead_per_min',   0.35749,  'GBP/min', 'works overhead'),
    (t,'linishing_per_min',  0.009016, 'GBP/min', 'linishing/fettling'),
    (t,'fuel_per_litre',     0.59,     'GBP/l',   'furnace fuel'),
    (t,'sand_per_kg',        0.117,    'GBP/kg',  'moulding sand'),
    (t,'sand_skip_5t',       280.00,   'GBP/skip','5t sand skip'),
    (t,'ht_per_kg',          1.20,     'GBP/kg',  'heat treatment'),
    (t,'filter_cost',        0.40,     'GBP/each','ceramic filter')
  ON CONFLICT (tenant_id, rate_key, effective_from) DO NOTHING;

  -- table-valued lookups -------------------------------------------------------
  INSERT INTO costing_lookups (tenant_id, lookup, key_text, value, meta) VALUES
    (t,'sleeve_price','2"',   0.59, '{}'),
    (t,'sleeve_price','2.5"', 0.72, '{}'),
    (t,'sleeve_price','3"',   0.88, '{}'),
    (t,'sleeve_price','4"',   2.00, '{}'),
    (t,'material_price','LM25TF', 2.60, '{}'),
    (t,'material_price','LM25M',  3.00, '{}'),
    (t,'material_price','LM6M',   3.00, '{}'),
    (t,'fx_rate','USD', 1.27, '{}'),
    (t,'crucible','TPX412', 867.42, '{"life_heats":100,"kg_per_heat":250}'),
    (t,'crucible','CX200',  206.77, '{"life_heats":50,"kg_per_heat":250}');

  -- stepped lookups (illustrative bands) ---------------------------------------
  INSERT INTO costing_lookups (tenant_id, lookup, band_min, band_max, value) VALUES
    (t,'labour_by_weight',   0,    1,   2.50),
    (t,'labour_by_weight',   1,    5,   4.00),
    (t,'labour_by_weight',   5,    20,  7.50),
    (t,'overhead_by_subtotal', 0,   50,  0.15),  -- value = overhead fraction of subtotal band
    (t,'overhead_by_subtotal', 50,  200, 0.12),
    (t,'overhead_by_subtotal', 200, NULL,0.10);
END $$;
