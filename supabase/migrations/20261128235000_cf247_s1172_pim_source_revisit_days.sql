-- CF-247 s1172 (S1-RM-Design; Platform Admin decision 26 Nov 2026 06:57 AEDT, "Accelerated Source Recovery"): the existing gaps.recheck_days stays at 60 days; a scoped setting
-- pim.source_revisit_days (7 days) governs the s1171 retryable failed-source revisit only.
--   security.pim_source_revisit_due_v1: backoff = pim.source_revisit_days, doubled per earlier revisit (cumulative history in pipeline.coverage_page_revisits kept); courses with no
--   active academic entry rows first (entry_missing), then the longest waiting.
--   security.pim_source_revisit_v1: the batch limit is enforced inside the function (least of the caller's limit and pim.source_revisit_batch, 25); each page is claimed with
--   FOR UPDATE SKIP LOCKED and its eligibility (still at the cap, not leased, not revisited since) is tested again on the locked row, so a page is never retried twice.
--   Access restrictions, leases, identity checks and the reader's spending controls (direct HTTP first; rendered fetch only by the reader's existing authorised path) are unchanged.
--   Measured before activation (06:58 AEDT, live): 1,778 pages due at 7 days across 183 providers, all for courses without active entry rows.
-- G1: no job, no queue (the planner's academic_entry step). G2: settings. G3: no consumer API object touched (checked). No lock removed; cron ceiling checked.
-- Replaces: the s1171 security.pim_source_revisit_due_v1 and security.pim_source_revisit_v1 (create or replace; the planner step reads the same names).
-- Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replaces
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if to_regprocedure('security.pim_source_revisit_v1(uuid,integer)') is null then raise exception 'guard: s1171 is not live'; end if;
end $g$;
create temp table s1172_locks on commit drop as select count(*) n from pipeline.manual_locks;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, updated_at)
values ('pipeline', 'pim.source_revisit_days', 'PIM: revisit a failed course page after',
        'A failed or unread course page at its read limit gets one more read this many days after its last read, doubled for each earlier revisit. Only for retryable failures; blocked, robots-refused and access-refused pages are never revisited. gaps.recheck_days is not affected.',
        'number', '7'::jsonb, 1, 60, 'days', 1862, 'Platform Admin decision 26 Nov 2026 06:57 AEDT (s1172)', 'Data delivery', 'security.pim_source_revisit_due_v1', now())
on conflict do nothing;

create or replace function security.pim_source_revisit_due_v1(p_provider uuid)
returns table(course_id uuid, last_at timestamptz)
language sql
stable
security definer
set search_path = ''
as $f$
  select g.course_id, coalesce(g.read_at, g.bound_at)
    from pipeline.coverage_course_pages g join catalogue.courses c on c.id = g.course_id and c.lifecycle_status = 'active'
    left join pipeline.coverage_page_revisits rv on rv.course_id = g.course_id
   where g.provider_id = p_provider and g.status = 'bound' and g.read_attempts >= 3  -- fixed: the reader's own cap (security.coverage_read_eligible_v1)
     and (g.read_status is null or g.read_status in ('fetch_failed', 'needs_render', 'too_thin'))
     and coalesce(g.http_status, 0) not in (401, 403, 407, 429, 451)  -- fixed: access refusals are never retried
     and coalesce(g.leased_until, '-infinity') < now()
     and coalesce(rv.last_revisit_at, g.read_at, g.bound_at) < now() - make_interval(days => security.pipeline_num_v1('pim.source_revisit_days', 7)::int * power(2, least(coalesce(rv.revisits, 0), 6))::int)  -- fixed: backoff doubling capped at 2^6
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = g.provider_id)
   order by exists (select 1 from catalogue.course_entry_requirements q where q.course_id = g.course_id and q.status = 'active'), coalesce(g.read_at, g.bound_at)
$f$;

create or replace function security.pim_source_revisit_v1(p_provider uuid, p_limit integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare v_ids uuid[]; v_lim int := least(greatest(0, coalesce(p_limit, 0)), security.pipeline_num_v1('pim.source_revisit_batch', 25)::int);
begin
  with cand as (select x.course_id from security.pim_source_revisit_due_v1(p_provider) x limit v_lim),
  d as (select g.course_id, g.read_attempts, g.read_status from pipeline.coverage_course_pages g
         where g.course_id in (select course_id from cand)
           and g.read_attempts >= 3 and coalesce(g.leased_until, '-infinity') < now()  -- tested again on the locked row
           and not exists (select 1 from pipeline.coverage_page_revisits rv where rv.course_id = g.course_id and rv.last_revisit_at > now() - make_interval(days => security.pipeline_num_v1('pim.source_revisit_days', 7)::int))
         for update of g skip locked),
  h as (insert into pipeline.coverage_page_revisits as rv(course_id, revisits, attempts_before_revisit, last_revisit_at, last_reason)
        select d.course_id, 1, d.read_attempts, now(), coalesce(d.read_status, 'not_read') from d
        on conflict (course_id) do update set revisits = rv.revisits + 1, attempts_before_revisit = rv.attempts_before_revisit + excluded.attempts_before_revisit,
                                              last_revisit_at = excluded.last_revisit_at, last_reason = excluded.last_reason
        returning rv.course_id),
  u as (update pipeline.coverage_course_pages g set read_attempts = 2, next_read_at = now() from h where g.course_id = h.course_id returning g.course_id)
  select array_agg(course_id) into v_ids from u;
  if coalesce(array_length(v_ids, 1), 0) > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('pim', 'source_revisit', p_provider::text, jsonb_build_object('pages', array_length(v_ids, 1), 'limit', v_lim, 'courses', to_jsonb(v_ids[1:50]), 'rule', 's1172 pim.source_revisit_days'), auth.uid());
  end if;
  return jsonb_build_object('revisited', coalesce(array_length(v_ids, 1), 0), 'limit', v_lim, 'courses', coalesce(to_jsonb(v_ids), '[]'::jsonb));
end $f$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); pv uuid; r jsonb; r2 jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1172_locks) then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  select g.provider_id into pv from pipeline.coverage_course_pages g where g.status = 'bound' and g.read_attempts >= 3 and g.read_status = 'fetch_failed'
     and coalesce(g.http_status, 0) not in (401, 403, 407, 429, 451) and g.read_at < now() - interval '30 days' order by g.read_at limit 1;  -- fixed: one sample provider
  if pv is not null then
    r := security.pim_source_revisit_v1(pv, 1000);  -- the function caps it
    if (r->>'limit')::int > security.pipeline_num_v1('pim.source_revisit_batch', 25) or (r->>'revisited')::int > (r->>'limit')::int then raise exception 'guard: batch limit not enforced: %', r; end if;
    r2 := security.pim_source_revisit_v1(pv, 1000);
    if exists (select 1 from jsonb_array_elements_text(r2->'courses') a join jsonb_array_elements_text(r->'courses') b on a = b) then raise exception 'guard: a page was retried twice'; end if;
    raise notice 'sample provider %: first claim %, second claim %', pv, r->'revisited', r2->'revisited';
  end if;
end $c$;
