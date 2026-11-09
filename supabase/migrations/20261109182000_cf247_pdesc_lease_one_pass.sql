-- CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): the provider-description lease finds each provider's stored About copy ONCE, not up to three times per queued row, so it finishes well inside the 8 second limit of a service call.
--
-- Live evidence (project fxcwkweaxjtknorudmwp, 9 Nov 2026, SELECT and rolled-back DO blocks only):
--   * 08:16 UTC: the worker's lease call failed with 500 "svc_provider_description_lease_v1: canceling statement due to statement timeout"; the 08:16 cron run took 71 s (1 call in about 12). Service calls run under the connection role's 8 s statement_timeout (authenticator 8s; service_role sets none).
--   * 09:20-09:24 UTC, 475 queued reads: public.svc_provider_description_next(10) (called by svc_provider_description_lease_v1) took 6.0 s, 4.7 s and again about 4.7 s when nothing else of ours was running. The lease already sits at 60 to 75 percent of the limit; the cron minutes :06, :16, :26 and :56 also start 5 to 12 other jobs
--     (fee-reader, coverage-ai-match-prepare, website-sync-check, provider-english-defaults and others, 15 to 55 s each), so the lease on a busy minute crosses 8 s. The queue grows with the 508-read target, and a sixth fire per hour adds load.
--   * Cause (measured per piece over the 475 queued reads, warm): security.provider_description_stored_v1(provider) costs about 2 ms per call even when the provider has no About copy (460 of 475 have none), so one pass is about 1.0 to 2.0 s (a provider WITH About copies costs 20 to 340 ms: the page rule runs once per copy, 597 copies for 51 providers). The lease called it for every queued row three times and once more for each of the (up to 10) items it hands out:
--     in the recovery-knowledge update (join), in the retry check of the pick, and in the identity check of the pick. The other pieces are small (scope 0.2 s, identity check 0.5 s, retry check 0.2 s, hidden/lock checks 0.01 s). It is not a lock wait and not a missing index:
--     the only wide scan, pipeline.sources / pipeline.evidence_artifacts, runs on pipeline_sources_provider_idx and evidence_source_idx (147 ms for all 475 as one query); catalogue.providers has providers_site_host_active_idx for the host-conflict check.
-- What this changes (only public.svc_provider_description_next(integer)):
--   1 The stored copy of each provider with open work (queued, or reading with an expired lease) is found once into v_stored, and every place reads it from there (the recovery update, the retry check, the identity check, the acquire-off test and the item the lease hands out).
--   2 Providers with no address that is an About page are not asked at all: security.pdesc_about_like_patterns_v1() is the first step of provider_description_stored_v1 (a copy must have an address matching it), as the picker already uses it. A set query finds them (147 ms), the function is asked only about those (52 of 475).
--   The choice of items, their order, the limit, every check and every setting are unchanged; the reservation protocol, the advisory lock, the AI and Firecrawl ceilings and the 20 minute claim timer are untouched. No statement timeout is changed. The stored copy of an item in a cohort is still the cohort's own evidence, as before.
-- Live definition this change edits (pg_proc.prosrc md5, read 9 Nov 2026 09:17 UTC), before -> after:
--   public.svc_provider_description_next(integer) cb83dc4e3502d6cc16450c2126368ec9 -> 2783d0a82e9f472b38b179c07add38ac
-- Replaces: the three per-row calls of security.provider_description_stored_v1 in public.svc_provider_description_next (recovery update, retry check, identity check) by one pass
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
declare r record;
begin
  for r in select * from (values ('public.svc_provider_description_next(integer)'), ('security.provider_description_stored_v1(uuid)'), ('security.pdesc_about_like_patterns_v1()')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  -- fixed: the prefilter is only exact while the pattern function is the one provider_description_stored_v1 starts from (body md5 read 9 Nov 2026)
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.pdesc_about_like_patterns_v1()'::regprocedure)) <> '29200a6a4ad7f38e0cdd30dbadd79857' then
    raise exception 'security.pdesc_about_like_patterns_v1 differs from the definition this change was written against';
  end if;
  if md5((select p.prosrc from pg_proc p where p.oid = 'security.provider_description_stored_v1(uuid)'::regprocedure)) <> '733d28159a080abdfd5cec244aed2cb9' then
    raise exception 'security.provider_description_stored_v1 differs from the definition this change was written against';
  end if;
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

select pg_temp.edit_all('public.svc_provider_description_next(integer)', 'cb83dc4e3502d6cc16450c2126368ec9', '2783d0a82e9f472b38b179c07add38ac',
array[
$old$v_fc_res int; v_fc_left int;$old$,
$old$  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure'$old$,
$old$join pipeline.evidence_artifacts a on a.id=security.provider_description_stored_v1(x.provider_id)$old$,
$old$(select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(r.provider_id))$old$,
$old$(select a.source_url from pipeline.evidence_artifacts a where a.id=security.provider_description_stored_v1(p.id))$old$,
$old$else security.provider_description_stored_v1(r.provider_id) is not null end$old$,
$old$else security.provider_description_stored_v1(u.provider_id) end stored_id$old$],
array[
$new$v_fc_res int; v_fc_left int; v_ws text[]; v_stored jsonb;$new$,
$new$  -- one pass (9 Nov 2026, lease statement time-out): the stored About copy of each provider with open work is found ONCE here and read from v_stored below; it was found up to three times per queued row.
  -- Only a provider with a copy at an About address can have one (security.pdesc_about_like_patterns_v1 is the first step of security.provider_description_stored_v1), so the others are not asked.
  v_ws := security.pdesc_about_like_patterns_v1();
  select coalesce(jsonb_object_agg(z.pid, to_jsonb(z.sid)), '{}'::jsonb) into v_stored from (
    select x.provider_id::text pid, security.provider_description_stored_v1(x.provider_id) sid
      from (select distinct o.provider_id from pipeline.provider_description_reads o where (o.state='queued' or (o.state='reading' and o.leased_until<now()))
               and exists (select 1 from pipeline.sources s join pipeline.evidence_artifacts a on a.source_id=s.id where s.provider_id=o.provider_id and lower(a.source_url) like any (v_ws))
             offset 0) x) z -- offset 0 is an optimisation fence: without it the planner moves the not-null test below the DISTINCT and asks stored_v1 for every open read
   where z.sid is not null;
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure'$new$,
$new$join pipeline.evidence_artifacts a on a.id=(v_stored->>x.provider_id::text)::uuid$new$,
$new$(select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>r.provider_id::text)::uuid)$new$,
$new$(select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>p.id::text)::uuid)$new$,
$new$else (v_stored->>r.provider_id::text) is not null end$new$,
$new$else (v_stored->>u.provider_id::text)::uuid end stored_id$new$]);
