{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='gold_record_id',
        on_schema_change='sync_all_columns',
        indexes=[
            {'columns': ['gold_record_id'], 'unique': true},
            {'columns': ['batch_id']},
            {'columns': ['meetdatum']},
            {'columns': ['voertuigcategorie']},
            {'columns': ['id_meetlocatie', 'start_meetperiode']}
        ]
    )
}}

with source_rows as (
    select
        md5(
            jsonb_build_array(
                id_meetlocatie,
                ndw_index,
                start_meetperiode,
                eind_meetperiode,
                rijstrook_rijbaan,
                voertuigcategorie
            )::text
        ) as gold_record_id,
        bronze_record_id,
        batch_id,
        source_row_number,
        bron_object_key,
        bron_bestandsnaam,
        batch_ingestietijdstip,
        id_meetlocatie,
        ndw_index,
        start_meetperiode,
        eind_meetperiode,
        meetdatum,
        meetuur,
        extract(epoch from (eind_meetperiode - start_meetperiode)) / 60
            as meetduur_minuten,
        rijstrook_rijbaan,
        voertuigcategorie,
        coalesce(voertuigcategorie = 'anyVehicle', false) as is_totaalverkeer,
        gem_intensiteit,
        gem_snelheid,
        gewogen_gem_snelheid,
        waarnemingen_intensiteit,
        waarnemingen_snelheid,
        gebruikte_minuten_intensiteit,
        gebruikte_minuten_snelheid,
        intensiteit_bruikbaar,
        snelheid_bruikbaar,
        kwaliteitsstatus,
        data_error_intensiteit,
        data_error_snelheid,
        technical_exclusion,
        traffic_flow_deviation_exclusions
    from {{ ref('silver_ndw_meetresultaten') }}
    where bron_bestandsnaam <> 'ndw_intensiteit_snelheid_test.csv'
    {% if is_incremental() %}
      and batch_id not in (select distinct batch_id from {{ this }})
    {% endif %}
),

ranked as (
    select
        *,
        row_number() over (
            partition by gold_record_id
            order by batch_ingestietijdstip desc, source_row_number desc
        ) as versie_volgorde
    from source_rows
)

select
    gold_record_id,
    bronze_record_id,
    batch_id,
    source_row_number,
    bron_object_key,
    bron_bestandsnaam,
    batch_ingestietijdstip,
    id_meetlocatie,
    ndw_index,
    start_meetperiode,
    eind_meetperiode,
    meetdatum,
    meetuur,
    meetduur_minuten,
    meetduur_minuten = 60 as is_volledig_uur,
    rijstrook_rijbaan,
    voertuigcategorie,
    is_totaalverkeer,
    gem_intensiteit,
    gem_snelheid,
    gewogen_gem_snelheid,
    waarnemingen_intensiteit,
    waarnemingen_snelheid,
    gebruikte_minuten_intensiteit,
    gebruikte_minuten_snelheid,
    intensiteit_bruikbaar,
    snelheid_bruikbaar,
    kwaliteitsstatus,
    data_error_intensiteit,
    data_error_snelheid,
    technical_exclusion,
    traffic_flow_deviation_exclusions
from ranked
where versie_volgorde = 1
