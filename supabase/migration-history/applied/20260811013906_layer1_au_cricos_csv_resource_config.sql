update pipeline.sources s
set metadata = coalesce(s.metadata,'{}'::jsonb) || jsonb_build_object(
  'preferred_resource_format','CSV',
  'required_resources',jsonb_build_array('CRICOS Institutions.csv','CRICOS Courses.csv')
), updated_at=now()
from integration.systems i, ref.countries c
where s.system_id=i.id and s.country_id=c.id
  and i.code='au_cricos' and c.iso_alpha2='AU';
