-- CF-247 F-PDESC (P0, found 9 Nov 2026 23:40 AEDT): the provider-description lease and record no longer time out at the 8 second service limit.
--
-- What was wrong (project fxcwkweaxjtknorudmwp, read-only evidence, 9 and 10 Nov 2026 AEDT):
--   * Seven of 27 reader dispatches between 17:56 and 00:16 failed with HTTP 500 "svc_provider_description_lease_v1 / _record: canceling statement due to statement timeout"
--     (the PostgREST service role runs under statement_timeout 8 s). A failed record leaves its reads in state 'reading' (10 sat there from 23:06), and a failed lease leaves 389 reads waiting.
--   * Lease, measured per piece over the 389 due reads on a quiet moment: the machine-blocked pass 1.35 s; the stored-copy pass 1.35 s (1.0 s of it one test over pipeline.evidence_artifacts that
--     read 8,886 buffers); and the pick 0.7 to 1.7 s (3.2 s on a busy moment). The pick tested scope, recovery memory and the identity of EVERY due read before it sorted and kept ten, although the
--     limit is ten (batch.provider_description). Together 3.4 to 4.5 s warm; the live mean of the successful leases is 3.95 s (max 7.77 s, 46 calls). At the start of a minute four to six cron jobs
--     start together (the sampler on the 00:16 and 00:17 ticks saw the fire job and three others at :00, four more at :00 of the next minute, with BufferMapping and DataFileRead waits), the same
--     work takes two to three times as long, and the call crosses 8 s.
--   * Record: the read-only work is about 75 ms per item (validate 56 ms on average and 176 ms at worst, machine gate 10 ms, identity 5 ms, scope and snapshot 4 ms), so ten items are about 0.75 s;
--     one avoidable part is the lookup of the page copy: security.coverage_sweep_source is VOLATILE, so as a test on every row it could not be an index condition and the lookup read the whole
--     (source, hash) index (22 ms on average, 142 ms at worst, against 0.23 ms with the id in hand), once per directly read page. The live mean of the successful records is 2.0 s (max 7.31 s, 40 calls):
--     they land in the same busy minute boundary. The identity check was also asked up to three times for one read when it failed.
--   * Measured and NOT the cause: a generic plan (plan_cache_mode). Seven repeats on one connection took 0.9 to 1.1 s with the default and 0.7 to 1.0 s with force_custom_plan, so no function is given
--     that setting here. The capacity advisory lock is held by the job fire (18 to 107 s) but the worker calls come after it commits (lease 00:16:47, record 00:16:57 against a fire that ended at 00:16:45;
--     nothing blocked them), so the lock is not changed.
-- What this changes (two function bodies and one index; no setting, ceiling, job, table, column, grant or consumer object):
--   1 public.svc_provider_description_next(integer): the pick is the same query in two steps. The cheap tests and the order are worked out for every due read (state, tries, description, manual lock, cohort,
--     stored copy while direct acquisition is off), then the dear per-provider tests (scope, recovery memory, identity, hidden) run on the reads in that order until the limit is reached (an offset 0 fence keeps
--     them above the sort). The row lock, skip locked and the limit are as before; the due test is repeated on the locked row, as the lock of the old single query re-tested it. The two settings the pick
--     tested per read (pdesc.tries, pdesc.acquire_direct) are read once into variables, still through security.pipeline_num_v1 with the same defaults. The same reads in the same order are chosen:
--     supabase/held/pdesc_lease_record_timeouts_equivalence.sql compares the old and new pick on the live data (3, 10, 100 and 1000 reads, automatic and manual mode: 0 mismatches; at 1000 the sets are equal).
--   2 public.svc_provider_description_record(jsonb): the sweep source is found once per read (v_src) and used for the lookup and for the registration; the identity answer is asked once (v_idc).
--     Same results, same writes, the same order of statements.
--   3 an index on pipeline.evidence_artifacts (source_id, source_url): the stored-copy pass answers its About-address test from the index.
--   Nothing else in either function changes: the reservation protocol, the advisory lock, the AI and Firecrawl ceilings, the 20 minute claim timer and every check are as they were.
-- Live definitions this change edits (pg_proc.prosrc md5, read 9 Nov 2026 AEDT), before -> after:
--   public.svc_provider_description_next(integer) 54c8856ec36465059d41d71a5a5d462b -> 7583808609dc2dea1d3fc251607405a1
--   public.svc_provider_description_record(jsonb) f7c3debc11b67d6de7b2c6d47c8c9b9c -> 9b2137954bc05501e55e93c8ef9cf448
-- Both are guarded below: the migration stops if a live body is neither the one it replaces nor the one it writes, and applying it twice changes nothing.
-- Consumer API (G3): not touched (public.svc_provider_description_* are the reader's service functions, not website or Zoho objects; no table or column the consumer API reads is changed).
-- No operational number is written into code (G2): the two settings are read through security.pipeline_num_v1 as before. No job is added (G1).
-- Replaces: the bodies of public.svc_provider_description_next (the single-query pick of 20261109185000) and public.svc_provider_description_record (the volatile lookup and the triple identity call); the earlier text is kept in supabase/held/pdesc_lease_record_timeouts_forward_recovery.sql
-- Retires: nothing (no object has a caller removed)
-- Nothing is dropped, deleted or renamed by this migration.


do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_provider_description_next(integer)'), ('public.svc_provider_description_record(jsonb)'), ('security.provider_description_scope_v1(uuid)'), ('security.provider_description_identity_v1(uuid,text)'), ('security.coverage_sweep_source(uuid)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.evidence_artifacts') is null then raise exception 'required pipeline.evidence_artifacts is missing'; end if;
end $g$;

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_all('public.svc_provider_description_next(integer)', '54c8856ec36465059d41d71a5a5d462b', '7583808609dc2dea1d3fc251607405a1',
array[
$old$v_ws text[]; v_stored jsonb; v_reoffer uuid[];
begin
$old$,
$old$  pick as (select r.id from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < security.pipeline_num_v1('pdesc.tries', 3)
                   and security.provider_description_scope_v1(r.provider_id)
                   and (r.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>r.provider_id::text)::uuid),v_model,coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and exists(select 1 from catalogue.providers p where p.id=r.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                   and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=r.provider_id)
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1 then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))
                 for update skip locked),
