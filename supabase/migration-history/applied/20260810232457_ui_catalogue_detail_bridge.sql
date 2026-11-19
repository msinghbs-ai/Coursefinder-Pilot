create or replace function public.ui_campuses_list(p_limit integer default 500)
returns table(
  id uuid, stable_key text, name text, campus_code text, provider_id uuid, provider_name text,
  country_code text, city text, postcode text, status text, publication_status text, course_count bigint
)
language sql
security definer
set search_path = public, catalogue, ref
as $$
  select ca.id, ca.stable_key, ca.name, ca.campus_code, ca.provider_id, p.canonical_name,
         c.iso_alpha2::text, ca.city, ca.postcode, ca.status, ca.publication_status,
         count(distinct cc.course_id)::bigint
  from catalogue.campuses ca
  join catalogue.providers p on p.id=ca.provider_id
  left join ref.countries c on c.id=ca.country_id
  left join catalogue.course_campuses cc on cc.campus_id=ca.id
  where auth.uid() is not null
  group by ca.id, ca.stable_key, ca.name, ca.campus_code, ca.provider_id, p.canonical_name,
           c.iso_alpha2, ca.city, ca.postcode, ca.status, ca.publication_status
  order by p.canonical_name, ca.name
  limit least(greatest(coalesce(p_limit,500),1),2000);
$$;

create or replace function public.ui_course_collections_list(p_limit integer default 500)
returns table(
  id uuid, stable_key text, name text, code text, provider_id uuid, provider_name text,
  parent_id uuid, parent_name text, lifecycle_status text, publication_status text, course_count bigint
)
language sql
security definer
set search_path = public, catalogue
as $$
  select cc.id, cc.stable_key, cc.name, cc.code, cc.provider_id, p.canonical_name,
         cc.parent_id, parent.name, cc.lifecycle_status, cc.publication_status,
         count(distinct m.course_id)::bigint
  from catalogue.course_collections cc
  join catalogue.providers p on p.id=cc.provider_id
  left join catalogue.course_collections parent on parent.id=cc.parent_id
  left join catalogue.course_collection_memberships m on m.collection_id=cc.id
  where auth.uid() is not null
  group by cc.id, cc.stable_key, cc.name, cc.code, cc.provider_id, p.canonical_name,
           cc.parent_id, parent.name, cc.lifecycle_status, cc.publication_status
  order by p.canonical_name, cc.display_order, cc.name
  limit least(greatest(coalesce(p_limit,500),1),2000);
$$;

create or replace function public.ui_categories_list(p_limit integer default 1000)
returns table(
  id uuid, code text, name text, category_type text, parent_id uuid, parent_name text,
  path text, depth smallint, status text, entity_count bigint
)
language sql
security definer
set search_path = public, pim
as $$
  select cat.id, cat.code, cat.name, cat.category_type, cat.parent_id, parent.name,
         cat.path, cat.depth, cat.status, count(distinct ec.entity_id)::bigint
  from pim.categories cat
  left join pim.categories parent on parent.id=cat.parent_id
  left join pim.entity_categories ec on ec.category_id=cat.id
  where auth.uid() is not null
  group by cat.id, cat.code, cat.name, cat.category_type, cat.parent_id, parent.name,
           cat.path, cat.depth, cat.status
  order by cat.category_type, cat.path, cat.display_order, cat.name
  limit least(greatest(coalesce(p_limit,1000),1),3000);
$$;

create or replace function public.ui_course_detail(p_course_id uuid)
returns jsonb
language sql
security definer
set search_path = public, catalogue, ref, pim
as $$
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
    'course_url', c.course_url,
    'duration_value', c.duration_value,
    'duration_unit', c.duration_unit,
    'delivery_mode', c.delivery_mode,
    'lifecycle_status', c.lifecycle_status,
    'publication_status', c.publication_status,
    'last_verified_at', c.last_verified_at,
    'fees', coalesce((select jsonb_agg(jsonb_build_object('year',f.fee_year,'audience',f.audience,'type',f.fee_type,'amount',f.amount,'currency',f.currency_code,'basis',f.basis,'csp',f.is_csp) order by f.fee_year desc, f.audience) from catalogue.course_fees f where f.course_id=c.id), '[]'::jsonb),
    'intakes', coalesce((select jsonb_agg(jsonb_build_object('year',i.intake_year,'label',i.intake_label,'start_date',i.start_date,'deadline',i.application_deadline,'status',i.status) order by i.start_date nulls last, i.intake_label) from catalogue.course_intakes i where i.course_id=c.id), '[]'::jsonb),
    'english', coalesce((select jsonb_agg(jsonb_build_object('test_code',et.code,'test_name',et.name,'overall_score',er.overall_score,'components',er.component_scores,'notes',er.notes,'confidence',er.confidence) order by et.code) from catalogue.course_english_requirements er join ref.english_tests et on et.id=er.english_test_id where er.course_id=c.id), '[]'::jsonb),
    'academic_options', coalesce((select jsonb_agg(jsonb_build_object('id',ao.id,'type',ao.option_type,'code',ao.code,'name',ao.name,'description',ao.description,'status',ao.status) order by ao.display_order, ao.name) from catalogue.course_academic_options ao where ao.course_id=c.id), '[]'::jsonb),
    'collections', coalesce((select jsonb_agg(jsonb_build_object('id',col.id,'name',col.name,'code',col.code,'is_primary',m.is_primary,'relationship_type',m.relationship_type) order by m.is_primary desc, m.display_order, col.name) from catalogue.course_collection_memberships m join catalogue.course_collections col on col.id=m.collection_id where m.course_id=c.id), '[]'::jsonb),
    'categories', coalesce((select jsonb_agg(jsonb_build_object('id',cat.id,'code',cat.code,'name',cat.name,'type',cat.category_type,'is_primary',ec.is_primary) order by ec.is_primary desc, ec.display_order, cat.name) from pim.entity_categories ec join pim.categories cat on cat.id=ec.category_id where ec.entity_id=c.id), '[]'::jsonb)
  ) end
  from catalogue.courses c
  join catalogue.providers p on p.id=c.provider_id
  left join ref.study_levels sl on sl.id=c.study_level_id
  left join ref.fields_of_study fos on fos.id=c.primary_field_id
  where c.id=p_course_id and auth.uid() is not null;
$$;

revoke all on function public.ui_campuses_list(integer) from public, anon;
revoke all on function public.ui_course_collections_list(integer) from public, anon;
revoke all on function public.ui_categories_list(integer) from public, anon;
revoke all on function public.ui_course_detail(uuid) from public, anon;
grant execute on function public.ui_campuses_list(integer) to authenticated;
grant execute on function public.ui_course_collections_list(integer) to authenticated;
grant execute on function public.ui_categories_list(integer) to authenticated;
grant execute on function public.ui_course_detail(uuid) to authenticated;
