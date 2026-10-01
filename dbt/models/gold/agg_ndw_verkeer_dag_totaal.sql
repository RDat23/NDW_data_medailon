{{
    config(
        materialized='table',
        indexes=[
            {'columns': ['meetdatum']},
            {'columns': ['id_meetlocatie', 'meetdatum']}
        ]
    )
}}

select
    meetdatum,
    extract(year from meetdatum)::smallint as meetjaar,
    extract(month from meetdatum)::smallint as meetmaand,
    extract(week from meetdatum)::smallint as iso_week,
    extract(isodow from meetdatum)::smallint as weekdag_iso,
    id_meetlocatie,
    ndw_index,
    rijstrook_rijbaan,
    count(*) as aantal_geleverde_tijdvakken,
    count(*) filter (where is_volledig_uur) as aantal_volledige_uurvakken,
    count(*) filter (
        where is_volledig_uur and intensiteit_bruikbaar
    ) as aantal_uurvakken_intensiteit_bruikbaar,
    count(*) filter (
        where is_volledig_uur and snelheid_bruikbaar
    ) as aantal_uurvakken_snelheid_bruikbaar,
    sum(gem_intensiteit) filter (
        where is_volledig_uur and intensiteit_bruikbaar
    ) as som_uurintensiteit,
    avg(gem_intensiteit) filter (
        where is_volledig_uur and intensiteit_bruikbaar
    ) as gemiddelde_uurintensiteit,
    avg(gem_snelheid) filter (
        where is_volledig_uur and snelheid_bruikbaar
    ) as gemiddelde_snelheid_ongewogen,
    sum(
        coalesce(gewogen_gem_snelheid, gem_snelheid) * waarnemingen_snelheid
    ) filter (
        where is_volledig_uur
          and snelheid_bruikbaar
          and waarnemingen_snelheid > 0
    ) as snelheid_gewogen_teller,
    sum(waarnemingen_snelheid) filter (
        where is_volledig_uur
          and snelheid_bruikbaar
          and waarnemingen_snelheid > 0
    ) as snelheid_gewicht,
    sum(
        coalesce(gewogen_gem_snelheid, gem_snelheid) * waarnemingen_snelheid
    ) filter (
        where is_volledig_uur
          and snelheid_bruikbaar
          and waarnemingen_snelheid > 0
    ) / nullif(
        sum(waarnemingen_snelheid) filter (
            where is_volledig_uur
              and snelheid_bruikbaar
              and waarnemingen_snelheid > 0
        ),
        0
    ) as gemiddelde_snelheid_gewogen,
    round(
        100.0 * count(*) filter (
            where is_volledig_uur and intensiteit_bruikbaar
        ) / nullif(count(*) filter (where is_volledig_uur), 0),
        2
    ) as dekking_intensiteit_pct,
    round(
        100.0 * count(*) filter (
            where is_volledig_uur and snelheid_bruikbaar
        ) / nullif(count(*) filter (where is_volledig_uur), 0),
        2
    ) as dekking_snelheid_pct,
    count(*) filter (where kwaliteitsstatus = 'datafout') as aantal_datafouten,
    count(*) filter (
        where kwaliteitsstatus = 'technisch_uitgesloten'
    ) as aantal_technische_uitsluitingen
from {{ ref('fct_ndw_verkeer_uur') }}
where is_totaalverkeer
group by meetdatum, id_meetlocatie, ndw_index, rijstrook_rijbaan
