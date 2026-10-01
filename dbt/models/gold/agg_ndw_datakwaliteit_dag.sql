{{ config(materialized='table', indexes=[{'columns': ['meetdatum'], 'unique': true}]) }}

select
    meetdatum,
    count(*) as aantal_geleverde_tijdvakken,
    count(*) filter (where is_volledig_uur) as aantal_volledige_uurvakken,
    count(*) filter (where intensiteit_bruikbaar) as aantal_intensiteit_bruikbaar,
    count(*) filter (where snelheid_bruikbaar) as aantal_snelheid_bruikbaar,
    count(*) filter (where kwaliteitsstatus = 'geen_meting') as aantal_zonder_meting,
    count(*) filter (
        where kwaliteitsstatus = 'gedeeltelijke_meting'
    ) as aantal_gedeeltelijke_metingen,
    count(*) filter (where kwaliteitsstatus = 'datafout') as aantal_datafouten,
    count(*) filter (
        where kwaliteitsstatus = 'technisch_uitgesloten'
    ) as aantal_technische_uitsluitingen,
    round(
        100.0 * count(*) filter (where intensiteit_bruikbaar)
        / nullif(count(*), 0),
        2
    ) as dekking_intensiteit_pct,
    round(
        100.0 * count(*) filter (where snelheid_bruikbaar)
        / nullif(count(*), 0),
        2
    ) as dekking_snelheid_pct
from {{ ref('fct_ndw_verkeer_uur') }}
where is_totaalverkeer
group by meetdatum
