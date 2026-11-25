-- CF-247 s1171 (S1-RM-Design; Global Autonomous PIM step 5 and interface 3; Platform Admin 26 Nov 2026 03:48 and 03:55 AEDT).
--   Found live (26 Nov 04:20): the page reader takes a bound page only while read_attempts < 3, so 2,226 failed or unread course pages are never visited again.
--   1. Bounded, reason-aware source revisit, security.pim_source_revisit_v1(provider, limit), through the existing reader (coverage-read):
--        only bound pages at the attempt cap whose last outcome can change on a later visit (not read, fetch_failed, needs_render, too_thin);
--        never blocked, robots_disallowed, or an access refusal (HTTP 401, 403, 407, 429, 451), so no access restriction is bypassed;
--        backoff: the existing setting gaps.recheck_days (60) after the last visit, doubled for each earlier revisit;
--        history kept: revisits, attempts_before_revisit (the cumulative attempts) and last_revisit_at on the page; read_attempts is set to 2, so each revisit buys exactly one read;
--        never a leased page, a hidden provider or an inactive course; a batch at most pim.source_revisit_batch (setting); every revisit is logged in pipeline.admin_control_events.
--      The reader's own spending controls (direct read first, Firecrawl inside the scheduled ceiling) apply unchanged. No bulk reset.
--   2. The planner hand-off to the academic entry lane: security.enrich_plan_v1 proposes step academic_entry when the provider has pages the revisit may take;
--      security.enrich_plan_start_step_v1 runs the revisit and returns a hand-off (ref kind handoff, with its courses); security.enrich_plan_tick_v1 marks it done when every
--      handed page has had its read. Fetch completion is only that: entry rows are admitted by the AER readers (aer-det-sweep) and Layer 4, and the plan's canonical result is
--      its fields_after and the PIM snapshot, never this step.
--   3. Deadline applicability defined in three states: a published application deadline (held); an evidenced statement of rolling admission or no deadline (a not_applicable
--      absence with evidence, not applicable); unknown (applicable, no value). No date is derived; admission rules unchanged.
--   4. Provider scholarships measured: verified when the provider has an active scholarship; the scholarship lane's disposition is the source finding.
--   Regular monitoring of read pages stays with the existing re-read schedule (median 90 days after a read); course entry Window 2 and its leases are not touched.
-- G1: no job (the planner's existing jobs). G2: settings. G3: no consumer API object touched (checked). No lock removed; cron ceiling checked.
-- New table: pipeline.coverage_page_revisits (history beside the reader's table). Replaces: security.enrich_plan_v1, security.enrich_plan_start_step_v1, security.enrich_plan_tick_v1, security.field_state_entity_v1 (each md5 guarded, anchored edits). Retires: none.
set local lock_timeout = '5s';  -- fixed: lock wait for the column add and function replaces
set local statement_timeout = '120s';  -- fixed: the guard reads

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API not at baseline: %', v; end if;
  if md5(pg_get_functiondef('security.enrich_plan_v1(uuid)'::regprocedure)) <> '15d174d703e29cb1b37d449847827cfa' then raise exception 'guard: enrich_plan_v1 changed'; end if;
  if md5(pg_get_functiondef('security.enrich_plan_start_step_v1(uuid,text)'::regprocedure)) <> '50b4ea8f613389062efc2116ece62db7' then raise exception 'guard: enrich_plan_start_step_v1 changed'; end if;
  if md5(pg_get_functiondef('security.enrich_plan_tick_v1(uuid)'::regprocedure)) <> '9b7c7c05491b95646b99fb7a855a9fa9' then raise exception 'guard: enrich_plan_tick_v1 changed'; end if;
  if md5(pg_get_functiondef('security.field_state_entity_v1(text,uuid)'::regprocedure)) <> 'd32d74e4d7536d1c711ca2eecbf6fa8d' then raise exception 'guard: field_state_entity_v1 changed'; end if;
end $g$;
create temp table s1171_locks on commit drop as select count(*) n from pipeline.manual_locks;

-- history beside the reader's hot table (no lock on pipeline.coverage_course_pages for a column add)
create table if not exists pipeline.coverage_page_revisits (
  course_id uuid primary key references pipeline.coverage_course_pages(course_id),
  revisits integer not null default 0,
  attempts_before_revisit integer not null default 0,
  last_revisit_at timestamptz,
  last_reason text);
comment on table pipeline.coverage_page_revisits is 'PIM (s1171): revisit history of course pages at the reader''s attempt cap; cumulative attempts = attempts_before_revisit + the page''s read_attempts.';
alter table pipeline.coverage_page_revisits enable row level security;
revoke all on table pipeline.coverage_page_revisits from public, anon, authenticated;
grant select on table pipeline.coverage_page_revisits to service_role;

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by, updated_at)
values ('pipeline', 'pim.source_revisit_batch', 'PIM: course pages revisited per plan step',
        'At most this many failed or unread course pages at their attempt cap are given one more read per academic entry plan step. A page is revisited only after gaps.recheck_days since its last read, doubled for each earlier revisit; blocked, robots-refused and access-refused pages are never revisited.',
        'number', '25'::jsonb, 0, 500, 'pages', 1861, 'S1-RM-Design s1171 (PIM step 5)', 'Data delivery', 'security.pim_source_revisit_v1', now())
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
     and coalesce(rv.last_revisit_at, g.read_at, g.bound_at) < now() - make_interval(days => security.pipeline_num_v1('gaps.recheck_days', 60)::int * power(2, least(coalesce(rv.revisits, 0), 6))::int)  -- fixed: backoff doubling capped at 2^6
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = g.provider_id)
$f$;
comment on function security.pim_source_revisit_due_v1(uuid) is 'PIM (s1171): a provider''s course pages the bounded revisit may take now.';
revoke all on function security.pim_source_revisit_due_v1(uuid) from public, anon, authenticated;

