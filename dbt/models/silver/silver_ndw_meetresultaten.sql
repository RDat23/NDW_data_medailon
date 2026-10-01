{{
    config(
        materialized='incremental',
        incremental_strategy='delete+insert',
        unique_key='bronze_record_id',
        on_schema_change='sync_all_columns',
        indexes=[
            {'columns': ['bronze_record_id'], 'unique': true},
            {'columns': ['batch_id']},
            {'columns': ['id_meetlocatie', 'start_meetperiode']}
        ]
    )
}}

with measurements as (
    select *
    from {{ ref('stg_ndw_intensiteit_snelheid') }}
    {% if is_incremental() %}
    where batch_id not in (select distinct batch_id from {{ this }})
    {% endif %}
)

select
    *,
    start_meetperiode::date as meetdatum,
    extract(hour from start_meetperiode)::smallint as meetuur,
    case
        when technical_exclusion is not null then 'technisch_uitgesloten'
        when coalesce(data_error_intensiteit, 0) = 1
          or coalesce(data_error_snelheid, 0) = 1 then 'datafout'
        when gem_intensiteit is null and gem_snelheid is null then 'geen_meting'
        when gem_intensiteit is null or gem_snelheid is null then 'gedeeltelijke_meting'
        else 'bruikbaar'
    end as kwaliteitsstatus,
    (
        gem_intensiteit is not null
        and coalesce(data_error_intensiteit, 0) = 0
        and not intensiteit_technisch_uitgesloten
    ) as intensiteit_bruikbaar,
    (
        gem_snelheid is not null
        and coalesce(data_error_snelheid, 0) = 0
        and not snelheid_technisch_uitgesloten
    ) as snelheid_bruikbaar
from measurements