$old$],
array[
$new$v_ws text[]; v_stored jsonb; v_reoffer uuid[]; v_tries numeric := security.pipeline_num_v1('pdesc.tries', 3); v_acq boolean := security.pipeline_num_v1('pdesc.acquire_direct', 0) >= 1; -- the two settings the pick tests on every due read, read once
begin
$new$,
$new$  pick as (select l.id from (
             -- lazy pick (9 Nov 2026, lease and record time-outs): the cheap tests and the order are worked out for every due read (inner query), then the dear per-provider tests
             -- (scope, recovery memory, identity, hidden) run only on the reads taken in that order until the limit is reached. The same reads in the same order as before; the whole queue is no longer tested on every call.
             select c.id from (
               select r.id, r.provider_id, r.prompt_version from pipeline.provider_description_reads r
                 where ((r.state = 'queued' and r.next_try_at <= now()) or (r.state = 'reading' and r.leased_until < now()))
                   and r.tries < v_tries
                   and ((select nullif(btrim(p.description),'') from catalogue.providers p where p.id=r.provider_id) is null
                     or (not v_mach and exists(select 1 from pipeline.provider_description_reads own where own.provider_id=r.provider_id and own.state in ('admitted','verified'))))
                   and not exists(select 1 from pipeline.manual_locks l where l.entity='provider' and l.entity_id=r.provider_id and l.field in ('description','p_description','all'))
                   and (nullif(current_setting('cf.pdesc_cohort',true),'') is null or exists(select 1 from pipeline.provider_description_cohort_members m where m.cohort_id=nullif(current_setting('cf.pdesc_cohort',true),'')::uuid and m.read_id=r.id and (m.evidence_id is null or exists(select 1 from pipeline.evidence_artifacts a where a.id=m.evidence_id and coalesce(a.content_hash,a.id::text)=m.snapshot->>'source_hash' and coalesce(a.captured_at,a.created_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.source_max_age_days',365)::int)))))
                   -- acquisition off (pdesc.acquire_direct 0): only a provider with a stored About copy is read
                   -- IQ-00055: a CASE, so the stored copy is not looked up per queued row while direct acquisition is on
                   and case when v_acq then true else (v_stored->>r.provider_id::text) is not null end
                 order by case when v_mach then coalesce((select a.n from act a join catalogue.providers pr on pr.id = r.provider_id where a.country_id = pr.country_id), 0) else 0 end, r.next_try_at, r.created_at
                 offset 0) c -- offset 0 is an optimisation fence: the dear tests below are not moved under the sort, so they stop with the limit
              where security.provider_description_scope_v1(c.provider_id)
                and (c.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',c.provider_id::text,security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(c.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))
                and exists(select 1 from catalogue.providers p where p.id=c.provider_id and p.publication_status='published' and (security.provider_description_identity_v1(p.id,coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid),p.website))->>'ok')::boolean)
                and not exists(select 1 from security.provider_hidden_v1 h where h.provider_id=c.provider_id)) o
           -- the row lock, as before: skip a read another call holds; the due test is repeated on the locked row, as the lock of the old single query re-tested it
           cross join lateral (select q.id from pipeline.provider_description_reads q where q.id = o.id
                                  and ((q.state = 'queued' and q.next_try_at <= now()) or (q.state = 'reading' and q.leased_until < now()))
                                  and q.tries < v_tries
                                for update skip locked) l
           limit greatest(1, least(coalesce(p_limit, 3),security.pipeline_num_v1('batch.provider_description',3)::int,(v_cap - v_pending)::int,coalesce(v_afford, 1000000)::int))),
$new$]);

select pg_temp.edit_all('public.svc_provider_description_record(jsonb)', 'f7c3debc11b67d6de7b2c6d47c8c9b9c', '9b2137954bc05501e55e93c8ef9cf448',
array[
$old$v_err text; v_m jsonb;
begin
$old$,
$old$      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = security.coverage_sweep_source(r.provider_id) and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(security.coverage_sweep_source(r.provider_id), v_url,$old$,
$old$    if not (security.provider_description_identity_v1(r.provider_id,r.source_url)->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'rule','reason',security.provider_description_identity_v1(r.provider_id,r.source_url)->>'reason','checks',v_chk->'checks');$old$],
array[
$new$v_err text; v_m jsonb; v_src uuid; v_idc jsonb;
begin
$new$,
$new$      if security.provider_page_host_v1(r.provider_id, v_url) = 'own' then
        -- the sweep source is found once (9 Nov 2026, record time-out): security.coverage_sweep_source is volatile, so as a test on every row it could not be an index condition and the lookup read the whole (source, hash) index (22 ms on average, 142 ms at worst, against 0.2 ms with the id in hand)
        v_src := security.coverage_sweep_source(r.provider_id);
        select a.id into v_ev from pipeline.evidence_artifacts a where a.source_id = v_src and a.content_hash = v_hash and a.source_url = v_url limit 1;
        if v_ev is null then
          v_ev := public.svc_coursefacts_register_evidence(v_src, v_url,$new$,
$new$    v_idc := security.provider_description_identity_v1(r.provider_id,r.source_url); -- once: the same answer was asked for up to three times
    if not (v_idc->>'ok')::boolean then
      v_chk:=jsonb_build_object('ok',false,'outcome','held','rule',v_idc->>'rule','reason',v_idc->>'reason','checks',v_chk->'checks');$new$]);

-- the stored-copy pass of the lease asks, for every provider with open work, whether any of its evidence is at an About address; that read the evidence heap (8,886 buffers for 389 reads).
-- With the source address in the index the same test is answered from the index (the table is 100% visible). A plain index: nothing is dropped; a build over the 208,836 rows takes a moment.
create index if not exists evidence_artifacts_source_url_idx on pipeline.evidence_artifacts (source_id, source_url);
comment on index pipeline.evidence_artifacts_source_url_idx is 'CF-247 9 Nov 2026 (provider-description lease time-out): lets the lease test the addresses of a source from the index; used by public.svc_provider_description_next.';
