-- M2.1 / PIM v2.13 Course detail read contract.
-- Purpose: surface the governed official Course link captured by Layer 2 and include
-- link/description Evidence in Course detail without changing Search/publication authority.

create or replace function public.ui_course_detail(p_course_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public','catalogue','ref','pim'
as $function$
  select case when c.id is null then null else jsonb_build_object(
    'id', c.id,
    'stable_key', c.stable_key,
    'canonical_title', c.canonical_title,
    'display_title', c.display_title,
    'course_code', c.course_code,
    'provider_id', c.provider_id,
    'provider_name', p.canonical_name,
    'level_code', sl.code,
    'level_name', sl.name,
    'field_code', fos.code,
    'field_name', fos.name,
    'description', c.description,
    'course_url', coalesce(
      nullif(c.course_url,''),
      (select cl.url from catalogue.course_links cl
       where cl.course_id=c.id
         and cl.link_type='official_course'
         and coalesce(cl.status,'active')='active'
       order by (cl.audience='international') desc,
                cl.last_verified_at desc nulls last,
                cl.created_at desc
       limit 1)
    ),
    'duration_value', c.duration_value,
    'duration_unit', c.duration_unit,
    'delivery_mode', c.delivery_mode,
    'lifecycle_status', c.lifecycle_status,
    'publication_status', c.publication_status,
    'last_verified_at', greatest(
      c.last_verified_at,
      (select max(cl.last_verified_at)
       from catalogue.course_links cl
       where cl.course_id=c.id
         and cl.link_type='official_course'
         and coalesce(cl.status,'active')='active')
    ),
    'fees', coalesce((
      select jsonb_agg(jsonb_build_object(
        'year',f.fee_year,'audience',f.audience,'type',f.fee_type,
        'amount',f.amount,'currency',f.currency_code,'basis',f.basis,'csp',f.is_csp
      ) order by f.fee_year desc,f.audience)
      from catalogue.course_fees f where f.course_id=c.id
    ),'[]'::jsonb),
    'intakes', coalesce((
      select jsonb_agg(jsonb_build_object(
        'year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,
        'deadline',i.application_deadline,'status',i.status
      ) order by i.start_date nulls last,i.intake_label)
      from catalogue.course_intakes i where i.course_id=c.id
    ),'[]'::jsonb),
    'english', coalesce((
      select jsonb_agg(jsonb_build_object(
        'test_code',et.code,'test_name',et.name,'overall_score',er.overall_score,
        'components',er.component_scores,'notes',er.notes,'confidence',er.confidence
      ) order by et.code)
      from catalogue.course_english_requirements er
      join ref.english_tests et on et.id=er.english_test_id
      where er.course_id=c.id
    ),'[]'::jsonb),
    'academic_options', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',ao.id,'type',ao.option_type,'code',ao.code,'name',ao.name,
        'description',ao.description,'status',ao.status
      ) order by ao.display_order,ao.name)
      from catalogue.course_academic_options ao where ao.course_id=c.id
    ),'[]'::jsonb),
    'collections', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',col.id,'name',col.name,'code',col.code,'is_primary',m.is_primary,
        'relationship_type',m.relationship_type
      ) order by m.is_primary desc,m.display_order,col.name)
      from catalogue.course_collection_memberships m
      join catalogue.course_collections col on col.id=m.collection_id
      where m.course_id=c.id
    ),'[]'::jsonb),
    'categories', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id',cat.id,'code',cat.code,'name',cat.name,'type',cat.category_type,
        'is_primary',ec.is_primary
      ) order by ec.is_primary desc,ec.display_order,cat.name)
      from pim.entity_categories ec
      join pim.categories cat on cat.id=ec.category_id
      where ec.entity_id=c.id
    ),'[]'::jsonb)
  ) end
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  left join ref.study_levels sl on sl.id=c.study_level_id
  left join ref.fields_of_study fos on fos.id=c.primary_field_id
  where c.id=p_course_id
    and auth.uid() is not null
    and security.current_role_rank() >= 1;
$function$;

-- admin_read_impl is intentionally retained as the governed Course detail dispatcher.
-- The live migration additionally expands its course_detail Evidence union to include:
--   catalogue.course_links.evidence_id
--   pim.attribute_values.evidence_id for the matching Course entity_registry stable_key
-- and emits evidence_type consistently for the dedicated PIM v2.13 renderer.
-- This repository mirror records the material read-contract change while preserving the
-- existing role-gated dispatcher implementation already versioned in earlier migrations.
