update pipeline.sources s
set metadata = jsonb_set(
  coalesce(s.metadata,'{}'::jsonb),
  '{required_resources}',
  '["CRICOS Institutions.csv","CRICOS Courses.csv","CRICOS Locations.csv","CRICOS Course Locations.csv"]'::jsonb,
  true
) || jsonb_build_object('depth_scope',jsonb_build_array('provider','course','location','course_location'),'depth_version','layer1-edge-v1.2.0'),
updated_at=now()
from integration.systems i
where i.id=s.system_id and i.code='au_cricos';

update integration.systems
set config = jsonb_set(coalesce(config,'{}'::jsonb),'{coverage}','["provider","course","location","course_location"]'::jsonb,true),
    updated_at=now()
where code='au_cricos';
