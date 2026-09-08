-- Extend the existing governed course-detail projection with display-safe PIM family/value metadata.
-- Browser access remains through public.admin_read('course_detail'); no direct PIM table grants are added.
-- PIM values are limited to accepted rows whose validity window includes current_date and whose attribute is visible in the assigned family.
-- Single-valued attributes expose at most one currently effective accepted preferred row; multivalue attributes retain the governed accepted effective set.
-- Top-level SQL null fields are stripped without recursively mutating governed value_json or option_labels JSON semantics.

create or replace function public.ui_course_detail(p_course_id uuid)
returns jsonb
language sql
security definer
set search_path to 'public', 'catalogue', 'ref', 'pim'
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
       where cl.course_id=c.id and cl.link_type='official_course' and coalesce(cl.status,'active')='active'
       order by (cl.audience='international') desc, cl.last_verified_at desc nulls last, cl.created_at desc
       limit 1)
    ),
    'duration_value', c.duration_value,
    'duration_unit', c.duration_unit,
    'delivery_mode', c.delivery_mode,
    'lifecycle_status', c.lifecycle_status,
    'publication_status', c.publication_status,
    'last_verified_at', greatest(c.last_verified_at,
      (select max(cl.last_verified_at) from catalogue.course_links cl where cl.course_id=c.id and cl.link_type='official_course' and coalesce(cl.status,'active')='active')
    ),
    'fees', coalesce((select jsonb_agg(jsonb_build_object('year',f.fee_year,'audience',f.audience,'type',f.fee_type,'amount',f.amount,'currency',f.currency_code,'basis',f.basis,'csp',f.is_csp) order by f.fee_year desc, f.audience) from catalogue.course_fees f where f.course_id=c.id), '[]'::jsonb),
    'intakes', coalesce((select jsonb_agg(jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'deadline',i.application_deadline,'status',i.status) order by i.start_date nulls last, i.intake_label) from catalogue.course_intakes i where i.course_id=c.id), '[]'::jsonb),
    'english', coalesce((select jsonb_agg(jsonb_build_object('test_code',et.code,'test_name',et.name,'overall_score',er.overall_score,'components',er.component_scores,'notes',er.notes,'confidence',er.confidence) order by et.code) from catalogue.course_english_requirements er join ref.english_tests et on et.id=er.english_test_id where er.course_id=c.id), '[]'::jsonb),
    'academic_options', coalesce((select jsonb_agg(jsonb_build_object('id',ao.id,'type',ao.option_type,'code',ao.code,'name',ao.name,'description',ao.description,'status',ao.status) order by ao.display_order, ao.name) from catalogue.course_academic_options ao where ao.course_id=c.id), '[]'::jsonb),
    'collections', coalesce((select jsonb_agg(jsonb_build_object('id',col.id,'name',col.name,'code',col.code,'is_primary',m.is_primary,'relationship_type',m.relationship_type) order by m.is_primary desc, m.display_order, col.name) from catalogue.course_collection_memberships m join catalogue.course_collections col on col.id=m.collection_id where m.course_id=c.id), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id',cat.id,'code',cat.code,'name',cat.name,'type',cat.category_type,'is_primary',ec.is_primary) order by ec.is_primary desc, ec.display_order, cat.name) from pim.entity_categories ec join pim.categories cat on cat.id=ec.category_id where ec.entity_id=c.id), '[]'::jsonb),
    'pim_family_id', (select er2.family_id from pim.entity_registry er2 where er2.entity_type='course' and er2.stable_key=c.stable_key limit 1),
    'pim_family_name', (select af2.name from pim.entity_registry er2 join pim.attribute_families af2 on af2.id=er2.family_id where er2.entity_type='course' and er2.stable_key=c.stable_key limit 1),
    'pim_attribute_values', coalesce((
      select jsonb_agg((
        jsonb_strip_nulls(jsonb_build_object(
          'id', av.id,
          'attribute_id', av.attribute_id,
          'attribute_code', ad.code,
          'attribute_name', ad.name,
          'attribute_data_type', ad.data_type,
          'attribute_display_order', coalesce(fa.display_order,ad.display_order),
          'attribute_is_multivalue', ad.is_multivalue,
          'value_text', av.value_text,
          'value_number', av.value_number,
          'value_boolean', av.value_boolean,
          'value_date', av.value_date,
          'value_datetime', av.value_datetime,
          'value_code', av.value_code,
          'locale', av.locale,
          'channel_code', av.channel_code,
          'position', av.position,
          'source_id', av.source_id,
          'evidence_id', av.evidence_id,
          'confidence', av.confidence,
          'review_status', av.review_status,
          'is_preferred', av.is_preferred,
          'valid_from', av.valid_from,
          'valid_to', av.valid_to
        ))
        || case when av.value_json is not null then jsonb_build_object('value_json', av.value_json) else '{}'::jsonb end
        || jsonb_build_object('option_labels', coalesce((select jsonb_object_agg(ao.code,ao.label order by ao.display_order nulls last,ao.code) from pim.attribute_options ao where ao.attribute_id=ad.id and coalesce(ao.status,'active')='active'),'{}'::jsonb))
      ) order by coalesce(fa.display_order,ad.display_order), av.position nulls first, av.created_at)
      from pim.entity_registry er2
      join pim.attribute_values av on av.entity_id=er2.id
      join pim.attribute_definitions ad on ad.id=av.attribute_id
      join pim.family_attributes fa on fa.family_id=er2.family_id and fa.attribute_id=ad.id
      where er2.entity_type='course'
        and er2.stable_key=c.stable_key
        and ad.entity_type='course'
        and coalesce(ad.status,'active')='active'
        and fa.is_visible is true
        and av.review_status='accepted'
        and (av.valid_from is null or av.valid_from <= current_date)
        and (av.valid_to is null or av.valid_to >= current_date)
        and (
          coalesce(ad.is_multivalue,false)
          or av.id = (
            select avp.id
            from pim.attribute_values avp
            where avp.entity_id=av.entity_id
              and avp.attribute_id=av.attribute_id
              and avp.review_status='accepted'
              and avp.is_preferred is true
              and (avp.valid_from is null or avp.valid_from <= current_date)
              and (avp.valid_to is null or avp.valid_to >= current_date)
            order by avp.valid_from desc nulls last, avp.created_at desc, avp.id
            limit 1
          )
        )
    ), '[]'::jsonb),
    'field_states', security.admin_course_field_states(c.id)
  ) end
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  left join ref.study_levels sl on sl.id=c.study_level_id
  left join ref.fields_of_study fos on fos.id=c.primary_field_id
  where c.id=p_course_id and auth.uid() is not null and security.current_role_rank() >= 1;
$function$;
