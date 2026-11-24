-- CF-247 s1056 (S1-Build; Platform Admin 24 Nov 2026 21:35 AEDT, FEE-FU-01 "Feedback-4 fee reconciliation and consistent fee selection"; Admin #978).
-- Found live (rolled back, 24 Nov 2026 21:40 to 22:05 AEDT):
--   * public.ui_course_detail returns every catalogue.course_fees row for the course, active and superseded alike, with no status, source,
--     evidence, campus or load, so screens pick a fee by their own rules (Admin #978 root cause).
--   * VU EBCL 105139H holds one provider row, 2027 AUD 33,800 basis indicative_annual. The AI fee reader's own note on that row (stored page
--     evidence 9d883905, 26 Oct) reads "from 33800 to 35500 ... yearly estimate from 16900 per term x full-time load". The official page gives
--     AUD 16,900 a semester for 2026 and AUD 17,750 a semester for 2027 (Admin #978 audit): 33,800 is the 2026 annual equivalent, so the year is
--     wrong, and 2027 is 35,500. 115486F (the other registration) holds only its own CRICOS total and is left as it is.
--   * VU Nursing 080229E holds only CRICOS rows (total tuition 134,458); no provider tuition is stored. Its official international page is not a
--     registered fee page.
-- What changes (live on deploy):
--   1. security.course_fee_selected_v1(course, audience, year): the one governed fee selection. Active rows only. Annual tuition is a provider row
--      of basis annual (provider published) or indicative_annual (calculated equivalent), for the asked year only, never another year; with no
--      year asked, the earliest year from the current Melbourne year on, else the latest earlier year marked past. CRICOS total tuition,
--      non-tuition (zero kept as zero) and estimated total course cost are returned separately and are never annual tuition. Several campuses or
--      amounts for one year are returned as campus_differs or conflict, not picked. Nothing found is the explicit state missing.
--   2. public.ui_course_detail: "fees" keeps its keys and adds status, source key, evidence, campus, load and verified date, for active rows only
--      (superseded history stays in Admin evidence); new key "fee_selected" carries course_fee_selected_v1. Internal read (not a G3 object).
--   3. 105139H: the wrong-year row is superseded (kept as history) and replaced by 2026 AUD 33,800 and 2027 AUD 35,500 calculated annual
--      equivalents on the same stored evidence, unless the field is manually locked.
--   4. The VU Nursing and EBCL international pages are registered as fee pages (manual, $0 direct read first) and Adelaide's 2027 guide is set to
--      be read again directly (its first direct read parsed 109 rows; the later scrape copy parsed none), for the fee reader's existing route.
-- G1: no job. G2: no operational value (the corrected amounts are the provider's published facts). G3: no consumer object changed (checked).
-- Replaces: the unfiltered fee array of public.ui_course_detail.
-- Retires: nothing. Nothing dropped or deleted (the wrong-year row is superseded, not removed).
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the consumer API check

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s1056_locks on commit drop as select count(*) n from pipeline.manual_locks;

CREATE OR REPLACE FUNCTION security.course_fee_selected_v1(p_course_id uuid, p_audience text DEFAULT 'international', p_year integer DEFAULT NULL)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_now int := extract(year from (now() at time zone 'Australia/Melbourne'))::int; v_year int; v_rows jsonb; v_state text; v_sel jsonb; v_c jsonb;
begin
  -- candidate annual tuition rows: active, this audience, a provider row whose basis is annual or a calculated annual equivalent
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'fee_year', f.fee_year, 'amount', f.amount, 'currency', f.currency_code, 'basis', f.basis, 'campus_id', f.campus_id,
                                               'load_basis', f.load_basis, 'evidence', f.evidence_id is not null, 'verified', coalesce(f.last_verified_at, f.updated_at))), '[]'::jsonb)
    into v_c from catalogue.course_fees f
   where f.course_id = p_course_id and f.status = 'active' and coalesce(f.audience, p_audience) = p_audience
     and f.fee_type = 'provider_current_tuition' and f.basis in ('annual', 'indicative_annual') and f.amount > 0;
  if p_year is not null then v_year := p_year;
  else
    select coalesce(min(fee_year) filter (where fee_year >= v_now), max(fee_year)) into v_year from jsonb_to_recordset(v_c) as c(id uuid, fee_year int, amount numeric, currency text, basis text, campus_id uuid, load_basis text, evidence boolean, verified timestamptz);
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('amount', amount, 'currency', currency, 'year', fee_year, 'basis', basis, 'campus_id', campus_id, 'load_basis', load_basis,
                                               'kind', case when basis = 'annual' then 'provider_published' else 'calculated_equivalent' end,
                                               'evidence', evidence, 'verified_at', verified, 'fee_id', id) order by basis, amount), '[]'::jsonb)
    into v_rows from jsonb_to_recordset(v_c) as c(id uuid, fee_year int, amount numeric, currency text, basis text, campus_id uuid, load_basis text, evidence boolean, verified timestamptz) where fee_year is not distinct from v_year and v_year is not null;
  v_state := case
    when jsonb_array_length(v_rows) = 0 and exists (select 1 from jsonb_to_recordset(v_c) as c(id uuid, fee_year int, amount numeric, currency text, basis text, campus_id uuid, load_basis text, evidence boolean, verified timestamptz) where fee_year is null) and p_year is null then 'year_unstated'
    when jsonb_array_length(v_rows) = 0 then 'missing'
    when (select count(distinct x->>'campus_id') from jsonb_array_elements(v_rows) x) > 1 then 'campus_differs'
    when (select count(distinct (x->>'amount')::numeric) from jsonb_array_elements(v_rows) x where x->>'kind' = (select y->>'kind' from jsonb_array_elements(v_rows) y order by (y->>'kind' <> 'provider_published') limit 1)) > 1 then 'conflict'
    when v_year < v_now then 'past_year'
    else 'selected' end;
  v_sel := case when v_state in ('selected', 'past_year') then (select x from jsonb_array_elements(v_rows) x order by (x->>'kind' <> 'provider_published'), (x->>'verified_at') desc limit 1) end;
  return jsonb_build_object(
    'state', v_state, 'audience', p_audience, 'year_asked', p_year, 'year', case when jsonb_array_length(v_rows) > 0 then v_year end,
    'annual_tuition', v_sel, 'candidates', case when v_state in ('campus_differs', 'conflict') then v_rows else '[]'::jsonb end,
    'years_held', coalesce((select jsonb_agg(distinct fee_year) from jsonb_to_recordset(v_c) as c(id uuid, fee_year int, amount numeric, currency text, basis text, campus_id uuid, load_basis text, evidence boolean, verified timestamptz) where fee_year is not null), '[]'::jsonb),
    'cricos_total_tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code, 'evidence', f.evidence_id is not null) from catalogue.course_fees f
                              where f.course_id = p_course_id and f.status = 'active' and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and coalesce(f.audience, p_audience) = p_audience order by f.updated_at desc limit 1),
    'non_tuition', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code) from catalogue.course_fees f
                     where f.course_id = p_course_id and f.status = 'active' and f.fee_type = 'non_tuition' and coalesce(f.audience, p_audience) = p_audience order by f.updated_at desc limit 1),
    'estimated_total_course_cost', (select jsonb_build_object('amount', f.amount, 'currency', f.currency_code) from catalogue.course_fees f
                     where f.course_id = p_course_id and f.status = 'active' and f.fee_type = 'estimated_total_course_cost' and coalesce(f.audience, p_audience) = p_audience order by f.updated_at desc limit 1),
    'official_url', (select cl.url from catalogue.course_links cl where cl.course_id = p_course_id and cl.link_type = 'official_course' and coalesce(cl.status, 'active') = 'active' order by cl.last_verified_at desc nulls last limit 1),
    'contract', 'course_fee_selected_v1');
