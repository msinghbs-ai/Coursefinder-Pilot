-- CF-247 Website API v3, build brief WP-1.5 (O20, REQ-28): the source of each academic entry row. Decision 277: v3 only; v2 is only read.
--   provider entry_matrix[] (provider, with or without edu_country): each item gains quote (the provider's own words the row was read from) and
--     source_url (the page or file it was read from). Same items, same order and same values as v2 otherwise. Live 12 Nov 2026: all 1,289
--     active rows hold both.
--   course entry.resolution.rows[] (course with edu_country): each row gains source_url, the page the row's quote was read from (the provider's
--     table for that country, else the course page); null when not held.
-- New: security.entry_matrix_payload_v3 (security.entry_matrix_payload_v1 plus quote and source_url; v1 unchanged).
-- Replaces: public.website_v3_provider (both forms), public.website_v3_course(text, text) (same names and signatures; md5-guarded against the
--   WP-1.1 and WP-0 definitions). Retires: nothing.

do $guard$
declare v_want jsonb := jsonb_build_object(
  'public.website_v3_provider(text)', '87f7de23346bdd960fefc0ce5af92d9c',
  'public.website_v3_provider(text,text)', 'daf3b4a4b89edc5d864fd2d4a5269b7e',
  'public.website_v3_course(text,text)', '7f56ec0e8fc16b05f8ff5fb15a2998dc'); k text;
begin
  for k in select jsonb_object_keys(v_want) loop
    if md5(pg_get_functiondef(k::regprocedure)) <> v_want->>k then
      raise exception 'live % differs from the definition this change replaces (md5 %)', k, md5(pg_get_functiondef(k::regprocedure));
    end if;
  end loop;
end $guard$;

create or replace function security.entry_matrix_payload_v3(p_provider uuid, p_country text)
returns jsonb language sql stable security definer set search_path = '' as $$
  -- security.entry_matrix_payload_v1 with quote and source_url on each item (same rows, order and values)
  select coalesce(jsonb_agg(jsonb_strip_nulls(jsonb_build_object('course_code', k.course_code)) || jsonb_build_object(
           'country', m.country_code, 'study_level', m.level_label, 'qualification', m.qualification_name, 'min_grade', m.min_grade,
           'scale', case when m.min_grade is null then 'none' else m.grade_scale end, 'band', m.benchmark_band, 'conditions', m.conditions, 'as_at', m.as_at,
           'scale_stated', case when m.min_grade is null or m.grade_scale = 'none' then null else m.grade_scale is not null end,
           'quote', m.quote, 'source_url', m.source_url)
           order by m.country_code, m.level_label, m.benchmark_band, m.qualification_name), '[]'::jsonb)
    from catalogue.provider_entry_matrix m left join catalogue.courses k on k.id = m.course_id
   where m.provider_id = p_provider and m.status = 'active' and (p_country is null or m.country_code = upper(p_country))
$$;
comment on function security.entry_matrix_payload_v3(uuid, text) is
  'Website API v3 O20 (build brief WP-1.5): the provider entry matrix as entry_matrix_payload_v1 plus quote and source_url on each item.';
revoke all on function security.entry_matrix_payload_v3(uuid, text) from public, anon, authenticated;

create or replace function public.website_v3_provider(p_provider_id text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_provider(p_provider_id); v_pid uuid;
begin
  if jsonb_typeof(v->'item') = 'object' then
    v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item'));
    select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_provider_id)) limit 1;
    if v ? 'item' and (v->'item') ? 'entry_matrix' then v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(v_pid, null)); end if;
  end if;
  return v;
end $$;
create or replace function public.website_v3_provider(p_provider_id text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_provider(p_provider_id, p_edu_country); v_pid uuid;
begin
  if jsonb_typeof(v->'item') = 'object' then
    v := jsonb_set(v, '{item}', public.website_v3_provider_item(v->'item'));
    select p.id into v_pid from catalogue.providers p where lower(p.stable_key) = lower(btrim(p_provider_id)) limit 1;
    if (v->'item') ? 'entry_matrix' then v := jsonb_set(v, '{item,entry_matrix}', security.entry_matrix_payload_v3(v_pid, upper(btrim(p_edu_country)))); end if;
  end if;
  return v;
end $$;

create or replace function public.website_v3_course(p_identifier text, p_edu_country text)
returns jsonb language plpgsql stable security definer set search_path = '' as $$
declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v #> '{item,entry,resolution,rows}') = 'array' then
    select d.course_id, d.provider_id into v_course, v_provider from search.course_documents d
     where lower(d.course_stable_key) = lower(v->'item'->>'course_id') and d.course_stable_key is not null limit 1;
    v := jsonb_set(v, '{item,entry,resolution,rows}', (select coalesce(jsonb_agg(r || jsonb_build_object('source_url', coalesce(
             (select m.source_url from catalogue.provider_entry_matrix m
               where m.provider_id = v_provider and m.status = 'active' and m.country_code = v_cc and m.quote = r->>'quote' order by m.updated_at desc limit 1),
             (select x.source_url from catalogue.course_entry_requirements x
               where x.course_id = v_course and x.status = 'active' and x.quote = r->>'quote' order by x.updated_at desc limit 1))) order by o), '[]'::jsonb)
        from jsonb_array_elements(v #> '{item,entry,resolution,rows}') with ordinality t(r, o)));
  end if;
  return v;
end $$;

comment on function public.website_v3_provider(text) is 'Website API v3 (Decision 277): website_v2_provider with R23, R31 and entry_matrix[] quote and source_url (O20).';
comment on function public.website_v3_provider(text, text) is 'Website API v3 (Decision 277): website_v2_provider with R23, R31 and entry_matrix[] quote and source_url (O20).';
comment on function public.website_v3_course(text, text) is 'Website API v3 (Decision 277): website_v2_course with R28 and entry.resolution.rows[] source_url (O20).';
