{{ config(materialized='view') }}

select
    meetdatum,
    kwaliteitsstatus,
    count(*) as aantal_records,
    count(*) filter (where intensiteit_bruikbaar) as aantal_intensiteit_bruikbaar,
    count(*) filter (where snelheid_bruikbaar) as aantal_snelheid_bruikbaar,
    count(*) filter (where voertuigcategorie is null) as aantal_zonder_voertuigcategorie,
    count(*) filter (where traffic_flow_deviation_exclusions is not null)
        as aantal_met_verkeersafwijking
from {{ ref('silver_ndw_meetresultaten') }}
group by meetdatum, kwaliteitsstatus
