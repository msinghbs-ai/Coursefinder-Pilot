-- CF-247 s978 (session S2-Build, Platform Admin consolidated morning batch of 23 Nov 2026 07:16 AEDT, Parts 2 and 4): the red Health badge,
-- IQ-00367 (AER consumer assurance), IQ-00555 (coverage-sweep HTTP 500), the :19-:23 and :49-:53 load windows (IR-013) and the $0 re-read of
-- stale AER reads from their stored copies.
-- Measured live 23 Nov 2026 07:20 to 07:45 AEDT (rolled-back dry runs; head 20261123000000, 2,270 rows; G3 75/48, no drift; manual locks 7,585;
-- active cron 136):
-- 1. Health critical check aer:p0, "31 critical consumer data finding(s)", is IQ-00367. All 31 findings are consumer_unadmitted, at 31 providers
--    (University of Wollongong 212 rows, Murdoch College 89, Federation University 87, ...), first seen 21 Nov 2026. All 1,133 rows the check
--    counts were admitted by the partial admission rule aer-partial-v1 (s914, Platform Admin 21 Nov 2026 10:03: "the partial entry-table
--    admission goes live now"): each row carries provenance.partial_admission and is named in its admission ledger row
--    (pipeline.aer_matrix_machine_admissions, outcome admitted, checks.admitted_row_ids). The check only knew a person's approval (the read's
--    Layer 4 item stays pending for the rows held back), so every partial admission read as "not admitted". Nothing bypassed a rule and no
--    defective row is served. security.aer_current_findings_v1 (md5-guarded edit of one fragment) now counts a row named by an admitted
--    aer-partial-v1 ledger row as admitted. A withdrawn row is no longer active, so the check still sees any row no rule or person admitted.
--    Decision 276 (AER v1 frozen): an essential correctness fix of an assurance check; no reader, word list, threshold or recovery path changes.
-- 2. IQ-00555: coverage-sweep answered HTTP 500 59 times in 24 hours (last 20:22 UTC), each "svc_scholarship_listing_next: canceling statement
--    due to statement timeout" (8 s API role). The claim ran security.fc_sch_held_v1 once per due listing page (339 pages of 29 providers):
--    2.1 s and 320,000 buffers on a quiet database, past 8 s under load. public.svc_scholarship_listing_next (md5-guarded, replaced in place)
--    now runs the provider checks once per provider of the due pages, then the same host check, order, limit and lease. Same rule, same rows.
-- 3. IR-013 (Platform Admin decision in this batch, Part 3.1: "throttle :20-:22 / :50-:53 background query bursts"): four jobs leave the
--    :19-:23 and :49-:53 windows for the quietest minutes of the hour (24-hour run log, background seconds per minute):
--      aer-source-discover        19          -> 40           (52 s a run)
--      field-gap-queue            23          -> 35           (79 s)
--      aer-machine-admission      6,21,36,51  -> 3,18,33,48   (43 s; still every 15 minutes, still before aer-reconcile at 12,27,42,57)
--      cdesc-queue-refresh        7,22,37,52  -> 13,28,43,58  (50 s; also leaves the :37 peak; not :00-:02)
--      layer4-readiness           22,52       -> 29,59        (20 s)
--    layer2-onboarding-snapshot (:53, every two hours) stays: rollup-scheduler holds it byte for byte as a disabled shadow target (cron
--    dispatcher rule). Commands are unchanged; only the minutes move. Active jobs stay 136.
-- 4. Stale AER reads (Part 2.5: "run existing $0 aer_det_reread on stored copies across System Queues"): of the 781 pending course entry first
--    reads, 106 are earlier AI reads held as technical recovery with a bound stored copy (security.aer_det_reread_v1 check: rereadable 106,
--    already deterministic 606, no stored page 33, not technical recovery 36). The existing rule (s870) supersedes those 106 and opens their
--    courses to the deterministic reader aer-det-v1.3 (job aer-det-sweep, stored copy, no model, no Firecrawl); the proposer then proposes
--    through the unchanged machine rule and Layer 4. No AER item is approved or rejected; the 606 deterministic reads and every entry-matrix
--    item stay for a person, one by one. The 33 with no stored page are not fetched ($0 rule; Firecrawl daily budget is 0).
-- Not changed here: the consumer API (G3 checked before and after; no v2 function changed), any manual lock, any Layer 4 decision, any spend.
-- G1: no new job. G2: no new operational value (the listing limit, lease and reread reader are the existing settings and fixed values).
-- Parity: live head 20261123000000 read 23 Nov 2026 07:20 AEDT; no open pull request carries a migration; this file is numbered above both.
-- Replaces: the per-page provider checks in public.svc_scholarship_listing_next; the consumer_unadmitted test in security.aer_current_findings_v1
-- (one fragment); the minutes of four jobs above.
-- Retires: nothing. Nothing dropped or removed.
set local lock_timeout = '5s';  -- fixed: lock wait for the function, job and catalogue updates

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
end $g$;
create temp table s978_base on commit drop as
  select (select count(*) from pipeline.manual_locks) locks, (select count(*) from cron.job where active) jobs,
         (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) decided;