end $function$;
comment on function security.course_fee_selected_v1(uuid, text, integer) is 'CF-247 s1056 (FEE-FU-01): the one governed course fee selection for every screen. Active rows only; annual tuition only from a provider row of basis annual (provider_published) or indicative_annual (calculated_equivalent) for the asked year, never another year; CRICOS total tuition, non-tuition and estimated total cost separate and never annual; campus_differs, conflict, year_unstated, past_year and missing are explicit states.';
revoke all on function security.course_fee_selected_v1(uuid, text, integer) from public, anon;
grant execute on function security.course_fee_selected_v1(uuid, text, integer) to authenticated;

-- 2. the internal course detail read: active fee rows with their provenance, and the governed selection beside them
do $ui$
declare d text := pg_get_functiondef('public.ui_course_detail(uuid)'::regprocedure);
  v_old constant text := $o$'fees', coalesce((select jsonb_agg(jsonb_build_object('year',f.fee_year,'audience',f.audience,'type',f.fee_type,'amount',f.amount,'currency',f.currency_code,'basis',f.basis,'csp',f.is_csp) order by f.fee_year desc, f.audience) from catalogue.course_fees f where f.course_id=c.id), '[]'::jsonb),$o$;
  v_new constant text := $n$'fees', coalesce((select jsonb_agg(jsonb_build_object('year',f.fee_year,'audience',f.audience,'type',f.fee_type,'amount',f.amount,'currency',f.currency_code,'basis',f.basis,'csp',f.is_csp,'status',f.status,'load_basis',f.load_basis,'campus_id',f.campus_id,'source_key',f.source_fee_key,'evidence',f.evidence_id is not null,'verified_at',coalesce(f.last_verified_at,f.updated_at)) order by f.fee_year desc nulls last, f.audience) from catalogue.course_fees f where f.course_id=c.id and f.status='active'), '[]'::jsonb),
    'fee_selected', security.course_fee_selected_v1(c.id, 'international', null),$n$;
