-- CF-247 s955 (session S1-API-Frontend-Delivery, Lane 1 item 1; Platform Admin 21 Nov 2026 21:15 AEDT brief and 21:45 AEDT answer): Zoho API v3
-- course export gains the English tests the platform holds beyond IELTS and PTE (REQ-34, register Z2), and the Zoho sync countries become
-- Australia, New Zealand and Canada (REQ-35, register Z3).
--
-- Z2: public.zoho_v3_export_page was a pass-through to public.zoho_v2_export_page. For the course file it now builds its own page, with the same
--   rows, order, paging and v2 columns (unchanged, first and in the same order), then nine columns added at the end:
--   toefl_ibt_overall, toefl_ibt_band, cae_overall, cae_band, det_overall, oet_overall, oet_band, oet_grade, oet_subtest_grades.
--   Scores come from the course item's english_requirements (the lowest for that test code), as ielts_overall does; the OET letter grade and the
--   subtest grades come from the course's active OET requirement (catalogue.course_english_requirements score_grade, subtest_grades). An empty
--   cell means not held. Read live 21 Nov 2026 21:40 AEDT: of 24,013 course items, TOEFL iBT is held on 3,100, Cambridge C1 Advanced 1,082,
--   Duolingo 412, OET 256 (no OET letter grade is stored yet). Provider, campus and contact files are the v2 answer, unchanged.
--   Zoho API v2 (public.zoho_v2_*, zoho-api-v2) is read only, never changed.
-- Z3: pipeline setting zoho.sync_countries ["AU"] becomes ["AU","NZ","CA"] (Platform Admin 21 Nov 2026 21:45 AEDT: "Enable NZ and CA now").
--   The setting is shared by Zoho v2 and v3: the change stream and both CSV exports include New Zealand and Canada providers, campuses,
--   contacts and courses from the next zoho-sync-check cycles (paced by batch.zoho_sync_check). Read live: search holds 6,514 NZ and 3,825 CA
--   courses. This is a value, not a shape: no function, table or column of the consumer API changes (G3).
-- Live on deploy. $0: no model, no Firecrawl. G1: no new job. G2: no new value written into code (the CSV columns are the API contract).
-- Parity: live head 20261122020000 read 21 Nov 2026 21:40 AEDT; this file is numbered strictly above it.
-- Replaces: the pass-through public.zoho_v3_export_page (same function, same arguments).
-- Retires: nothing. Nothing dropped, deleted or renamed.
set local lock_timeout = '5s';
set local statement_timeout = '120s';  -- fixed: the post-check builds two export pages

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('public.zoho_v3_export_page(text,integer)'::regprocedure)) <> md5(E'CREATE OR REPLACE FUNCTION public.zoho_v3_export_page(p_entity text, p_page integer)\n RETURNS jsonb\n LANGUAGE sql\n SECURITY DEFINER\n SET search_path TO \'\'\nAS $function$ select public.zoho_v2_export_page(p_entity, p_page) $function$\n') then
    raise exception 'guard: live public.zoho_v3_export_page is not the pass-through this change replaces';
  end if;
end $g$;
create temp table s955_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s955_cron on commit drop as select count(*) n from cron.job where active;
create temp table s955_v2 on commit drop as select md5(pg_get_functiondef('public.zoho_v2_export_page(text,integer)'::regprocedure)) m;

-- the lowest score a course item holds for one English test (numeric order; v2 compares the text), as text; null when the test is not held
create or replace function security.zoho_v3_english_score_v1(p_item jsonb, p_test text, p_field text) returns text
language sql immutable set search_path = '' as $f$
  select min((e->>p_field)::numeric)::text from jsonb_array_elements(coalesce(p_item->'english_requirements', '[]'::jsonb)) e
   where e->>'test_code' = p_test and e->>p_field ~ '^[0-9]+(\.[0-9]+)?$'
$f$;
comment on function security.zoho_v3_english_score_v1(jsonb, text, text) is
  'CF-247 s955 (REQ-34, Z2): the lowest score (overall or band) a Zoho course item holds for one English test code, for the Zoho API v3 course export; null when not held.';

create or replace function public.zoho_v3_export_page(p_entity text, p_page integer) returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_csv text; v_n bigint; v_total bigint; v_off bigint; v_head text;
        v_at bigint;
        v_lim int := greatest(security.pipeline_num_v1('zoho.export_page_rows', 3000)::int, 1);
        v_oet uuid := (select t.id from ref.english_tests t where t.code = 'OET');  -- fixed: API contract (REQ-34: OET grade columns)