create or replace function security.pim_source_revisit_v1(p_provider uuid, p_limit integer)
returns jsonb
language plpgsql
security definer
set search_path = ''
as $f$
declare v_ids uuid[];
begin
  with d as (select g.course_id, g.read_attempts, g.read_status from pipeline.coverage_course_pages g
              where g.course_id in (select x.course_id from security.pim_source_revisit_due_v1(p_provider) x order by x.last_at limit greatest(0, coalesce(p_limit, 0)))
                and coalesce(g.leased_until, '-infinity') < now()
              for update of g skip locked),
  h as (insert into pipeline.coverage_page_revisits as rv(course_id, revisits, attempts_before_revisit, last_revisit_at, last_reason)
        select d.course_id, 1, d.read_attempts, now(), coalesce(d.read_status, 'not_read') from d
        on conflict (course_id) do update set revisits = rv.revisits + 1, attempts_before_revisit = rv.attempts_before_revisit + excluded.attempts_before_revisit,
                                              last_revisit_at = excluded.last_revisit_at, last_reason = excluded.last_reason
        returning rv.course_id),
  u as (update pipeline.coverage_course_pages g set read_attempts = 2, next_read_at = now()
          from h where g.course_id = h.course_id returning g.course_id)
  select array_agg(course_id) into v_ids from u;
  if coalesce(array_length(v_ids, 1), 0) > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('pim', 'source_revisit', p_provider::text, jsonb_build_object('pages', array_length(v_ids, 1), 'courses', to_jsonb(v_ids[1:50]), 'rule', 's1171 bounded revisit'), auth.uid());
  end if;
  return jsonb_build_object('revisited', coalesce(array_length(v_ids, 1), 0), 'courses', coalesce(to_jsonb(v_ids), '[]'::jsonb));
end $f$;
comment on function security.pim_source_revisit_v1(uuid, integer) is 'PIM (s1171): one more read for at most p_limit capped failed or unread pages of a provider, by backoff; history kept; logged.';
revoke all on function security.pim_source_revisit_v1(uuid, integer) from public, anon, authenticated;
grant execute on function security.pim_source_revisit_v1(uuid, integer) to service_role;

