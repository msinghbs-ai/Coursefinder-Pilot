-- CF-CHG-20260901-061
-- Correct Provider city projection in the bounded comparison read.
-- The canonical Provider schema stores primary_city, not city.

begin;

create or replace function security.admin_contextual_compare(
  p_args jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'pg_catalog','security','catalogue','ref','auth'
as $$
declare
  v_rank integer:=0;
  v_type text:=lower(coalesce(nullif(btrim(p_args->>'entity_type'),''),'provider'));
  v_ids uuid[];
  v_count integer:=0;
  v_items jsonb:='[]'::jsonb;
begin
  if auth.uid() is null then raise exception 'authentication required' using errcode='42501'; end if;
  select security.current_role_rank() into v_rank;
  if coalesce(v_rank,0)<1 then raise exception 'catalogue reader role required' using errcode='42501'; end if;
  if v_type not in ('provider','course') then raise exception 'invalid comparison entity type' using errcode='22023'; end if;
  if jsonb_typeof(coalesce(p_args->'ids','[]'::jsonb))<>'array' then raise exception 'ids must be an array' using errcode='22023'; end if;

  begin
    select coalesce(array_agg(value::uuid order by ordinality),'{}'::uuid[])
      into v_ids
    from jsonb_array_elements_text(coalesce(p_args->'ids','[]'::jsonb)) with ordinality as z(value,ordinality);
  exception when invalid_text_representation then
    raise exception 'invalid comparison id' using errcode='22023';
  end;

  v_count:=coalesce(array_length(v_ids,1),0);
  if v_count>6 then raise exception 'maximum six comparison entities' using errcode='22023'; end if;
  if v_count=0 then
    return jsonb_build_object('entity_type',v_type,'items','[]'::jsonb,'total',0,'max_items',6);
  end if;

  if v_type='provider' then
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',p.id,
      'name',coalesce(p.display_name,p.canonical_name),
      'country_code',co.iso_alpha2,
      'subdivision',sd.name,
      'city',p.primary_city,
      'contextual_insights',security.admin_contextual_insights_v2('provider',p.id)
    ) order by u.ord),'[]'::jsonb)
    into v_items
    from unnest(v_ids) with ordinality u(id,ord)
    join catalogue.providers p on p.id=u.id
    left join ref.countries co on co.id=p.country_id
    left join ref.subdivisions sd on sd.id=p.subdivision_id;
  else
    select coalesce(jsonb_agg(jsonb_build_object(
      'id',c.id,
      'name',coalesce(c.display_title,c.canonical_title),
      'provider_id',p.id,
      'provider_name',coalesce(p.display_name,p.canonical_name),
      'course_code',c.course_code,
      'study_level',coalesce(sl.name,sl.code),
      'field_of_study',coalesce(f.name,f.code),
      'contextual_insights',security.admin_contextual_insights_v2('course',c.id)
    ) order by u.ord),'[]'::jsonb)
    into v_items
    from unnest(v_ids) with ordinality u(id,ord)
    join catalogue.courses c on c.id=u.id
    join catalogue.providers p on p.id=c.provider_id
    left join ref.study_levels sl on sl.id=c.study_level_id
    left join ref.fields_of_study f on f.id=c.primary_field_id;
  end if;

  return jsonb_build_object(
    'entity_type',v_type,
    'items',v_items,
    'total',jsonb_array_length(v_items),
    'requested_total',v_count,
    'max_items',6,
    'authority_note','Context only. QILT/PRISMS statistics retain their governed source grain and do not become Course facts.'
  );
end
$$;

revoke all on function security.admin_contextual_compare(jsonb) from public,anon,authenticated;
grant execute on function security.admin_contextual_compare(jsonb) to service_role;

commit;
