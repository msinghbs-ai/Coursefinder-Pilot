begin;

update pipeline.sources s
set metadata=coalesce(s.metadata,'{}'::jsonb)||jsonb_build_object(
  'layer','2A',
  'domain','scholarship',
  'identity_authority',false,
  'scholarship_source_key','au_provider_scholarship_detail_'||
    replace(s.provider_id::text,'-','')||'_'||
    substr(encode(extensions.digest(lower(trim(s.url)),'sha256'),'hex'),1,12),
  'change_control_ref','CF-CHG-20260903-083'
),
updated_at=now()
where s.source_type='scholarship_detail'
  and s.metadata->>'change_control_ref'='CF-CHG-20260903-083';

insert into pipeline.layer4_field_registry(
  entity_type,field_code,display_label,value_kind,editability_class,min_role_rank,
  publication_sensitive,enabled,notes
)
values(
  'scholarship','scope_resolution','Scholarship scope resolution','json','elevated',4,
  true,true,
  'Review-only scope/applicability decision for Provider/Course/Collection/Study Level/Field/Campus/Country include-exclude mappings before publication.'
)
on conflict(entity_type,field_code) do update set
  display_label=excluded.display_label,
  value_kind=excluded.value_kind,
  editability_class=excluded.editability_class,
  min_role_rank=excluded.min_role_rank,
  publication_sensitive=excluded.publication_sensitive,
  enabled=excluded.enabled,
  notes=excluded.notes;

commit;