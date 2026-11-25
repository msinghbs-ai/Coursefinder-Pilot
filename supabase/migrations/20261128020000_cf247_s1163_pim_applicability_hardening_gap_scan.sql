-- CF-247 s1163 (S1-RM-Design; Global Autonomous PIM step 1, interface 1 completed; Platform Admin 25 Nov 2026 21:37 and 21:39 AEDT: "Extend applicability rules across the registered fields.
-- Do not treat undefined applicability as confirmed applicability.").
--   1. pipeline.field_register: applicability_status (defined or undefined; a field added later is undefined until someone defines it), applicability_requires
--      (null, or international_open: the field applies to a course open to international students), applicability_basis (why).
--   2. Defined: the 23 fields whose rule is stated by the register's own purpose or evidence; deadline stays undefined (not every course has an application deadline,
--      and no rule is stated). english, academic_entry and provider_tuition require international_open: 144 active courses are closed to international students,
--      4,329 are unknown and stay unconfirmed (shown separately, never as applicable).
--   3. security.field_applicable_v1 answers true, false or null (unconfirmed) with a reason; security.pim_progress_v1 counts applicable, not applicable and unconfirmed apart.
--   4. The existing gap scan (security.field_gap_scan_v1, live definition guarded by md5) skips a course field that is not applicable (a recorded not_applicable absence, a country the
--      register does not cover, a course closed to international students). An unconfirmed field is still scanned: nothing is dropped from the queue on a guess.
-- G1: no job. G2: rules are data in the register. G3: no consumer API object touched (checked before and after). Locks and cron unchanged.
-- Replaces: the s1160 and s1162 versions of security.field_applicable_v1 and security.pim_progress_v1 (create or replace). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the guard reads
set local statement_timeout = '120s';  -- fixed: the guard reads and the first measured run

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if md5(pg_get_functiondef('security.field_gap_scan_v1(text[],integer,integer)'::regprocedure)) <> '211c4d5a15c5ed9dbc9ce0f7afa5050c' then
    raise exception 'guard: security.field_gap_scan_v1 is not the definition this change was written against';
  end if;
end $g$;
create temp table s1163_locks on commit drop as select count(*) n from pipeline.manual_locks;
create temp table s1163_cron on commit drop as select count(*) n from cron.job where active;

alter table pipeline.field_register
  add column if not exists applicability_status text not null default 'undefined',
  add column if not exists applicability_requires text,
  add column if not exists applicability_basis text;
alter table pipeline.field_register add constraint field_register_status_chk check (applicability_status in ('defined', 'undefined'));
alter table pipeline.field_register add constraint field_register_requires_chk check (applicability_requires is null or applicability_requires in ('international_open'));
comment on column pipeline.field_register.applicability_status is 'defined, or undefined (the default for a new field): an undefined field is never counted as applicable.';
comment on column pipeline.field_register.applicability_requires is 'null, or international_open: the field applies to a course not closed to international students; a course with that flag unknown is unconfirmed.';
comment on column pipeline.field_register.applicability_basis is 'Why the rule is what it is, in plain words.';

update pipeline.field_register set applicability_status = 'defined',
  applicability_basis = case field
    when 'registered_tuition' then 'The CRICOS register covers Australia only.'
    when 'english' then 'An English requirement is asked of international students.'
    when 'academic_entry' then 'Entry requirements are shown to international students.'
    when 'provider_tuition' then 'The provider''s current international tuition.'
    else 'Every active course or provider has this field.' end,
  applicability_requires = case when field in ('english', 'academic_entry', 'provider_tuition') then 'international_open' end
 where field <> 'deadline' and applicability_status <> 'defined';
update pipeline.field_register set applicability_basis = 'Not every course has an application deadline and no rule is stated: undefined until the Platform Admin states one.' where field = 'deadline';

