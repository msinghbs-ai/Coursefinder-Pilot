-- CF-247 s790 and s791, IQ-00313 / F-INT (Platform Admin 19 Nov 2026 23:12 and 23:21 AEDT, chat S1-Build): Course intake Run & Validate.
--   PAGE-01: any AU, NZ or CA provider paged through all its active courses (scope university:<id>[:page:<n>]), and hand-picked courses
--            (scope courses:<id>,...); was: the top 10 AU universities with a bounded scan of a few rows each.
--   OPS-01:  durable stage counts for each cohort and run (fetched, parsed, extracted when the cohort is fixed; verified, admitted, held after
--            each run, with its run id) in pipeline.intake_cohort_stages; the verify view returns them.
--   VERIFY-01: a hand-picked cohort is the human Verify / Admit path: the preview shows each intake's stored evidence, before and planned values;
--            Run Now admits through the existing intake-dates-apply job (its no-overwrite update, manual-lock trigger and same-month guard are
--            unchanged; /dates, /calendar and /timetable rules stay in intake_dates_plan_v3); verify reads the catalogue, website and Zoho back.
-- Pre-flight parity (read live 20 Nov 2026 00:15 AEDT): history head 20261119182000; versions after the baseline cut-off = supabase/migrations
-- one to one; Pilot #1397 (20261119190000) and #1398 (20261119191000) are open, so this is numbered above both.
-- G3: no consumer table, view or function is created or changed; the public functions edited are admin_* operator bridges (not consumer API);
-- the new table and functions are in schemas pipeline and security. No spend (planning reads stored pages and approved calendars only).
-- Replaces: the fixed top-10 scope as the only way in (kept, and still the default). Retires: nothing.

-- G2: the page size of a provider's course list
insert into pipeline.platform_toolset_settings (toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason)
values ('pipeline', 'run_now.university_page_courses', 'Intake Run & Validate: courses a page',
        'How many of a provider''s active courses one page of Course intake Run & Validate plans at once (scope university:<id>:page:<n>). Pages cover every active course.',
        'number', '200'::jsonb, 20, 1000, 'courses', 1108, 'Run now',
        'security.intake_ui_selection_wide_v1 and admin_intake_run_read_v1 (views capabilities and universities)',
        'CF-247 s790 PAGE-01 (Platform Admin 19 Nov 2026 23:12): page a whole provider')
on conflict do nothing;

create table if not exists pipeline.intake_cohort_stages (
  id bigint generated always as identity primary key,
  cohort_id uuid not null references pipeline.run_now_cohorts(id),
  run_id uuid,
  stage text not null check (stage in ('fetched', 'parsed', 'extracted', 'verified', 'admitted', 'held')),
  courses integer not null,
  intakes integer not null,
  recorded_at timestamptz not null default now()
);
comment on table pipeline.intake_cohort_stages is
  'CF-247 s791 OPS-01: stage counts of a Course intake Run & Validate cohort. fetched, parsed and extracted are written when the cohort is fixed (run_id null); verified, admitted and held after each Run Now (with its admin_jobs run id). Written only by security.intake_cohort_stages_record_v1; never updated or deleted.';
create index if not exists intake_cohort_stages_cohort_idx on pipeline.intake_cohort_stages (cohort_id, recorded_at);
alter table pipeline.intake_cohort_stages enable row level security;
revoke all on pipeline.intake_cohort_stages from public, anon, authenticated;

