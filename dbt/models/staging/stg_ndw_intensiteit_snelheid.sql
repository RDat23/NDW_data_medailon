{{ config(materialized='view') }}

with raw_values as (
    select
        raw.batch_id,
        raw.source_row_number,
        raw.ingested_at,
        batch.bron_object_key,
        batch.bron_bestandsnaam,
        batch.bron_checksum_sha256,
        batch.ingestietijdstip as batch_ingestietijdstip,
        nullif(trim(raw.source_payload ->> 'id_meetlocatie'), '') as id_meetlocatie,
        nullif(trim(raw.source_payload ->> 'ndw_index'), '') as ndw_index,
        nullif(trim(raw.source_payload ->> 'start_meetperiode'), '') as start_meetperiode_text,
        nullif(trim(raw.source_payload ->> 'eind_meetperiode'), '') as eind_meetperiode_text,
        nullif(trim(raw.source_payload ->> 'waarnemingen_intensiteit'), '') as waarnemingen_intensiteit_text,
        nullif(trim(raw.source_payload ->> 'waarnemingen_snelheid'), '') as waarnemingen_snelheid_text,
        nullif(trim(raw.source_payload ->> 'gebruikte_minuten_intensiteit'), '') as gebruikte_minuten_intensiteit_text,
        nullif(trim(raw.source_payload ->> 'gebruikte_minuten_snelheid'), '') as gebruikte_minuten_snelheid_text,
        nullif(trim(raw.source_payload ->> 'data_error_snelheid'), '') as data_error_snelheid_text,
        nullif(trim(raw.source_payload ->> 'data_error_intensiteit'), '') as data_error_intensiteit_text,
        nullif(trim(raw.source_payload ->> 'gem_intensiteit'), '') as gem_intensiteit_text,
        nullif(trim(raw.source_payload ->> 'gem_snelheid'), '') as gem_snelheid_text,
        nullif(trim(raw.source_payload ->> 'gewogen_gem_snelheid'), '') as gewogen_gem_snelheid_text,
        nullif(trim(raw.source_payload ->> 'rijstrook_rijbaan'), '') as rijstrook_rijbaan,
        nullif(trim(raw.source_payload ->> 'voertuigcategorie'), '') as voertuigcategorie,
        nullif(trim(raw.source_payload ->> 'technical_exclusion'), '') as technical_exclusion,
        nullif(trim(raw.source_payload ->> 'traffic_flow_deviation_exclusions'), '')
            as traffic_flow_deviation_exclusions
    from {{ source('bronze', 'ndw_intensiteit_snelheid_raw') }} as raw
    inner join {{ source('bronze', 'ingestion_batches') }} as batch
        on raw.batch_id = batch.batch_id
    where batch.status = 'loaded'
),

typed as (
    select
        md5(batch_id::text || ':' || source_row_number::text) as bronze_record_id,
        batch_id,
        source_row_number,
        bron_object_key,
        bron_bestandsnaam,
        bron_checksum_sha256,
        batch_ingestietijdstip,
        ingested_at,
        id_meetlocatie,
        ndw_index,
        start_meetperiode_text::timestamp as start_meetperiode,
        eind_meetperiode_text::timestamp as eind_meetperiode,
        waarnemingen_intensiteit_text::numeric as waarnemingen_intensiteit,
        waarnemingen_snelheid_text::numeric as waarnemingen_snelheid,
        gebruikte_minuten_intensiteit_text::numeric as gebruikte_minuten_intensiteit,
        gebruikte_minuten_snelheid_text::numeric as gebruikte_minuten_snelheid,
        data_error_snelheid_text::smallint as data_error_snelheid,
        data_error_intensiteit_text::smallint as data_error_intensiteit,
        gem_intensiteit_text::numeric as gem_intensiteit_raw,
        gem_snelheid_text::numeric as gem_snelheid_raw,
        gewogen_gem_snelheid_text::numeric as gewogen_gem_snelheid_raw,
        rijstrook_rijbaan,
        voertuigcategorie,
        technical_exclusion,
        traffic_flow_deviation_exclusions
    from raw_values
)

select
    *,
    case when gem_intensiteit_raw >= 0 then gem_intensiteit_raw end as gem_intensiteit,
    case when gem_snelheid_raw >= 0 then gem_snelheid_raw end as gem_snelheid,
    case
        when gewogen_gem_snelheid_raw >= 0 then gewogen_gem_snelheid_raw
    end as gewogen_gem_snelheid,
    coalesce('i' = any(string_to_array(technical_exclusion, ',')), false)
        as intensiteit_technisch_uitgesloten,
    coalesce('v' = any(string_to_array(technical_exclusion, ',')), false)
        as snelheid_technisch_uitgesloten,
    coalesce('cat' = any(string_to_array(technical_exclusion, ',')), false)
        as categorie_technisch_uitgesloten
from typed