begin
  if (length(d) - length(replace(d, v_old, ''))) / length(v_old) <> 1 then
    raise exception 's1056: public.ui_course_detail does not hold the fee array this change replaces (exactly once)';
  end if;
  execute replace(d, v_old, v_new);
end $ui$;

-- 3. VU EBCL 105139H: the 2026 annual equivalent was labelled 2027; 2027 is 35,500
do $ebcl$
declare r record; v_course uuid; v_n int := 0;
begin
  select c.id into v_course from catalogue.courses c where c.course_code = '105139H' and c.provider_id = 'bac82321-ded7-4e10-a71d-b18f3ae4d1c7' and c.lifecycle_status = 'active';
  if v_course is null then raise notice 's1056: 105139H not found; nothing changed'; return; end if;
  if exists (select 1 from pipeline.manual_locks l where l.entity_id = v_course and l.field in ('provider_tuition', 'provider_current_tuition', 'fees')) then
    raise notice 's1056: 105139H provider tuition is manually locked; nothing changed'; return;
  end if;
  select * into r from catalogue.course_fees f where f.course_id = v_course and f.status = 'active' and f.fee_type = 'provider_current_tuition'
     and f.fee_year = 2027 and f.amount = 33800 and f.basis = 'indicative_annual' and f.notes ~ '16900 per term';
  if r.id is null then raise notice 's1056: the 105139H row is no longer the wrong-year row; nothing changed'; return; end if;
  update catalogue.course_fees set status = 'superseded', notes = coalesce(notes, '') || ' | CF-247 s1056: superseded, the 2026 annual equivalent (16,900 a semester) was labelled 2027 (Feedback 4, FEE-FU-01).', updated_at = now()
   where id = r.id;
  insert into catalogue.course_fees(course_id, fee_year, audience, fee_type, amount, currency_code, basis, load_basis, is_csp, notes, source_id, evidence_id, confidence, campus_id, source_fee_key, status, last_verified_at)
  values
    (v_course, 2026, r.audience, 'provider_current_tuition', 33800, r.currency_code, 'indicative_annual', 'full_time', r.is_csp,
     'Calculated annual equivalent: AUD 16,900 a semester (2026) x 2 semesters, full-time; official international page (CF-247 s1056, Feedback 4)', r.source_id, r.evidence_id, 0.9, r.campus_id,
     '105139h:international:2026:indicative_annual:s1056', 'active', now()),
    (v_course, 2027, r.audience, 'provider_current_tuition', 35500, r.currency_code, 'indicative_annual', 'full_time', r.is_csp,
     'Calculated annual equivalent: AUD 17,750 a semester (2027) x 2 semesters, full-time; official international page (CF-247 s1056, Feedback 4)', r.source_id, r.evidence_id, 0.9, r.campus_id,
     '105139h:international:2027:indicative_annual:s1056', 'active', now())
  on conflict do nothing;
  get diagnostics v_n = row_count;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('fees', 'year_correction', v_course::text, jsonb_build_object('superseded', r.id, 'added', v_n, 'course', '105139H',
          'approved_by', 'Platform Admin (chat, 24 Nov 2026 21:35 AEDT, FEE-FU-01)', 'via', 'CF-247 s1056 migration'), null);
