-- Basisstructuur voor de NDW-medallion-architectuur.
-- Dit script is herhaalbaar en kan veilig opnieuw worden uitgevoerd.

CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE SCHEMA IF NOT EXISTS bronze;
CREATE SCHEMA IF NOT EXISTS silver;
CREATE SCHEMA IF NOT EXISTS gold;

CREATE TABLE IF NOT EXISTS bronze.ingestion_batches (
    batch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    aanvraag_id UUID,
    exportnaam TEXT NOT NULL,
    bron_object_key TEXT NOT NULL UNIQUE,
    bron_bestandsnaam TEXT NOT NULL,
    bron_checksum_sha256 CHAR(64),
    bron_periode_van TIMESTAMPTZ,
    bron_periode_tot TIMESTAMPTZ,
    aggregatieperiode TEXT NOT NULL,
    aggregatievariant TEXT NOT NULL,
    meetcompleetheid_meegenomen BOOLEAN,
    ingestietijdstip TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    aantal_records_gelezen INTEGER,
    aantal_records_geladen INTEGER,
    status TEXT NOT NULL DEFAULT 'registered'
        CHECK (status IN ('registered', 'loading', 'loaded', 'failed')),
    foutmelding TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS bronze.ndw_intensiteit_snelheid_raw (
    batch_id UUID NOT NULL REFERENCES bronze.ingestion_batches(batch_id),
    source_row_number INTEGER NOT NULL,
    source_payload JSONB NOT NULL,
    ingested_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (batch_id, source_row_number)
);

COMMENT ON TABLE bronze.ingestion_batches IS
    'Registratie en lineage van elke ingelezen NDW-exportbatch.';
COMMENT ON COLUMN bronze.ingestion_batches.bron_object_key IS
    'Volledige object key in MinIO, bijvoorbeeld bronze/intensiteit-snelheid/2026/09/export.csv.';
COMMENT ON TABLE bronze.ndw_intensiteit_snelheid_raw IS
    'Brongetrouwe NDW-CSV-rijen als JSON; inhoudelijke transformaties beginnen pas in Silver.';
