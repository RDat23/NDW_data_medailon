select gold_record_id
from {{ ref('fct_ndw_verkeer_uur') }}
where bron_bestandsnaam = 'ndw_intensiteit_snelheid_test.csv'