create or replace function security.intake_cohort_stages_record_v1(p_cohort uuid, p_run uuid)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_at timestamptz := (select created_at from pipeline.run_now_cohorts where id = p_cohort); v_since timestamptz; v_rows jsonb;
begin
  if v_at is null then raise exception 'unknown cohort'; end if;
  if p_run is null then
    -- at selection: what the stored evidence held for each picked intake
    with x as (select m.course_id, nullif(e->>'page_url', '') is not null fetched,
                      nullif(btrim(coalesce(e->>'page_quote', '')), '') is not null parsed,
                      coalesce(jsonb_strip_nulls(e->'planned'), '{}'::jsonb) <> '{}'::jsonb extracted
                 from pipeline.run_now_cohort_members m cross join lateral jsonb_array_elements(m.evidence) e where m.cohort_id = p_cohort)
    insert into pipeline.intake_cohort_stages (cohort_id, run_id, stage, courses, intakes)
    select p_cohort, null, s.stage,
           (select count(distinct x.course_id) from x where case s.stage when 'fetched' then x.fetched when 'parsed' then x.parsed else x.extracted end),
           (select count(*) from x where case s.stage when 'fetched' then x.fetched when 'parsed' then x.parsed else x.extracted end)
      from (values (1, 'fetched'), (2, 'parsed'), (3, 'extracted')) s(o, stage) order by s.o;
  else
    -- after a run: the intake job's own decisions on the picked intakes since the last count of this cohort (its event log, so each run counts its own)
    v_since := coalesce((select max(recorded_at) from pipeline.intake_cohort_stages where cohort_id = p_cohort and run_id is not null), v_at);
    with x as (select ev.intake_id, min(ev.course_id::text)::uuid course_id, bool_or(ev.outcome = 'filled') filled
                 from pipeline.course_intake_date_events ev
                 join pipeline.run_now_cohort_members m on m.cohort_id = p_cohort and m.course_id = ev.course_id
                where ev.run_at > v_since and ev.intake_id in (select (e->>'intake_id')::uuid from jsonb_array_elements(m.evidence) e)
                group by ev.intake_id)
    insert into pipeline.intake_cohort_stages (cohort_id, run_id, stage, courses, intakes)
    select p_cohort, p_run, s.stage,
           (select count(distinct x.course_id) from x where case s.stage when 'verified' then true when 'admitted' then x.filled else not x.filled end),
           (select count(*) from x where case s.stage when 'verified' then true when 'admitted' then x.filled else not x.filled end)
      from (values (1, 'verified'), (2, 'admitted'), (3, 'held')) s(o, stage) order by s.o;
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('stage', stage, 'courses', courses, 'intakes', intakes) order by id), '[]') into v_rows
    from pipeline.intake_cohort_stages where cohort_id = p_cohort and run_id is not distinct from p_run and recorded_at = now();
  return v_rows;
end $f$;
revoke all on function security.intake_cohort_stages_record_v1(uuid, uuid) from public, anon, authenticated;
comment on function security.intake_cohort_stages_record_v1(uuid, uuid) is 'CF-247 s791 OPS-01: writes the stage counts of an intake cohort (at selection, or after a run).';

-- PAGE-01: a provider paged through all its active courses, or hand-picked courses
create or replace function security.intake_ui_selection_wide_v1(p_scope text, p_size integer)
returns jsonb language plpgsql stable security definer set search_path to '' as $f$
declare cap int := security.pipeline_num_v1('run_now.pilot_cap', 20)::int;
        psz int := security.pipeline_num_v1('run_now.university_page_courses', 200)::int;
        rows_lim int := security.pipeline_num_v1('run_now.cohort_scan_rows', 1500)::int;
        v_pid uuid; v_page int := 1; v_total int; v_pages int; ids uuid[]; v_pick text[]; unis jsonb; result jsonb; v_mode text;