-- 1. the AER assurance check: a row named by an admitted aer-partial-v1 ledger row is admitted
do $e1$
declare v_def text := pg_get_functiondef('security.aer_current_findings_v1()'::regprocedure);
        v_old constant text := $o$and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)$o$;
        v_new constant text := $n$and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)
               -- s978 (23 Nov 2026): a row the partial admission rule admitted (aer-partial-v1, s914) is admitted; its ledger row names it
               and not exists (select 1 from pipeline.aer_matrix_machine_admissions ma where ma.run_id = m.run_id and ma.outcome = 'admitted'
                                  and ma.rule = 'aer-partial-v1' and ma.checks->'admitted_row_ids' ? m.id::text)$n$;
begin
  if position('s978 (23 Nov 2026)' in v_def) > 0 then raise notice 's978 edit 1: already applied'; return; end if;
  if md5(v_def) <> '9ebdd7d01a89c00edf85d4a54ce5265a' then
    raise exception 'guard: live security.aer_current_findings_v1 differs from the definition this change edits (live md5 %)', md5(v_def);
  end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'guard: the edited fragment is not found exactly once'; end if;
  execute replace(v_def, v_old, v_new);
end $e1$;

-- 2. the scholarship listing claim: provider checks once per provider of the due pages
do $e2$
begin
  if position('s978 (23 Nov 2026' in pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) > 0 then return; end if;
  if md5(pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) <> '0ce6a0268db2c2b31d6946cd1fe427e1' then
    raise exception 'guard: live public.svc_scholarship_listing_next differs from the definition this change replaces';
  end if;
end $e2$;

CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  -- s978 (23 Nov 2026, IQ-00555): the provider checks (hidden, Firecrawl scholarship hold) run once per provider of the due pages, not once per
  -- due page (339 pages of 29 providers took 2.1 s quiet and timed out at 8 s under load); then the same host check, order, limit and lease
  with due as materialized (
    select l.id, l.provider_id from pipeline.scholarship_listing_pages l
     where l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()),
  prov as materialized (
    select d.provider_id from (select distinct due.provider_id from due) d
     where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = d.provider_id)
       and not security.fc_sch_held_v1(d.provider_id, true)),
  pick as (
    select l.id from pipeline.scholarship_listing_pages l
     where l.id in (select due.id from due join prov on prov.provider_id is not distinct from due.provider_id)
       and l.active and l.source <> 'suggested' and coalesce(l.next_read_at, now()) <= now()
       and not security.third_party_host_v1(l.url)  -- v2.15.265
     order by l.next_read_at nulls first, l.id limit greatest(1, least(coalesce(p_limit, 6), security.pipeline_num_v1('scholarship.listing_max', 20)::int)) for update skip locked),
  upd as (update pipeline.scholarship_listing_pages l set next_read_at = now() + interval '15 minutes' from pick where l.id = pick.id returning l.id, l.provider_id, l.url, l.next_url, l.page_state)  -- fixed: claim lease
  -- CF-247 scholarship recovery F6: a partly read catalogue continues from the address it stopped at
  select coalesce(jsonb_agg(jsonb_build_object('id', u.id, 'provider_id', u.provider_id, 'url', u.url, 'next_url', case when u.page_state = 'partial' then u.next_url end,
           'hosts', (select to_jsonb(coalesce(d.allowed_hosts, '{}') || array[regexp_replace(lower(substring(coalesce(d.site_origin, d.website, '') from '^https?://([^/:?#]+)')), '^www\.', '')])
                       from pipeline.scholarship_discovery_providers d where d.provider_id = u.provider_id))), '[]'::jsonb) into v from upd u;
  return v;
end $function$;

