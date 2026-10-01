select bronze_record_id
from {{ ref('silver_ndw_meetresultaten') }}
where start_meetperiode >= eind_meetperiode
