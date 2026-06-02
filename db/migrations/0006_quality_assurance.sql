-- =============================================================================
-- FoundryCast — Migration 0006: Quality Assurance
-- =============================================================================
-- Reflects the Costing Addendum §4 CofA decision:
--   * CofA certificate module REMOVED. NovaCast issues CofC only.
--     The certificates table keeps cert_type, but in practice only 'CofC' is
--     used; the CofA results-table layout is gone.
--   * Chemical / physical results are RETAINED as optional batch data
--     (batch_test_results) — attached evidence surfaced in traceability,
--     NEVER auto-issued as a certificate.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- certificates — Certificate of Conformance generated on despatch.
-- -----------------------------------------------------------------------------
CREATE TABLE certificates (
  id          uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id    uuid NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  cert_type   text NOT NULL DEFAULT 'CofC' CHECK (cert_type IN ('CofC')),
  cert_no     text,
  status      text NOT NULL DEFAULT 'draft'
              CHECK (status IN ('draft','approved','released')),
  document_id uuid,                       -- rendered PDF object key in S3/R2
  signed_by   uuid REFERENCES users(id),
  signed_at   timestamptz,
  created_by  uuid REFERENCES users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  UNIQUE (tenant_id, cert_no)
);
SELECT attach_updated_at('certificates');
SELECT enable_tenant_rls('certificates');
CREATE INDEX idx_cert_batch ON certificates(batch_id);

-- -----------------------------------------------------------------------------
-- batch_test_results — optional chem/physical results attached to a batch.
-- These are evidence, not generated certs.
-- -----------------------------------------------------------------------------
CREATE TABLE batch_test_results (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  batch_id      uuid NOT NULL REFERENCES batches(id) ON DELETE CASCADE,
  result_type   text NOT NULL CHECK (result_type IN ('chemical','mechanical')),
  results       jsonb NOT NULL DEFAULT '{}',
  source        text CHECK (source IN ('lab','supplier_cert','in_house')),
  attachment_id uuid,                     -- scanned/PDF source object key
  recorded_at   timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES users(id),
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('batch_test_results');
SELECT enable_tenant_rls('batch_test_results');
CREATE INDEX idx_test_results_batch ON batch_test_results(batch_id);

-- -----------------------------------------------------------------------------
-- calibration_records — metrology/QA equipment calibration history & due dates.
-- -----------------------------------------------------------------------------
CREATE TABLE calibration_records (
  id                uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  equipment_id      uuid NOT NULL REFERENCES equipment(id) ON DELETE CASCADE,
  calibration_date  date NOT NULL,
  next_due          date,
  result            text CHECK (result IN ('pass','fail','adjusted')),
  performed_by      text,                 -- internal user or external cal house
  certificate_ref   text,
  created_by        uuid REFERENCES users(id),
  created_at        timestamptz NOT NULL DEFAULT now(),
  updated_at        timestamptz NOT NULL DEFAULT now()
);
SELECT attach_updated_at('calibration_records');
SELECT enable_tenant_rls('calibration_records');
CREATE INDEX idx_cal_equipment ON calibration_records(equipment_id);
CREATE INDEX idx_cal_due ON calibration_records(tenant_id, next_due);