begin
  if p_size is null or p_size < 1 or p_size > cap then raise exception 'cohort size must be between 1 and %', cap; end if;
  if p_scope ~ '^university:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(:page:[1-9][0-9]{0,4})?$' then
    v_mode := 'university'; v_pid := split_part(p_scope, ':', 2)::uuid;
    if p_scope like '%:page:%' then v_page := split_part(p_scope, ':', 4)::int; end if;
    if not exists (select 1 from catalogue.providers p join ref.countries k on k.id = p.country_id
                    where p.id = v_pid and p.lifecycle_status = 'active' and k.iso_alpha2 in ('AU', 'NZ', 'CA')) then
      raise exception 'invalid scope: an active Australian, New Zealand or Canadian provider is required'; end if;
    select count(*) into v_total from catalogue.courses where provider_id = v_pid and lifecycle_status = 'active';
    v_pages := greatest(1, ceil(v_total::numeric / psz)::int);
    if v_page > v_pages then raise exception 'page % is outside 1 to %', v_page, v_pages; end if;
    ids := array(select id from catalogue.courses where provider_id = v_pid and lifecycle_status = 'active'
                  order by md5(id::text), id offset (v_page - 1) * psz limit psz);
  elsif p_scope ~ '^courses:[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}(,[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})*$' then
    v_mode := 'courses'; v_pick := string_to_array(substr(p_scope, 9), ',');
    if cardinality(v_pick) > cap then raise exception 'pick at most % courses', cap; end if;
    ids := array(select distinct c.id from unnest(v_pick::uuid[]) x join catalogue.courses c on c.id = x and c.lifecycle_status = 'active'
                   join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id and k.iso_alpha2 in ('AU', 'NZ', 'CA'));
    if coalesce(cardinality(ids), 0) = 0 then raise exception 'no active Australian, New Zealand or Canadian course in the pick'; end if;
  else
    raise exception 'invalid scope';
  end if;
  unis := (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', coalesce(p.display_name, p.canonical_name),
             'active_courses', (select count(*) from catalogue.courses c2 where c2.provider_id = p.id and c2.lifecycle_status = 'active')) order by coalesce(p.display_name, p.canonical_name)), '[]')
             from catalogue.providers p where p.id in (select c.provider_id from catalogue.courses c where c.id = any (ids)));
  with all_plan as materialized (select p.* from security.intake_dates_plan_v3(ids, rows_lim) p),
  f as (select * from all_plan where outcome = 'filled'),
  c as (select course_id, min(provider_id::text)::uuid provider_id,
          array_remove(array[case when bool_or(new_year is not null) then 'year' end, case when bool_or(new_start is not null) then 'start_date' end,
                             case when bool_or(new_deadline is not null) then 'application_deadline' end], null) fills,
          string_agg(distinct coalesce(start_precision, '-') || '/' || coalesce(deadline_kind, '-'), '+' order by coalesce(start_precision, '-') || '/' || coalesce(deadline_kind, '-')) pattern,
          jsonb_agg(jsonb_build_object('intake_id', intake_id, 'proposal_id', proposal_id, 'calendar_evidence_id', calendar_evidence_id, 'calendar_url', calendar_url,
            'page_url', (select e.source_url from catalogue.course_intakes i join pipeline.evidence_artifacts e on e.id = i.evidence_id where i.id = intake_id),
            'periods', periods, 'page_quote', page_quote, 'start_quote', start_quote, 'deadline_quote', deadline_quote, 'deadline_kind', deadline_kind,
            'before', before_value, 'planned', jsonb_build_object('year', new_year, 'start_date', new_start, 'application_deadline', new_deadline), 'rule', rule) order by intake_id) at_selection
          from f group by course_id),
  r as (select c.*, row_number() over (partition by provider_id order by cardinality(fills) desc, md5(course_id::text)) rp,
          row_number() over (partition by pattern order by cardinality(fills) desc, md5(course_id::text)) rq from c),
  pick as (select r.*, row_number() over (order by rp, rq, cardinality(fills) desc, md5(course_id::text)) n from r)
  select jsonb_build_object('scope', p_scope, 'mode', v_mode, 'size', p_size, 'cap', cap, 'scan_rows', rows_lim,
    'page', case when v_mode = 'university' then v_page end, 'pages', v_pages, 'page_courses', case when v_mode = 'university' then psz end,
    'universities', (select jsonb_agg(u || jsonb_build_object('scan_limit', rows_lim,
        'rows_planned', (select count(*) from all_plan where provider_id = (u->>'id')::uuid),
        'eligible_courses', (select count(distinct course_id) from all_plan where provider_id = (u->>'id')::uuid and outcome = 'filled'),
        'eligible_values', (select count(*) from all_plan where provider_id = (u->>'id')::uuid and outcome = 'filled'))) from jsonb_array_elements(unis) u),
    'scope_courses', cardinality(ids), 'rows_planned', (select count(*) from all_plan),
    'eligible_courses', (select count(distinct course_id) from f), 'rows_eligible', (select count(*) from f),
    'skipped_by_reason', (select coalesce(jsonb_object_agg(reason, n), '{}') from (select coalesce(reason, outcome) reason, count(*) n from all_plan where outcome <> 'filled' group by 1) x),
    'rule', case when v_mode = 'university'
                 then 'Existing intake-dates-plan-v3 filled outcome on page ' || v_page || ' of ' || v_pages || ' of this provider''s active courses (' || psz || ' a page, stable order); official stored page and approved calendar; no scope widening'
                 else 'Existing intake-dates-plan-v3 filled outcome on the hand-picked courses only; official stored page and approved calendar; no scope widening' end,
    'courses', coalesce((select jsonb_agg(jsonb_build_object('course_id', p.course_id, 'provider_id', p.provider_id, 'pick', p.n, 'pattern', p.pattern, 'fills', p.fills,
        'course_title', coalesce(cc.display_title, cc.canonical_title), 'provider_name', coalesce(pp.display_name, pp.canonical_name), 'course_url', cc.course_url,
        'eligibility_reason', 'The existing intake plan found supported missing values from the stored course wording and an approved calendar; its manual-lock, same-month and admission guards remain authoritative.',
        'at_selection', p.at_selection) order by p.n) from pick p join catalogue.courses cc on cc.id = p.course_id join catalogue.providers pp on pp.id = p.provider_id where p.n <= p_size), '[]')) into result;
  return result;
