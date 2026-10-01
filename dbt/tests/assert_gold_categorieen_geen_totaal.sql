select *
from {{ ref('agg_ndw_verkeer_dag_voertuigcategorie') }}
where voertuigcategorie = 'anyVehicle'