begin
  if p_entity is distinct from 'course' then return public.zoho_v2_export_page(p_entity, p_page); end if;
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  if coalesce(p_page, 1) < 1 then raise exception 'INVALID_INPUT: page must be 1 or more' using errcode = '22023'; end if;
  v_at := (select coalesce(max(z.seq), 0) from pipeline.zoho_sync_items z);
  v_off := (coalesce(p_page, 1) - 1)::bigint * v_lim;
  select count(*) into v_total from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null and z.item is not null;
  -- the v2 course columns, unchanged and in the same order, then the v3 English test columns (REQ-34, Z2)
  v_head := 'course_id,cricos_course_code,title,provider_id,cricos_provider_code,provider_name,study_level,study_area,country_code,states,campus_cities,delivery_modes,duration_months,intake_months,ielts_overall,ielts_band,pte_overall,tuition_annual,tuition_currency,tuition_year,official_url,scholarship_count'
         || ',toefl_ibt_overall,toefl_ibt_band,cae_overall,cae_band,det_overall,oet_overall,oet_band,oet_grade,oet_subtest_grades';
  select count(*), string_agg(concat_ws(',', security.zoho_v2_csv_v1(i->>'course_id'), security.zoho_v2_csv_v1(i->>'cricos_course_code'), security.zoho_v2_csv_v1(i->>'title'),
           security.zoho_v2_csv_v1(i->'provider'->>'provider_id'), security.zoho_v2_csv_v1(i->'provider'->>'cricos_provider_code'), security.zoho_v2_csv_v1(i->'provider'->>'name'),
           security.zoho_v2_csv_v1(i->'study_level'->>'name'), security.zoho_v2_csv_v1(i->'study_area'->>'name'), security.zoho_v2_csv_v1(i->>'country_code'),
           security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'subdivision_codes', '[]'::jsonb)) x)),
           security.zoho_v2_csv_v1((select string_agg(distinct c->>'city', '; ') from jsonb_array_elements(coalesce(i->'campuses', '[]'::jsonb)) c)),
           security.zoho_v2_csv_v1((select string_agg(x, '; ') from jsonb_array_elements_text(coalesce(i->'delivery_modes', '[]'::jsonb)) x)),
           security.zoho_v2_csv_v1(i->>'duration_months'),
           security.zoho_v2_csv_v1((select string_agg(distinct coalesce(n->>'label', n->>'month'), '; ') from jsonb_array_elements(coalesce(i->'intakes', '[]'::jsonb)) n)),
           security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
           security.zoho_v2_csv_v1((select min(e->>'min_band_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'IELTS')),
           security.zoho_v2_csv_v1((select min(e->>'min_overall_score') from jsonb_array_elements(coalesce(i->'english_requirements', '[]'::jsonb)) e where e->>'test_code' = 'PTE')),
           security.zoho_v2_csv_v1(i->'tuition'->>'annual_amount'), security.zoho_v2_csv_v1(i->'tuition'->>'currency'), security.zoho_v2_csv_v1(i->'tuition'->>'year'),
           security.zoho_v2_csv_v1(i->>'official_url'), security.zoho_v2_csv_v1(i->>'scholarship_count'),
           security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'TOEFL_IBT', 'min_overall_score')), security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'TOEFL_IBT', 'min_band_score')),
           security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'CAE', 'min_overall_score')), security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'CAE', 'min_band_score')),
           security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'DET', 'min_overall_score')),
           security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'OET', 'min_overall_score')), security.zoho_v2_csv_v1(security.zoho_v3_english_score_v1(i, 'OET', 'min_band_score')),
           security.zoho_v2_csv_v1(o.grades), security.zoho_v2_csv_v1(o.subtests)
         ), E'\n' order by i->'provider'->>'name', i->>'title', k)
    into v_n, v_csv
    from (select z.item i, z.item_key k from pipeline.zoho_sync_items z where z.entity = 'course' and z.removed_at is null and z.item is not null
           order by z.item->'provider'->>'name', z.item->>'title', z.item_key limit v_lim offset v_off) x
    -- the OET letter grades and subtest grades of the page's courses, read once for the page (course item key -> search record -> requirement)
    left join (select d.course_stable_key sk,
                      string_agg(distinct r.score_grade, '; ') filter (where r.score_grade is not null) grades,
                      string_agg(distinct l.g, '; ') filter (where l.g is not null) subtests
                 from catalogue.course_english_requirements r
                 join search.course_documents d on d.course_id = r.course_id
                 left join lateral (select case jsonb_typeof(r.subtest_grades)
                                             when 'object' then (select string_agg(k.key || ' ' || (r.subtest_grades->>k.key), ', ' order by k.key) from jsonb_each(r.subtest_grades) k)
                                             when 'array' then (select string_agg(a, ', ') from jsonb_array_elements_text(r.subtest_grades) a)
                                             else r.subtest_grades #>> '{}' end g) l on true
                where r.english_test_id = v_oet and r.status = 'active' and (r.score_grade is not null or r.subtest_grades is not null)
                group by d.course_stable_key) o on o.sk = x.i->>'course_id';
  return jsonb_build_object('api_version', 'zoho-v3', 'entity', 'course', 'rows', coalesce(v_n, 0),
    'page', coalesce(p_page, 1), 'pages', greatest(ceil(v_total::numeric / v_lim), 1)::int, 'total_rows', v_total,
    'has_more', v_off + coalesce(v_n, 0) < v_total,
    'countries', coalesce((select s.value from pipeline.platform_toolset_settings s where s.toolset_key = 'pipeline' and s.key = 'zoho.sync_countries'), '["AU"]'::jsonb),
    'complete', (select s.last_cycle_at is not null from pipeline.zoho_sync_scan s where s.entity = 'course'),
    'sync_cursor', rtrim(translate(replace(encode(convert_to(jsonb_build_object('v', 1, 'm', 'delta', 'a', v_at,
                     'e', jsonb_build_array('provider', 'campus', 'contact', 'course'))::text, 'utf8'), 'base64'), E'\n', ''), '+/', '-_'), '='),
    'csv', v_head || E'\n' || coalesce(v_csv || E'\n', ''));
end $f$;
comment on function public.zoho_v3_export_page(text, integer) is
  'Zoho API v3 export, one page. Course: the v2 course columns unchanged, then toefl_ibt_overall, toefl_ibt_band, cae_overall, cae_band, det_overall, oet_overall, oet_band, oet_grade, oet_subtest_grades (CF-247 s955, REQ-34, Z2; empty means not held). Provider, campus and contact: the v2 answer.';
revoke all on function public.zoho_v3_export_page(text, integer) from public, anon, authenticated;
grant execute on function public.zoho_v3_export_page(text, integer) to service_role;
revoke all on function security.zoho_v3_english_score_v1(jsonb, text, text) from public, anon, authenticated;

-- Z3 (REQ-35): New Zealand and Canada join the Zoho change stream and CSV
update pipeline.platform_toolset_settings
   set value = '["AU", "NZ", "CA"]'::jsonb, updated_at = now(),
       reason = 'CF-247 s955 (Platform Admin 21 Nov 2026 21:45 AEDT, REQ-35 / Z3: "Enable NZ and CA now"); was ["AU"] (Platform Admin 16 Oct 2026: Dhivya, "Australia only for now")'
 where toolset_key = 'pipeline' and key = 'zoho.sync_countries' and value = '["AU"]'::jsonb;

do $c$
declare v_api jsonb; v jsonb; v1 text; v_h text; v_t0 timestamptz;
begin
  if (select value from pipeline.platform_toolset_settings where toolset_key = 'pipeline' and key = 'zoho.sync_countries') <> '["AU", "NZ", "CA"]'::jsonb then
    raise exception 'post-check: zoho.sync_countries is not AU, NZ, CA';
  end if;
  if md5(pg_get_functiondef('public.zoho_v2_export_page(text,integer)'::regprocedure)) <> (select m from s955_v2) then raise exception 'post-check: Zoho v2 export changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s955_cron) then raise exception 'post-check: the number of active cron jobs changed'; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s955_locks) then raise exception 'post-check: the manual locks changed'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
  -- the course page keeps every v2 column first and in order, and the same rows as v2 on the same page
  v_t0 := clock_timestamp();
  v := public.zoho_v3_export_page('course', 1);
  v1 := split_part(public.zoho_v2_export_page('course', 1)->>'csv', E'\n', 1);
  v_h := split_part(v->>'csv', E'\n', 1);
  if left(v_h, length(v1) + 1) <> v1 || ',' then raise exception 'post-check: the v3 course header does not start with the v2 header: % / %', v_h, v1; end if;
  if (v->>'rows')::int <> (public.zoho_v2_export_page('course', 1)->>'rows')::int then raise exception 'post-check: v3 and v2 course pages differ in rows'; end if;
  if public.zoho_v3_export_page('provider', 1) <> public.zoho_v2_export_page('provider', 1) then raise exception 'post-check: the provider file is not the v2 answer'; end if;
  raise notice 's955: course page 1 % rows in % ms; header %; countries %', v->>'rows', round(extract(epoch from clock_timestamp() - v_t0) * 1000), v_h, v->'countries';
end $c$;
