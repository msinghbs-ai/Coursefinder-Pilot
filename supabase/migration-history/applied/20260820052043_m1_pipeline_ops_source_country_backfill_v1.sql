update pipeline.sources s
set country_id=c.id, updated_at=now()
from ref.countries c
where s.country_id is null
  and nullif(btrim(s.metadata->>'country'),'') is not null
  and upper(btrim(s.metadata->>'country'))=c.iso_alpha2::text;