end $f$;
revoke all on function security.intake_ui_selection_wide_v1(text, integer) from public, anon, authenticated;
comment on function security.intake_ui_selection_wide_v1(text, integer) is 'CF-247 s790 PAGE-01: intake cohort selection for a paged provider or hand-picked courses (same plan, guards and output shape as intake_ui_selection_v1).';

create or replace function pg_temp.cf_edit_def(p_sig regprocedure, p_md5 text, p_old text[], p_new text[])
returns void language plpgsql as $f$
declare v_def text := replace(pg_get_functiondef(p_sig), chr(13), ''); v_c int; i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'pre-check: % changed since it was read (definition md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_old, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_old[i], ''))) / length(p_old[i]);
    if v_c <> 1 then raise exception 'pre-check: %: fragment % must occur exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_old[i], p_new[i]);
  end loop;
  execute v_def;
end $f$;

-- the existing selection hands the new scopes to the wide selection; its own scopes are unchanged
select pg_temp.cf_edit_def('security.intake_ui_selection_v1(text,integer)'::regprocedure, '09b38c698f349b885bc0f3ddfeedb010',
  array[$o$ if p_size is null or p_size<1 or p_size>cap then raise exception 'cohort size must be between 1 and %',cap; end if;$o$],
  array[$n$ if p_scope like 'university:%' or p_scope like 'courses:%' then return security.intake_ui_selection_wide_v1(p_scope, p_size); end if;  -- s790 PAGE-01
 if p_size is null or p_size<1 or p_size>cap then raise exception 'cohort size must be between 1 and %',cap; end if;$n$]);

