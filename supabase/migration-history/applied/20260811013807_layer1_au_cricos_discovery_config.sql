update pipeline.sources s
set metadata = coalesce(s.metadata,'{}'::jsonb) || jsonb_build_object(
  'discovery_url','https://data.gov.au/data/api/3/action/package_show?id=cricos',
  'discovery_type','ckan_package',
  'preferred_resource_format','ZIP',
  'dataset_slug','cricos'
), updated_at=now()
from integration.systems i, ref.countries c
where s.system_id=i.id and s.country_id=c.id
  and i.code='au_cricos' and c.iso_alpha2='AU';