-- planner: propose the academic entry step
do $p$
declare d text := pg_get_functiondef('security.enrich_plan_v1(uuid)'::regprocedure);
        a constant text := '-- CF-247 ops D (P0 mandate 15:37 §7, IQ-00066): repeated empty cycles.';
        b constant text := E'-- 7 academic entry (s1171): hand capped course pages to the bounded revisit; the AER readers and Layer 4 admit the rows\n'
          || E'  if exists (select 1 from security.pim_source_revisit_due_v1(p_provider)) and security.pipeline_num_v1(''pim.source_revisit_batch'', 25) > 0 then\n'
          || E'    v_steps := v_steps || jsonb_build_object(''step'', ''academic_entry'', ''label'', ''Read failed course pages again (academic entry)'',\n'
          || E'      ''why'', (select count(*) from security.pim_source_revisit_due_v1(p_provider)) || '' course pages at their read limit are due a revisit; a read is a fetch only, rows are admitted by the AER readers and Layer 4'',\n'
          || E'      ''fields'', jsonb_build_array(''academic_entry''), ''est_credits'', least((select count(*) from security.pim_source_revisit_due_v1(p_provider)), security.pipeline_num_v1(''pim.source_revisit_batch'', 25)::int),\n'
          || E'      ''est_usd'', 0, ''group'', ''reads'');\n'
          || E'  end if;\n  ';
        i int := position(a in d);
begin
  if i = 0 or position(a in substr(d, i + 1)) > 0 then raise exception 'guard: the planner anchor is not found exactly once'; end if;
  execute substr(d, 1, i - 1) || b || substr(d, i);
end $p$;

-- step start: the hand-off
do $s$
declare d text := pg_get_functiondef('security.enrich_plan_start_step_v1(uuid,text)'::regprocedure);
        a constant text := E'raise exception ''unknown step %'', p_step;';
        b constant text := E'if p_step = ''academic_entry'' then  -- s1171: hand-off to the academic entry lane through the bounded revisit\n'
          || E'    v := security.pim_source_revisit_v1(r.provider_id, security.pipeline_num_v1(''pim.source_revisit_batch'', 25)::int);\n'
          || E'    return jsonb_build_object(''kind'', ''handoff'', ''lane'', ''academic_entry'', ''courses'', v->''courses'', ''revisited'', v->''revisited'');\n'
          || E'  end if;\n  ' || a;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the step anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $s$;

