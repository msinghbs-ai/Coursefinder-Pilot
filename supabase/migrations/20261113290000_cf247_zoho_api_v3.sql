-- CF-247 Zoho API v3 (S2-CF directive, Platform Admin 13 Nov 2026 10:25, section 3; Decision 277; register Z1 and Z4): a separate copy beside
-- Zoho v2, built on the Website v3 that is live. This is what was still needed from draft Pilot #1085; its website dispatcher, schema api_v3
-- and release switch are not taken. Zoho v2 (public.zoho_v2_*, zoho-api-v2) and Website v2 are only read; nothing they read is changed.
-- Served by the new edge function zoho-api-v3: the same Zoho keys, rate limit and call log as v2 (actions logged as "v3:<action>").
-- Zoho switches by changing the address, one screen or one sync at a time; nothing switches by itself and there is no global gate.
-- Every v3 action is the v2 action (same arguments, paging, errors and v2 fields) with these additions:
--   search    each item gains intakes[].start_date_status (R28), description_excerpt (O26) and scholarships_top[] (Z1, REQ-31): the first
--             five published scholarships of the course as held in the search record, each scholarship_id, name, amount_type, amount_value,
--             amount_currency (the same values the scholarship action returns; checked when the migration is applied). An empty list means none is held.
--   course    intakes[].start_date_status (R28); with edu_country (Z4, REQ-28: the country of previous education, ISO alpha-2) the item's
--             entry is the Website v3 entry for that country, with quote and source_url on each resolution row (O20). An unknown code is
--             refused (INVALID_INPUT). Without edu_country the item is the v2 item with R28.
--   courses   as course without edu_country, for each identifier.
--   scholarships, scholarship, rankings   the Website v3 answers (scholarship detail fields, R24, R29 paging through filters).
--   reference, providers, provider, campuses, contacts, statistics, report, report_status, sync, export   the v2 answers unchanged.
--             sync and export stay v2 in this release: the sync record and its change cursor are built from v2 items, so v3 fields come
--             through search, course(s) and scholarship(s). Z3 (countries beyond AU) is the existing setting zoho.sync_countries; it is not
--             changed here (a consumer change, held for the developer communication).
-- Replaces: nothing.
-- Retires: nothing (draft Pilot #1085 is closed unmerged; nothing of it was ever applied).
-- Reversal: none needed: nothing calls these functions until Zoho uses the v3 address. They are removed by paste file if v3 is withdrawn.

-- Z1: the first five published scholarships of each course, in the search record's own order, for a page of courses in one statement
-- (the blocked-scholarship list is read once a page: read once an item it took 60 ms an item in the dry run). The amount fields follow
-- the rule of api.website_v2_scholarship_item and are compared with it when this migration is applied.
create or replace function public.zoho_v3_scholarships_top(p_courses uuid[]) returns table(course_id uuid, top jsonb)
language sql stable security definer set search_path = '' as $$
  with blocked as materialized (select b.scholarship_id from security.layer4_search_blocked_scholarships b where b.scholarship_id is not null)
  select d.course_id, coalesce((select jsonb_agg(jsonb_build_object('scholarship_id', t.stable_key, 'name', t.name,
             'amount_type', case when t.award_value_type = 'fixed_amount' then 'fixed_amount'
                                 when t.award_value_type = 'percentage' and t.award_percentage >= 100 then 'full_tuition'
                                 when t.award_value_type = 'percentage' then 'percentage_tuition' end,
             'amount_value', coalesce(t.award_amount, t.award_percentage), 'amount_currency', t.award_currency_code) order by t.o)
           from (select x.o, s.stable_key, s.name, s.award_value_type, s.award_percentage, s.award_amount, s.award_currency_code
                   from jsonb_array_elements(coalesce(d.scholarship_options, '[]'::jsonb)) with ordinality x(opt, o)
                   join scholarship.scholarships s on s.stable_key = x.opt->>'scholarship_key' and s.lifecycle_status = 'active' and s.publication_status = 'published'
                  where s.id not in (select b.scholarship_id from blocked b)
                  order by x.o limit 5) t), '[]'::jsonb)  -- fixed: API contract (register Z1: top five)
    from search.course_documents d where d.course_id = any (p_courses)
$$;
comment on function public.zoho_v3_scholarships_top(uuid[]) is
  'Zoho API v3 Z1 (REQ-31): for each course, its first five published scholarships (search record order) with the amount fields of the scholarship action.';

create or replace function public.zoho_v3_course_search(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.zoho_v2_course_search(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (
      with it as (select t.x, t.o, (select d.course_id from search.course_documents d where lower(d.course_stable_key) = lower(t.x->>'course_id') and d.course_stable_key is not null limit 1) cid
                    from jsonb_array_elements(v->'items') with ordinality t(x, o)),
           tp as (select z.course_id, z.top from public.zoho_v3_scholarships_top(array(select it.cid from it where it.cid is not null)) z)
      select coalesce(jsonb_agg(public.website_v3_course_search_item(it.x) || jsonb_build_object('scholarships_top', coalesce(tp.top, '[]'::jsonb)) order by it.o), '[]'::jsonb)
        from it left join tp on tp.course_id = it.cid));
  end if;
  return v;
end $$;
comment on function public.zoho_v3_course_search(jsonb, integer, integer, text) is
  'Zoho API v3: public.zoho_v2_course_search with intakes[].start_date_status (R28), description_excerpt (O26) and scholarships_top[] (Z1) on each item.';

create or replace function public.zoho_v3_course(p_identifier text, p_edu_country text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.zoho_v2_course(p_identifier); w jsonb;
begin
  if nullif(btrim(coalesce(p_edu_country, '')), '') is not null then
    w := public.website_v3_course(p_identifier, p_edu_country); -- refuses an unknown country (INVALID_INPUT), as the website action does
  end if;
  if jsonb_typeof(v->'item') = 'object' then
    v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item'));
    if w #> '{item,entry}' is not null and w #>> '{item,course_id}' = v #>> '{item,course_id}' then v := jsonb_set(v, '{item,entry}', w #> '{item,entry}'); end if;
  end if;
  return v;
end $$;
comment on function public.zoho_v3_course(text, text) is
  'Zoho API v3: public.zoho_v2_course with intakes[].start_date_status (R28); with edu_country (Z4) the entry is the Website v3 entry for that country.';

create or replace function public.zoho_v3_courses(p_identifiers text[])
returns jsonb language plpgsql security definer set search_path = '' as $$
declare v jsonb := public.zoho_v2_courses(p_identifiers);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_course_item_r28(x) order by o), '[]'::jsonb) from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $$;
comment on function public.zoho_v3_courses(text[]) is 'Zoho API v3: public.zoho_v2_courses with intakes[].start_date_status (R28) on each item.';

-- scholarships, scholarship and rankings: the Website v3 answers, labelled as the v2 passthrough labels them; report as v2
create or replace function public.zoho_v3_passthrough(p_action text, p_filters jsonb, p_page integer, p_page_size integer, p_id text, p_body jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r jsonb; v_max int := greatest(security.pipeline_num_v1('zoho.page_max', 50)::int, 1);
begin
  if p_action not in ('rankings', 'scholarships', 'scholarship') then return public.zoho_v2_passthrough(p_action, p_filters, p_page, p_page_size, p_id, p_body); end if;
  if p_action in ('rankings', 'scholarships') and coalesce(p_page_size, 20) > v_max then raise exception 'INVALID_INPUT: page_size must be 1-%', v_max using errcode = '22023'; end if;
  r := case p_action
    when 'rankings' then public.website_v3_rankings(coalesce(p_filters, '{}'::jsonb), coalesce(p_page, 1), coalesce(p_page_size, 20))
    when 'scholarships' then public.website_v3_scholarships(coalesce(p_filters, '{}'::jsonb), coalesce(p_page, 1), coalesce(p_page_size, 20))
    else public.website_v3_scholarship(p_id, coalesce(p_filters, jsonb_build_object('page', null, 'page_size', null))) end; -- R29: p_filters carries {page, page_size} of the linked courses
  if r ? 'error' and (r->'error'->>'code' = 'NOT_FOUND' or r->>'error' = 'NOT_FOUND') then return jsonb_build_object('api_version', 'zoho-v3', 'error', jsonb_build_object('code', 'NOT_FOUND')); end if;
  return (r - 'contract_version') || jsonb_build_object('api_version', 'zoho-v3');
end $$;
comment on function public.zoho_v3_passthrough(text, jsonb, integer, integer, text, jsonb) is
  'Zoho API v3: rankings, scholarships and scholarship from the Website v3 functions (scholarship: filters carry the linked-course paging of R29); any other action as public.zoho_v2_passthrough.';

-- the actions v3 does not change yet: the v2 answer
create or replace function public.zoho_v3_reference() returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_reference() $$;
create or replace function public.zoho_v3_providers(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_providers(p_filters, p_page, p_page_size, p_sort) $$;
create or replace function public.zoho_v3_provider(p_identifier text) returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_provider(p_identifier) $$;
create or replace function public.zoho_v3_list(p_entity text, p_filters jsonb, p_page integer, p_page_size integer)
returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_list(p_entity, p_filters, p_page, p_page_size) $$;
create or replace function public.zoho_v3_statistics(p_kind text, p_filters jsonb, p_page integer, p_page_size integer)
returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_statistics(p_kind, p_filters, p_page, p_page_size) $$;
create or replace function public.zoho_v3_report(p_body jsonb) returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_report(p_body) $$;
create or replace function public.zoho_v3_report_status(p_flag_ids jsonb) returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_report_status(p_flag_ids) $$;
create or replace function public.zoho_v3_sync(p_cursor text, p_full boolean, p_entities text[], p_page_size integer)
returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_sync(p_cursor, p_full, p_entities, p_page_size) $$;
create or replace function public.zoho_v3_export_page(p_entity text, p_page integer)
returns jsonb language sql security definer set search_path = '' as $$ select public.zoho_v2_export_page(p_entity, p_page) $$;
comment on function public.zoho_v3_reference() is 'Zoho API v3: public.zoho_v2_reference unchanged.';
comment on function public.zoho_v3_providers(jsonb, integer, integer, text) is 'Zoho API v3: public.zoho_v2_providers unchanged.';
comment on function public.zoho_v3_provider(text) is 'Zoho API v3: public.zoho_v2_provider unchanged.';
comment on function public.zoho_v3_list(text, jsonb, integer, integer) is 'Zoho API v3: public.zoho_v2_list (campuses, contacts) unchanged.';
comment on function public.zoho_v3_statistics(text, jsonb, integer, integer) is 'Zoho API v3: public.zoho_v2_statistics unchanged.';
comment on function public.zoho_v3_report(jsonb) is 'Zoho API v3: public.zoho_v2_report unchanged (the same flags as v2).';
comment on function public.zoho_v3_report_status(jsonb) is 'Zoho API v3: public.zoho_v2_report_status unchanged.';
comment on function public.zoho_v3_sync(text, boolean, text[], integer) is 'Zoho API v3: public.zoho_v2_sync unchanged in this release (the sync record is built from v2 items).';
comment on function public.zoho_v3_export_page(text, integer) is 'Zoho API v3: public.zoho_v2_export_page unchanged in this release (the v2 CSV).';

do $g$
declare f text;
begin
  foreach f in array array['public.zoho_v3_scholarships_top(uuid[])', 'public.zoho_v3_course_search(jsonb,integer,integer,text)', 'public.zoho_v3_course(text,text)', 'public.zoho_v3_courses(text[])',
      'public.zoho_v3_passthrough(text,jsonb,integer,integer,text,jsonb)', 'public.zoho_v3_reference()', 'public.zoho_v3_providers(jsonb,integer,integer,text)', 'public.zoho_v3_provider(text)',
      'public.zoho_v3_list(text,jsonb,integer,integer)', 'public.zoho_v3_statistics(text,jsonb,integer,integer)', 'public.zoho_v3_report(jsonb)', 'public.zoho_v3_report_status(jsonb)',
      'public.zoho_v3_sync(text,boolean,text[],integer)', 'public.zoho_v3_export_page(text,integer)'] loop
    execute format('revoke all on function %s from public, anon, authenticated', f);
    execute format('grant execute on function %s to service_role', f);
  end loop;
end $g$;

do $post$
begin
  if exists (select 1 from public.zoho_v3_scholarships_top(null)) then raise exception 'post-check: no course, no scholarships'; end if;
  -- the summary's fields equal the scholarship action's, for every scholarship of the first courses that hold any
  if exists (select 1 from public.zoho_v3_scholarships_top(array(select d.course_id from search.course_documents d where jsonb_array_length(coalesce(d.scholarship_options, '[]'::jsonb)) > 0 order by d.course_stable_key limit 5)) c  -- fixed: a small apply-time sample
              cross join lateral jsonb_array_elements(c.top) t(x)
              join scholarship.scholarships s on s.stable_key = t.x->>'scholarship_id'
              cross join lateral (select api.website_v2_scholarship_item(s.id) i) w
             where (w.i -> 'scholarship_id', w.i -> 'name', w.i -> 'amount_type', w.i -> 'amount_value', w.i -> 'amount_currency')
                   is distinct from (t.x -> 'scholarship_id', t.x -> 'name', t.x -> 'amount_type', t.x -> 'amount_value', t.x -> 'amount_currency')) then
    raise exception 'post-check: the scholarship summary differs from the scholarship item';
  end if;
  if (select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'zoho\_v3\_%') <> 14 then raise exception 'post-check: fourteen zoho_v3 functions'; end if;
end $post$;
