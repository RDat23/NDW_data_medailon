{{ config(materialized='view') }}

select
    id_meetlocatie,
    ndw_index,
    min(start_meetperiode) as eerste_meetperiode,
    max(eind_meetperiode) as laatste_meetperiode,
    count(*) as aantal_records,
    count(*) filter (where kwaliteitsstatus = 'bruikbaar') as aantal_bruikbare_records,
    count(distinct rijstrook_rijbaan) as aantal_rijstrookwaarden,
    count(distinct voertuigcategorie) as aantal_voertuigcategorieen
from {{ ref('silver_ndw_meetresultaten') }}
group by id_meetlocatie, ndw_index