-- 3. four jobs leave the :19-:23 and :49-:53 windows (commands unchanged)
do $c$
declare r record; v_id bigint;
begin
  for r in select * from (values
      ('aer-source-discover', '19 * * * *', '40 * * * *', '19 to 40'),
      ('field-gap-queue', '23 * * * *', '35 * * * *', '23 to 35'),
      ('aer-machine-admission', '6,21,36,51 * * * *', '3,18,33,48 * * * *', '6,21,36,51 to 3,18,33,48'),
      ('cdesc-queue-refresh', '7,22,37,52 * * * *', '13,28,43,58 * * * *', '7,22,37,52 to 13,28,43,58'),
      ('layer4-readiness', '22,52 * * * *', '29,59 * * * *', '22,52 to 29,59')) v(job, was, now_s, note)
  loop
    select j.jobid into v_id from cron.job j where j.jobname = r.job and j.active;
    if v_id is null then raise exception 'guard: active job % not found', r.job; end if;
    if (select j.schedule from cron.job j where j.jobid = v_id) = r.now_s then continue; end if;
    if (select j.schedule from cron.job j where j.jobid = v_id) <> r.was then
      raise exception 'guard: job % runs at %, not the schedule this change moves', r.job, (select j.schedule from cron.job j where j.jobid = v_id);
    end if;
    perform cron.alter_job(v_id, schedule => r.now_s);
    update pipeline.automation_catalogue set description = description || ' Minutes moved ' || r.note
           || ' on 23 Nov 2026 (s978, IR-013: out of the :19-:23 and :49-:53 load windows).'
     where jobname = r.job and position('s978' in description) = 0;
  end loop;
end $c$;

-- 4. stale AER reads with a stored copy: the existing $0 re-read rule (s870)
do $r$
declare v jsonb; v_ids uuid[];
begin
  v_ids := array(select i.id from pipeline.layer4_review_items i where i.status = 'pending' and i.field_code = 'course_entry_first_read');
  v := security.aer_det_reread_v1('apply', v_ids,
         'Platform Admin 23 Nov 2026 07:16 AEDT (consolidated batch, Part 2.5): re-read stale AI course entry reads from their stored copies with the existing deterministic reader ($0)',
         'S2-Build s978');
  raise notice 's978 re-read: %', left(v::text, 500);
end $r$;

-- post-checks
do $p$
declare v jsonb := security.consumer_api_check_v1(); b record;
begin
  select * into b from pg_temp.s978_base;
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
  if (select count(*) from pipeline.manual_locks) <> b.locks then raise exception 'post-check: manual locks changed'; end if;
  if (select count(*) from cron.job where active) <> b.jobs then raise exception 'post-check: active job count changed'; end if;
  if (select count(*) from pipeline.layer4_review_items where status in ('approved', 'edited_approved', 'rejected')) <> b.decided then
    raise exception 'post-check: a Layer 4 item was approved or rejected';
  end if;
  -- the consumer_unadmitted test of security.aer_current_findings_v1 for provider-table rows, as edited above (the whole check is too heavy to run here)
  if exists (select 1 from catalogue.provider_entry_matrix m
               left join pipeline.entry_matrix_runs r on r.id = m.run_id left join pipeline.layer4_review_items li on li.id = r.review_item_id
              where m.status = 'active' and coalesce(m.provenance->>'reader', '') <> 'manual' and coalesce(li.status, 'none') not in ('approved', 'edited_approved')
                and not exists (select 1 from pipeline.layer4_review_items la where la.entity_id = m.provider_id and la.field_code in ('entry_matrix_first_run', 'entry_matrix_change')
                                  and la.status in ('approved', 'edited_approved') and la.proposed_value->>'run_id' = m.run_id::text)
                and not exists (select 1 from pipeline.aer_matrix_machine_admissions ma where ma.run_id = m.run_id and ma.outcome = 'admitted'
                                  and ma.rule = 'aer-partial-v1' and ma.checks->'admitted_row_ids' ? m.id::text)) then
    raise exception 'post-check: an active provider-table row is admitted by no person and no rule';
  end if;
  if position('s978 (23 Nov 2026)' in pg_get_functiondef('security.aer_current_findings_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the AER check was not edited';
  end if;
  if position('s978 (23 Nov 2026, IQ-00555)' in pg_get_functiondef('public.svc_scholarship_listing_next(integer)'::regprocedure)) = 0 then
    raise exception 'post-check: the listing claim was not replaced';
  end if;
  if (select count(*) from cron.job j where j.active and j.jobname in ('aer-source-discover', 'field-gap-queue', 'aer-machine-admission', 'cdesc-queue-refresh', 'layer4-readiness')
        and (j.schedule ~ '(^|,)(19|20|21|22|23|49|50|51|52|53)( |,)')) <> 0 then
    raise exception 'post-check: a moved job still runs in a load window';
  end if;
end $p$;