end $ebcl$;

-- 4. official fee pages for the fee reader's existing route ($0 direct read first)
do $pages$
declare r record; v_approval text := 'Platform Admin (chat, 24 Nov 2026 21:35 AEDT, FEE-FU-01)';
begin
  for r in select * from (values
      ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid, 'https://www.vu.edu.au/courses/bachelor-of-nursing-hbnb/international'),
      ('bac82321-ded7-4e10-a71d-b18f3ae4d1c7'::uuid, 'https://www.vu.edu.au/courses/bachelor-of-early-childhood-education-and-leadership-ebcl/international'),
      ('de2201a1-69ee-40ff-b6aa-0e54e535e6c0'::uuid, 'https://adelaide.edu.au/content/dam/adelaideuniversity/documents/about/pdfs/2027-international-student-guide.pdf')
    ) x(provider_id, url) loop
    insert into pipeline.provider_fact_sources(provider_id, kind, url, title, rank, found_via, status)
    values (r.provider_id, 'fee_schedule', r.url, null, 9, 'manual', 'found')
    on conflict (provider_id, kind, url) do update set status = 'found', attempts = 0, rank = 9, found_via = 'manual', updated_at = now();
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('fees', 'page_add', r.provider_id::text, jsonb_build_object('url', r.url, 'reason', 'Feedback 4 fee reconciliation: read directly by the fee reader', 'approved_by', v_approval, 'via', 'CF-247 s1056 migration'), null);
  end loop;
end $pages$;

do $c$
declare v_api jsonb; v jsonb;
begin
  v := security.course_fee_selected_v1((select id from catalogue.courses where course_code = '075119J' and lifecycle_status = 'active' limit 1), 'international', 2027);
  if v->>'state' <> 'selected' or (v->'annual_tuition'->>'amount')::numeric <> 47340 then raise exception 'post-check: Monash Nursing 2027 is not selected as 47,340: %', v; end if;
  v := security.course_fee_selected_v1((select id from catalogue.courses where course_code = '080229E' and lifecycle_status = 'active' limit 1), 'international', null);
  if v->>'state' <> 'missing' or (v->'cricos_total_tuition'->>'amount')::numeric <> 134458 then raise exception 'post-check: VU Nursing shows CRICOS total as annual or lost it: %', v; end if;
  v := security.course_fee_selected_v1((select id from catalogue.courses where course_code = '105139H' and lifecycle_status = 'active' limit 1), 'international', 2027);
  if (v->'annual_tuition'->>'amount')::numeric is distinct from 35500 then raise exception 'post-check: EBCL 2027 is not 35,500: %', v; end if;
  v := security.course_fee_selected_v1((select id from catalogue.courses where course_code = '105139H' and lifecycle_status = 'active' limit 1), 'international', 2026);
  if (v->'annual_tuition'->>'amount')::numeric is distinct from 33800 then raise exception 'post-check: EBCL 2026 is not 33,800: %', v; end if;
  if exists (select 1 from jsonb_array_elements(public.ui_course_detail((select id from catalogue.courses where course_code = '075119J' and lifecycle_status = 'active' limit 1))->'fees') x where x->>'status' <> 'active') then
    raise exception 'post-check: the course detail still returns superseded fees';
  end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1056_locks) then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'post-check: more than 140 active cron jobs'; end if;
  v_api := security.consumer_api_check_v1();
  if jsonb_array_length(coalesce(v_api->'drift', '[]'::jsonb)) <> 0 or (v_api->>'functions')::int <> 75 or (v_api->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v_api;
  end if;
end $c$;
