select gold_record_id
from {{ ref('fct_ndw_verkeer_uur') }}
where is_totaalverkeer is distinct from coalesce(voertuigcategorie = 'anyVehicle', false)