-- tick: a hand-off is done when each handed page has had its read (or left the reader's reach); never counted as canonical delivery
do $t$
declare d text := pg_get_functiondef('security.enrich_plan_tick_v1(uuid)'::regprocedure);
        a constant text := E'when s->''ref''->>''kind'' = ''onboarding'' then';
        b constant text := E'when s->''ref''->>''kind'' = ''handoff'' then (select case when not exists (select 1 from pipeline.coverage_course_pages g\n'
          || E'             where g.course_id = any (array(select x::uuid from jsonb_array_elements_text(coalesce(s->''ref''->''courses'', ''[]''::jsonb)) x))\n'
          || E'               and g.read_attempts < 3 and coalesce(g.read_at, ''-infinity'') < (s->>''started_at'')::timestamptz) then ''done'' end)  -- s1171: fetches finished, not rows admitted\n'
          || E'           ' || a;
begin
  if (length(d) - length(replace(d, a, ''))) / length(a) <> 1 then raise exception 'guard: the tick anchor is not found exactly once'; end if;
  execute replace(d, a, b);
end $t$;

-- deadline: three states, defined
update pipeline.field_register set applicability_status = 'defined',
  applicability_basis = 'Three states: a published application deadline on an active intake (held); an evidenced statement of rolling admission or no deadline, recorded as a not_applicable absence with its evidence (not applicable); otherwise unknown (applies, no value). No date is ever derived.'
 where field = 'deadline';

-- provider scholarships measured
do $m$
declare d text := pg_get_functiondef('security.field_state_entity_v1(text,uuid)'::regprocedure);
        a1 constant text := E'when ''p_campuses'' then exists (select 1 from catalogue.campuses k where k.provider_id = p.id)';
        b1 constant text := a1 || E'\n      when ''p_scholarships'' then exists (select 1 from scholarship.scholarships s where s.provider_id = p.id and s.lifecycle_status = ''active'')';
        a2 constant text := E'''source_finding'', null, ''protected_hold'', coalesce(v_locked, false)';
        b2 constant text := E'''source_finding'', case when p_field = ''p_scholarships'' and not v_held then (select jsonb_build_object(''finding'', coalesce(sc.disposition, ''unknown''), ''next_action'', sc.next_action, ''next_eligible_at'', sc.next_discover_at)\n'
          || E'        from pipeline.scholarship_provider_coverage sc where sc.provider_id = p.id) end, ''protected_hold'', coalesce(v_locked, false)';
begin
  if (length(d) - length(replace(d, a1, ''))) / length(a1) <> 1 or (length(d) - length(replace(d, a2, ''))) / length(a2) <> 1 then raise exception 'guard: field state anchors'; end if;
  execute replace(replace(d, a1, b1), a2, b2);
end $m$;

do $c$
declare v jsonb := security.consumer_api_check_v1(); pv uuid; r jsonb; n_due int; g record; x jsonb;
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then raise exception 'guard: consumer API moved: %', v; end if;
  if (select count(*) from pipeline.manual_locks) < (select n from s1171_locks) then raise exception 'guard: a manual lock was removed'; end if;
  if (select count(*) from cron.job where active) > 140 then raise exception 'guard: active cron above 140'; end if;  -- fixed: protected ceiling
  -- never an access-refused or robots page
  if exists (select 1 from pipeline.coverage_course_pages gg join catalogue.providers pp on pp.id = gg.provider_id,
             lateral security.pim_source_revisit_due_v1(pp.id) d where d.course_id = gg.course_id and (gg.read_status in ('blocked', 'robots_disallowed') or gg.http_status in (401, 403, 429))) then
    raise exception 'guard: an access-restricted page is due a revisit';
  end if;
  select g2.provider_id into pv from pipeline.coverage_course_pages g2 join catalogue.providers p2 on p2.id = g2.provider_id
   where exists (select 1 from security.pim_source_revisit_due_v1(g2.provider_id)) limit 1;  -- fixed: one sample provider for the rehearsal
  if pv is not null then
    select count(*) into n_due from security.pim_source_revisit_due_v1(pv);
    r := security.pim_source_revisit_v1(pv, 1);
    if (r->>'revisited')::int <> 1 then raise exception 'guard: bounded revisit took % (limit 1)', r; end if;
    select pg.read_attempts, pg.next_read_at, rv.revisits, rv.attempts_before_revisit, pg.course_id into g from pipeline.coverage_course_pages pg join pipeline.coverage_page_revisits rv on rv.course_id = pg.course_id
     where pg.course_id = ((r->'courses'->>0)::uuid);
    if g.read_attempts <> 2 or g.revisits < 1 or g.attempts_before_revisit < 3 or g.next_read_at > now() then raise exception 'guard: revisit state % % %', g.read_attempts, g.revisits, g.attempts_before_revisit; end if;
    if exists (select 1 from security.pim_source_revisit_due_v1(pv) d where d.course_id = g.course_id) then raise exception 'guard: a revisited page is still due (backoff)'; end if;
    raise notice 'sample provider % had % due; one revisited', pv, n_due;
  end if;
  x := security.field_state_entity_v1('p_scholarships', (select id from catalogue.providers where lifecycle_status = 'active' order by id limit 1));  -- fixed: one sample
  if x->>'completeness' not in ('verified', 'none') then raise exception 'guard: p_scholarships %', x; end if;
  if (select applicability_status from pipeline.field_register where field = 'deadline') <> 'defined' then raise exception 'guard: deadline'; end if;
  raise notice 'total due now: %', (select count(*) from catalogue.providers p, lateral security.pim_source_revisit_due_v1(p.id));
end $c$;