create or replace function security.field_applicable_v1(p_field text, p_entity uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare r pipeline.field_register%rowtype; v_country text; v_open boolean;
begin
  select * into r from pipeline.field_register where field = p_field;
  if r.field is null or not r.active then
    return jsonb_build_object('applicable', false, 'reason', 'field_not_registered', 'grain', null, 'rule', null);
  end if;
  if r.entity_grain = 'course' and exists (
       select 1 from pipeline.course_field_absence a
        where a.course_id = p_entity and a.field = r.absence_field and a.absence_class = 'not_applicable' and a.resolved_at is null) then
    return jsonb_build_object('applicable', false, 'reason', 'recorded_not_applicable', 'grain', r.entity_grain, 'rule', r.applicability_rule);
  end if;
  if r.applicability_rule = 'countries' then
    select k.iso_alpha2 into v_country
      from catalogue.providers p join ref.countries k on k.id = p.country_id
     where p.id = case r.entity_grain when 'course' then (select c.provider_id from catalogue.courses c where c.id = p_entity) else p_entity end;
    if v_country is null or not (r.applicability_param->'countries') ? v_country then
      return jsonb_build_object('applicable', false, 'reason', 'country_not_covered', 'grain', r.entity_grain, 'rule', r.applicability_rule, 'country', v_country);
    end if;
  end if;
  if r.applicability_requires = 'international_open' and r.entity_grain = 'course' then
    select c.open_to_international into v_open from catalogue.courses c where c.id = p_entity;
    if v_open is false then return jsonb_build_object('applicable', false, 'reason', 'closed_to_international', 'grain', r.entity_grain, 'rule', r.applicability_rule); end if;
    if v_open is null then return jsonb_build_object('applicable', null, 'reason', 'international_open_unknown', 'grain', r.entity_grain, 'rule', r.applicability_rule); end if;
  end if;
  if r.applicability_status <> 'defined' then
    return jsonb_build_object('applicable', null, 'reason', 'applicability_undefined', 'grain', r.entity_grain, 'rule', r.applicability_rule);
  end if;
  return jsonb_build_object('applicable', true, 'reason', 'applies', 'grain', r.entity_grain, 'rule', r.applicability_rule);
end $f$;

create or replace function security.pim_progress_v1()
returns jsonb
language plpgsql
stable
security definer
set search_path = ''
as $f$
declare v_hours int := greatest(security.pipeline_num_v1('data_delivery.net_short_hours', 24)::int, 1);
        v_since timestamptz; v_fields jsonb; v_abs jsonb; v_jobs jsonb; v_ai jsonb; v_fc jsonb; v_l4 jsonb; v_leases jsonb; v_gap jsonb;
begin
  v_since := now() - make_interval(hours => v_hours);
  with reg as (select r.field, r.absence_field, r.applicability_rule, r.applicability_param, r.applicability_status, r.applicability_requires from pipeline.field_register r where r.active and r.entity_grain = 'course'),
  c as (
    select co.id course_id, k.iso_alpha2 cc, co.open_to_international oi, p.publication_status prov_pub,
           (nullif(btrim(coalesce(co.course_url, '')), '') is not null
              or exists (select 1 from catalogue.course_links l where l.course_id = co.id and l.link_type = 'official_course' and coalesce(l.status, 'active') = 'active')) official_url,
           co.study_level_id is not null level, co.primary_field_id is not null field_of_study, co.duration_value is not null duration,
           nullif(btrim(coalesce(co.delivery_mode, '')), '') is not null delivery,
           exists (select 1 from catalogue.course_campuses x where x.course_id = co.id) campus,
           co.open_to_international is not null international,
           exists (select 1 from catalogue.course_fees f where f.course_id = co.id and f.fee_type ~ '^provider_current_' and coalesce(f.status, 'active') = 'active') provider_tuition,
           exists (select 1 from catalogue.course_fees f where f.course_id = co.id and f.fee_type = 'tuition' and f.basis = 'registered_total_course' and coalesce(f.status, 'active') = 'active') registered_tuition,
           exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active') intakes,
           exists (select 1 from catalogue.course_intakes i where i.course_id = co.id and i.status = 'active' and i.application_deadline is not null) deadline,
           exists (select 1 from catalogue.course_english_requirements e where e.course_id = co.id and coalesce(e.status, 'active') = 'active') english,
           exists (select 1 from catalogue.course_entry_requirements q where q.course_id = co.id and q.status = 'active') academic_entry,
           nullif(btrim(coalesce(co.description, '')), '') is not null description
      from catalogue.courses co join catalogue.providers p on p.id = co.provider_id join ref.countries k on k.id = p.country_id
     where co.lifecycle_status = 'active'),
  u as (
    select c.cc, c.course_id, c.prov_pub, v.field, v.held, r.absence_field,
           case when r.applicability_rule = 'countries' and not (r.applicability_param->'countries') ? c.cc then 'no'
                when r.applicability_requires = 'international_open' and c.oi is false then 'no'
                when r.applicability_status <> 'defined' or (r.applicability_requires = 'international_open' and c.oi is null) then 'unconfirmed'
                else 'yes' end rule_state
      from c cross join lateral (values ('official_url', c.official_url), ('level', c.level), ('field_of_study', c.field_of_study), ('duration', c.duration),
             ('delivery', c.delivery), ('campus', c.campus), ('international', c.international), ('provider_tuition', c.provider_tuition),
             ('registered_tuition', c.registered_tuition), ('intakes', c.intakes), ('deadline', c.deadline), ('english', c.english),
             ('academic_entry', c.academic_entry), ('description', c.description)) v(field, held)
      join reg r on r.field = v.field),
  ua as (select u.cc, u.course_id, u.field, u.held, case when exists (select 1 from pipeline.course_field_absence a where a.course_id = u.course_id and a.field = u.absence_field and a.absence_class = 'not_applicable' and a.resolved_at is null) then 'no' else u.rule_state end app from u),
  ap as (select cc, field, count(*) filter (where app = 'yes') applicable, count(*) filter (where app = 'yes' and held) held,
                count(*) filter (where app = 'no') not_applicable, count(*) filter (where app = 'unconfirmed') unconfirmed
           from ua group by 1, 2),
  q as (
    select k.iso_alpha2 cc, e.field,
           count(*) filter (where e.state in ('queued', 'waiting')) queued,
           count(*) filter (where e.state in ('leased', 'ai') and (e.leased_until is null or e.leased_until >= now())) running,
           count(*) filter (where e.state = 'review') review,
           count(*) filter (where e.state = 'failed') failed,
           count(*) filter (where e.state = 'skipped') no_source_found,
           count(*) filter (where e.state in ('leased', 'ai') and e.leased_until < now()) expired_leases,
           count(*) filter (where e.state = 'filled' and e.updated_at >= v_since) filled_window,
           count(*) filter (where e.state = 'filled' and e.updated_at >= v_since and pr.publication_status = 'published') filled_published_window,
           min(e.created_at) filter (where e.state in ('queued', 'waiting', 'leased', 'ai', 'review')) oldest_outstanding
      from pipeline.field_enrich_items e join catalogue.courses co on co.id = e.course_id join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
     where e.course_id is not null group by 1, 2)
  select coalesce(jsonb_agg(jsonb_build_object(
           'country', ap.cc, 'field', ap.field, 'applicable', ap.applicable, 'not_applicable', ap.not_applicable, 'unconfirmed', ap.unconfirmed,
           'held', ap.held, 'backlog', ap.applicable - ap.held,
           'queued', coalesce(q.queued, 0), 'running', coalesce(q.running, 0), 'review', coalesce(q.review, 0), 'failed', coalesce(q.failed, 0), 'no_source_found', coalesce(q.no_source_found, 0),
           'expired_leases', coalesce(q.expired_leases, 0),
           'canonical_gain_window', coalesce(q.filled_window, 0), 'published_gain_window', coalesce(q.filled_published_window, 0),
           'throughput_per_hour', round(coalesce(q.filled_window, 0)::numeric / v_hours, 2),
           'clearance_hours', case when coalesce(q.filled_window, 0) > 0 then round((ap.applicable - ap.held)::numeric / (q.filled_window::numeric / v_hours), 1) end,
           'oldest_outstanding', q.oldest_outstanding) order by ap.cc, ap.field), '[]'::jsonb)
    into v_fields from ap left join q on q.cc = ap.cc and q.field = ap.field;
  select coalesce(jsonb_agg(z order by z->>'country', z->>'class'), '[]'::jsonb) into v_abs
    from (select jsonb_build_object('country', k.iso_alpha2, 'class', a.absence_class, 'open', count(*)) z
            from pipeline.course_field_absence a join catalogue.courses co on co.id = a.course_id join catalogue.providers pr on pr.id = co.provider_id join ref.countries k on k.id = pr.country_id
           where a.resolved_at is null group by k.iso_alpha2, a.absence_class) s;
  select coalesce(jsonb_agg(jsonb_build_object('job', j.jobname, 'active', j.active, 'schedule', j.schedule,
           'next_run', case when j.active then security.cron_next_run_v1(j.schedule, now()) end) order by j.jobname), '[]'::jsonb)
    into v_jobs from cron.job j where j.jobname in ('enrich-plan-run', 'enrich-plan-auto', 'field-gap-queue');
  select jsonb_build_object('cycle', k.cycle, 'last_run_at', k.last_run_at, 'cycle_started_at', k.cycle_started_at, 'cycle_scanned', k.cycle_scanned, 'cycle_found', k.cycle_found)
    into v_gap from pipeline.field_gap_queue_checkpoint k where k.id = 1;
  select jsonb_build_object('attempts', count(*), 'failed', count(*) filter (where i.outcome = 'failed'), 'cost_usd', coalesce(round(sum(i.cost_usd)::numeric, 4), 0))
    into v_ai from pipeline.ai_invocations i where i.at >= v_since;
  select jsonb_build_object('calls', count(*), 'credits', coalesce(sum(f.credits_used), 0)) into v_fc from pipeline.firecrawl_calls f where f.at >= v_since;
  select coalesce(jsonb_agg(jsonb_build_object('field', s.field_code, 'waiting', s.n, 'oldest', s.oldest) order by s.n desc), '[]'::jsonb)
    into v_l4 from (select i.field_code, count(*) n, min(i.created_at) oldest from pipeline.layer4_review_items i where i.status = 'pending' group by 1) s;
  select jsonb_build_object('expired', count(*), 'recovery', 'A lease past its time is taken back by the next worker claim; nothing is restored by hand.')
    into v_leases from pipeline.field_enrich_items e where e.state in ('leased', 'ai') and e.leased_until < now();
  return jsonb_build_object('as_at', now(), 'window_hours', v_hours, 'fields', v_fields, 'source_findings', v_abs, 'jobs', v_jobs, 'gap_queue', v_gap,
    'ai', v_ai, 'firecrawl', v_fc, 'human_required', jsonb_build_object('layer4_waiting', v_l4, 'enrich_review', (select count(*) from pipeline.field_enrich_items e where e.state = 'review')),
    'leases', v_leases,
    'drill', jsonb_build_object('queues_and_lanes', 'Scheduled jobs › Queue & lane control', 'operations', 'Layer 2/3 Build & enrich › Operations', 'layer4', 'Layer 4 Review'),
    'meaning', jsonb_build_object('applicable', 'fields the register says apply; an undefined rule is never counted as applicable',
      'clearance_hours', 'backlog divided by the measured hourly gain in the window; null when nothing was gained, never a guess',
      'published_gain', 'canonical gains for courses of a published provider'));
end $f$;
comment on function security.pim_progress_v1() is 'PIM monitoring (s1162, s1163): production processing progress by country and course field; applicable, not applicable and unconfirmed apart; read through security.data_delivery_v1 key pim.';

-- the gap scan: a course field that is not applicable is not taken (the live definition with one condition added before the manual-lock test of the course gaps)
do $r$
declare d text := pg_get_functiondef('security.field_gap_scan_v1(text[],integer,integer)'::regprocedure);
        a constant text := E'     where not exists (select 1 from pipeline.manual_locks lk where lk.entity = ''course'' and lk.entity_id = m.course_id and lk.field in (m.field, ''all''))';
        b constant text := E'     where not exists (select 1 from pipeline.field_register fr where fr.field = m.field and (\n'
          || E'             exists (select 1 from pipeline.course_field_absence ab where ab.course_id = m.course_id and ab.field = fr.absence_field and ab.absence_class = ''not_applicable'' and ab.resolved_at is null)\n'
          || E'          or (fr.applicability_rule = ''countries'' and not exists (select 1 from catalogue.providers pp join ref.countries kk on kk.id = pp.country_id where pp.id = m.provider_id and (fr.applicability_param->''countries'') ? kk.iso_alpha2))\n'
          || E'          or (fr.applicability_requires = ''international_open'' and exists (select 1 from catalogue.courses cc where cc.id = m.course_id and cc.open_to_international is false))))  -- not applicable: not taken (s1163)\n'
          || E'       and not exists (select 1 from pipeline.manual_locks lk where lk.entity = ''course'' and lk.entity_id = m.course_id and lk.field in (m.field, ''all''))';
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the course manual-lock anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $r$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); p jsonb; n_ok int; v_cnt int; t0 timestamptz := clock_timestamp(); s jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: the consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) <> (select n from s1163_locks) then raise exception 'guard: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> (select n from s1163_cron) then raise exception 'guard: active cron jobs changed'; end if;
  select count(*) into v_cnt from pipeline.field_register where applicability_status <> 'defined';
  if v_cnt <> 1 or not exists (select 1 from pipeline.field_register where field = 'deadline' and applicability_status = 'undefined') then raise exception 'guard: only deadline may be undefined, found %', v_cnt; end if;
  -- tri-state answers
  select count(*) into v_cnt from (select c.id from catalogue.courses c where c.lifecycle_status = 'active' and c.open_to_international is false limit 10) c  -- fixed: a sample for the rehearsal
   where (security.field_applicable_v1('english', c.id)->>'applicable') is distinct from 'false';
  if v_cnt <> 0 then raise exception 'guard: % courses closed to international wrongly applicable for english', v_cnt; end if;
  select count(*) into v_cnt from (select c.id from catalogue.courses c where c.lifecycle_status = 'active' and c.open_to_international is null limit 10) c  -- fixed: a sample for the rehearsal
   where (security.field_applicable_v1('english', c.id)->>'applicable') is not null;
  if v_cnt <> 0 then raise exception 'guard: % unknown-international courses counted as decided', v_cnt; end if;
  s := security.field_applicable_v1('deadline', (select c.id from catalogue.courses c where c.lifecycle_status = 'active' limit 1));
  if s->>'reason' <> 'applicability_undefined' or s->'applicable' <> 'null'::jsonb then raise exception 'guard: undefined deadline answered %', s; end if;
  -- the hooked scan still runs (a short slice in this rolled-back run: the checkpoint it moves is rolled back too)
  create temp table if not exists _gap(provider_id uuid, course_id uuid, field text, pri int) on commit drop;
  begin  -- a smoke slice whose writes (the scan's checkpoint) are undone: the block ends in a deliberate error
    perform security.field_gap_scan_v1(array['english', 'duration'], 7, 5);  -- fixed: a five-item smoke slice
    raise exception 's1163_smoke_ok';
  exception when others then
    if sqlerrm <> 's1163_smoke_ok' then raise; end if;
  end;
  p := security.pim_progress_v1();
  if exists (select 1 from jsonb_array_elements(p->'fields') f where (f->>'field') = 'deadline' and (f->>'applicable')::int <> 0) then raise exception 'guard: undefined deadline counted as applicable'; end if;
  if not exists (select 1 from jsonb_array_elements(p->'fields') f where (f->>'field') = 'english' and (f->>'unconfirmed')::int > 0) then raise exception 'guard: no unconfirmed english in the read'; end if;
  raise notice 'progress read in % ms', (extract(epoch from clock_timestamp() - t0) * 1000)::int;  -- fixed: milliseconds
end $c$;