-- OPS-01: stage counts when a cohort is fixed
select pg_temp.cf_edit_def('public.admin_intake_cohort_prepare_v1(text,integer,text,text)'::regprocedure, '8a6d250362cba7319b3e18086073844e',
  array[$o$ insert into pipeline.admin_control_events(area,action,target,detail,actor)
 values('run_now','cohort_prepared'$o$],
  array[$n$ perform security.intake_cohort_stages_record_v1(c, null);  -- s791 OPS-01: fetched, parsed, extracted
 insert into pipeline.admin_control_events(area,action,target,detail,actor)
 values('run_now','cohort_prepared'$n$]);

-- OPS-01: stage counts after each run, with its run id (a failure to count never fails the run)
select pg_temp.cf_edit_def('public.admin_intake_run_now_v1(uuid)'::regprocedure, 'd3f2c2445a955f9c6e71fe0a00ab0608',
  array[$o$ v_result:=public.admin_job_run_now_v1('intake-dates-apply',r.reason,jsonb_build_object('cohort_id',r.cohort_id,'idempotency_key',r.request_key));$o$],
  array[$n$ v_result:=public.admin_job_run_now_v1('intake-dates-apply',r.reason,jsonb_build_object('cohort_id',r.cohort_id,'idempotency_key',r.request_key));
 begin perform security.intake_cohort_stages_record_v1(r.cohort_id, nullif(v_result->>'run_id','')::uuid);  -- s791 OPS-01: verified, admitted, held
 exception when others then raise warning 'intake stage counts not recorded for cohort %: %', r.cohort_id, sqlerrm; end;$n$]);

-- reads: scope forms and page size, every provider paged (views universities and course_search), and the stage history in verify
select pg_temp.cf_edit_def('public.admin_intake_run_read_v1(text,jsonb)'::regprocedure, 'fa7d47a39f1401e54e751fbfe4de29c9',
  array[$o$ 'diagnostic',jsonb_build_object('approved',false));$o$,
        $o$ elsif p_view='preview' then return security.intake_ui_preview_v1(p_args->>'scope',(p_args->>'size')::integer);$o$,
        $o$ 'next_action','Compare catalogue and consumer read-backs$o$],
  array[$n$ 'diagnostic',jsonb_build_object('approved',false),
 'scope_forms',jsonb_build_array('top-au','<provider id>','university:<provider id>:page:<n>','courses:<course id>,<course id>'),
 'page_courses',security.pipeline_num_v1('run_now.university_page_courses',200));$n$,
        $n$ elsif p_view='universities' then  -- s790 PAGE-01: every active AU, NZ and CA provider with active courses, searchable and paged
 return (with v as (select p.id,coalesce(p.display_name,p.canonical_name) name,k.iso_alpha2 cc,t.code tcode,count(c.id) n
             from catalogue.providers p join ref.countries k on k.id=p.country_id and k.iso_alpha2 in ('AU','NZ','CA')
             left join ref.provider_types t on t.id=p.provider_type_id
             join catalogue.courses c on c.provider_id=p.id and c.lifecycle_status='active'
            where p.lifecycle_status='active'
              and (nullif(btrim(p_args->>'q'),'') is null or coalesce(p.display_name,p.canonical_name) ilike '%'||btrim(p_args->>'q')||'%')
              and (nullif(p_args->>'country','') is null or k.iso_alpha2=upper(p_args->>'country'))
            group by p.id,2,3,4),
   pg as (select * from v order by n desc, name, id offset greatest(0,coalesce((p_args->>'offset')::int,0)) limit least(greatest(1,coalesce((p_args->>'limit')::int,25)),50))
   select jsonb_build_object('total',(select count(*) from v),'items',coalesce((select jsonb_agg(jsonb_build_object('id',pg.id,'name',pg.name,'country',pg.cc,'type',pg.tcode,'active_courses',pg.n,
     'pages',greatest(1,ceil(pg.n::numeric/security.pipeline_num_v1('run_now.university_page_courses',200))::int)) order by pg.n desc, pg.name, pg.id) from pg),'[]')));
 elsif p_view='course_search' then  -- s790 PAGE-01: find single courses to pick (title or course code; one provider optional)
 if length(btrim(coalesce(p_args->>'q','')))<3 then raise exception 'type at least 3 characters'; end if;
 return jsonb_build_object('items',coalesce((select jsonb_agg(jsonb_build_object('course_id',x.id,'title',x.title,'code',x.course_code,'provider_id',x.provider_id,'provider',x.provider,'country',x.cc,
   'intakes',x.n_int,'intakes_without_date',x.n_nodate) order by x.title) from (
     select c.id,coalesce(c.display_title,c.canonical_title) title,c.course_code,c.provider_id,coalesce(p.display_name,p.canonical_name) provider,k.iso_alpha2 cc,
            (select count(*) from catalogue.course_intakes i where i.course_id=c.id and i.status='active') n_int,
            (select count(*) from catalogue.course_intakes i where i.course_id=c.id and i.status='active' and i.start_date is null) n_nodate
       from catalogue.courses c join catalogue.providers p on p.id=c.provider_id join ref.countries k on k.id=p.country_id and k.iso_alpha2 in ('AU','NZ','CA')
      where c.lifecycle_status='active'
        and (coalesce(c.display_title,c.canonical_title) ilike '%'||btrim(p_args->>'q')||'%' or c.course_code ilike btrim(p_args->>'q')||'%')
        and (nullif(p_args->>'provider_id','') is null or c.provider_id=(p_args->>'provider_id')::uuid)
      order by 2 limit least(greatest(1,coalesce((p_args->>'limit')::int,20)),security.pipeline_num_v1('run_now.pilot_cap',20)::int)) x),'[]'));
 elsif p_view='preview' then return security.intake_ui_preview_v1(p_args->>'scope',(p_args->>'size')::integer);$n$,
        $n$ 'stage_history',coalesce((select jsonb_agg(jsonb_build_object('run_id',s.run_id,'stage',s.stage,'courses',s.courses,'intakes',s.intakes,'recorded_at',s.recorded_at) order by s.recorded_at,s.id)
   from pipeline.intake_cohort_stages s where s.cohort_id=c),'[]'),  -- s791 OPS-01
 'next_action','Compare catalogue and consumer read-backs$n$]);

-- post-checks (inside this transaction)
do $$
declare v_uni uuid; r jsonb; t timestamptz; v_ms int; v_course uuid; v_o text := '';
begin
  -- the largest AU university: page 1 plans, in time, with the same output shape
  select p.id into v_uni from catalogue.providers p join ref.countries k on k.id = p.country_id and k.iso_alpha2 = 'AU'
    join ref.provider_types ty on ty.id = p.provider_type_id and ty.code = 'university'
    join catalogue.courses c on c.provider_id = p.id and c.lifecycle_status = 'active'
   where p.lifecycle_status = 'active' group by p.id order by count(*) desc limit 1;
  t := clock_timestamp(); r := security.intake_ui_selection_v1('university:' || v_uni || ':page:1', 20); v_ms := round(extract(epoch from clock_timestamp() - t) * 1000);
  if r->>'mode' <> 'university' or (r->>'pages')::int < 1 or (r->>'scope_courses')::int < 1 or jsonb_typeof(r->'courses') <> 'array' then
    raise exception 'post-check: university page selection returned %', left(r::text, 300); end if;
  v_o := format('university page 1 of %s: %s courses planned, %s eligible, %s picked, %s ms', r->>'pages', r->>'scope_courses', r->>'eligible_courses', jsonb_array_length(r->'courses'), v_ms);
  if v_ms > 30000 then raise exception 'post-check: a page took % ms', v_ms; end if;
  -- a hand-picked course
  v_course := coalesce((r->'courses'->0->>'course_id')::uuid, (select c.id from catalogue.courses c where c.provider_id = v_uni and c.lifecycle_status = 'active' limit 1));
  r := security.intake_ui_selection_v1('courses:' || v_course, 1);
  if r->>'mode' <> 'courses' or (r->>'scope_courses')::int <> 1 then raise exception 'post-check: course pick returned %', left(r::text, 300); end if;
  v_o := v_o || format(' | pick of one course: %s eligible', r->>'eligible_courses');
  -- the old scopes still work as before
  r := security.intake_ui_selection_v1('top-au', 1);
  if r ? 'mode' or jsonb_typeof(r->'courses') <> 'array' then raise exception 'post-check: top-au changed shape'; end if;
  -- refusals
  begin perform security.intake_ui_selection_v1('university:' || v_uni || ':page:99999', 1); raise exception 'post-check: page past the end was accepted';
  exception when raise_exception then if sqlerrm not like 'page % is outside%' and sqlerrm not like 'page%outside%' then raise; end if; end;
  -- stage counts on a temporary cohort (rolled back with this transaction only in the dry run; in the real apply nothing is inserted here)
  if (select count(*) from pg_proc where proname = 'intake_cohort_stages_record_v1') <> 1 then raise exception 'post-check: stage recorder missing'; end if;
  if (select count(*) from pipeline.intake_cohort_stages) <> 0 then raise exception 'post-check: stage table is not empty at creation'; end if;
  if exists (select 1 from information_schema.role_table_grants where table_schema = 'pipeline' and table_name = 'intake_cohort_stages' and grantee in ('anon', 'authenticated')) then
    raise exception 'post-check: stage table is granted to a client role'; end if;
  -- the read views and the stage recorder, as a signed-in Platform Admin, in a sub-block that is always rolled back (nothing kept)
  declare v_admin uuid; v_coh uuid; u jsonb; cs jsonb; cap jsonb; st jsonb; vr jsonb;
  begin
    select ur.user_id into v_admin from security.user_roles ur join security.roles ro on ro.code = ur.role_code
     where ro.status = 'active' and (ur.expires_at is null or ur.expires_at > now()) order by ro.rank desc limit 1;
    if v_admin is null then raise exception 'post-check: no active admin role to read as'; end if;
    perform set_config('request.jwt.claims', jsonb_build_object('sub', v_admin::text, 'role', 'authenticated')::text, true);
    cap := public.admin_intake_run_read_v1('capabilities', '{}');
    if (cap->>'page_courses')::int <> 200 or jsonb_array_length(cap->'scope_forms') <> 4 then raise exception 'post-check: capabilities %', left(cap::text, 200); end if;
    u := public.admin_intake_run_read_v1('universities', jsonb_build_object('limit', 5));
    if (u->>'total')::int < 50 or jsonb_array_length(u->'items') <> 5 then raise exception 'post-check: universities view %', left(u::text, 300); end if;
    cs := public.admin_intake_run_read_v1('course_search', jsonb_build_object('q', 'Master of', 'limit', 5));
    if jsonb_array_length(cs->'items') < 1 then raise exception 'post-check: course search found nothing'; end if;
    v_o := v_o || format(' | providers %s (largest %s, %s courses, %s pages) | course search %s', u->>'total', u->'items'->0->>'name', u->'items'->0->>'active_courses', u->'items'->0->>'pages', jsonb_array_length(cs->'items'));
    select id into v_coh from pipeline.run_now_cohorts order by created_at desc limit 1;
    if v_coh is not null then
      st := security.intake_cohort_stages_record_v1(v_coh, null);
      if jsonb_array_length(st) <> 3 then raise exception 'post-check: selection stages %', st; end if;
      st := st || security.intake_cohort_stages_record_v1(v_coh, gen_random_uuid());
      if jsonb_array_length(st) <> 6 then raise exception 'post-check: run stages %', st; end if;
      vr := public.admin_intake_run_read_v1('verify', jsonb_build_object('cohort_id', v_coh));
      if jsonb_array_length(vr->'stage_history') <> jsonb_array_length(st) then raise exception 'post-check: verify stage_history % vs %', vr->'stage_history', st; end if;
      v_o := v_o || ' | latest cohort stages ' || (select string_agg((x->>'stage') || '=' || (x->>'courses') || '/' || (x->>'intakes'), ' ') from jsonb_array_elements(st) x);
    end if;
    raise exception 'cf-s790-undo';
  exception when raise_exception then if sqlerrm <> 'cf-s790-undo' then raise; end if;
  end;
  perform set_config('request.jwt.claims', '', true);
  perform set_config('cf.diag', v_o, true);
end $$;
