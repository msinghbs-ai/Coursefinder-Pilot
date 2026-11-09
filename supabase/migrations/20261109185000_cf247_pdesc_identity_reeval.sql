-- CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026: "Continue fixing the provider-description declines, identity conflicts ... autonomously"): provider-identity holds made by an earlier reader are read again by the current reader (same stored page).
-- Reworked after QA of the first version (the coordinator's review, 9 Nov 2026): (1) the current reader is one stored row read in O(1), no scan of the reads in the signature or the lease; (2) the evidence signature is NOT changed, so the recovery memory of the other same-hash failures is kept;
-- (3) the current reader is the stamp of the worker that is running (the newest stamp written by a worker, kept by a trigger), not the highest label on any read.
--
-- Live evidence (read 9 Nov 2026 08:30 UTC, project fxcwkweaxjtknorudmwp, SELECT only): 41 providers are held for provider identity (provider_name_conflict 39, provider_subunit_source 2). 30 of the 39 conflicts were judged by reader provider-description-source-guard-v1, BEFORE worker v0.59.13
-- (deployed 9 Nov 05:56 UTC; its reads carry provider-description-source-guard-v2), which added the registry-evidence proof (own verified host, catalogue name or registry abbreviation in the title, h1 or site name, no other institution named). They include at least 14 universities, polytechnics and TAFEs
-- (ANU, Sydney, UTS, Edith Cowan, Canberra, Canterbury, Auckland, AUT, Waikato, Massey, Open Polytechnic, Wintec, EIT, TAFE Queensland). The others were judged by v2 and stay held with that evidence.
-- Cause: the picker (security.provider_description_selection_v1) parks a held read for the same stored page (unchanged_unsuitable_evidence, retry_wait), and the lease (public.svc_provider_description_next) holds or skips a provider whose recovery knowledge (ops_learning_retry_check_v1, keyed by the evidence signature) already
-- failed for that signature. All 41 have the same page hash as their read and allowed=false. Nothing about their page changed: the READER changed.
-- What this changes:
--   1 pipeline.pdesc_reader_state: one row, the behaviour version of the reader that is running (checks.identity.reader_behavior_version, stamped by the worker on every identity check). Two row triggers on provider_description_reads keep it: a stamp that is new on a read (insert, or an update that changes it) becomes the current one.
--     The newest stamp wins, so a prefix rename is picked up, and a worker rolled back to an earlier reader makes that reader current again (its holds are read once by it, not for ever). It is seeded from the newest stamped read.
--   2 security.pdesc_reader_behaviour_v1(): the current reader, one primary-key row (microseconds).
--   3 The picker no longer parks a HELD read on an identity rule (setting pdesc.identity_reeval_rules, default provider_name_conflict, provider_name_not_proved, provider_subunit_source) whose identity check was made by another reader than the current one (unchanged_unsuitable_evidence and retry_wait are skipped for it).
--   4 The lease (public.svc_provider_description_next) does not hold or skip such a provider on its recovery knowledge: the knowledge recorded the earlier reader's failure. The set is found once per lease from the latest finished read of each provider (indexed), not per row.
--   The evidence signature (security.provider_description_signature_v1) is NOT edited: a failure of any other kind, or of the current reader, keeps its memory exactly as now. After the re-read the hold carries the current version and is parked as before; a hold the current reader still refuses stays held with the evidence.
--   Every later check is unchanged: scope, manual locks, provider_description_identity_v1, the budget, the AI and Firecrawl ceilings, Layer 4. The re-read uses the stored official copy (no Firecrawl, no new fetch), and an AI call only when the worker's identity proof passes. Nothing relaxes the identity proof itself (worker).
-- Depends on 20261109182000 (the lease finds each stored copy once): this change edits the lease function that migration produced and refuses until it is applied.
-- Live definitions this change edits (pg_proc.prosrc md5, read 9 Nov 2026), before -> after:
--   security.provider_description_selection_v1(jsonb) c8dd7882a5a6c5b174a829972d475d40 -> b51801e562a1569940c88c8413596cc4
--   public.svc_provider_description_next(integer) 90275ff3bc7da9989c2a3430b16cb94f -> d2635ebd4545fc45a8dd84c2007f90f6
-- Replaces: the identity-hold branches of the 'unchanged_unsuitable_evidence' and 'retry_wait' parking in security.provider_description_selection_v1 and of the recovery-knowledge hold and skip in public.svc_provider_description_next (both for a held read on an identity rule made by another reader)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_selection_v1(jsonb)'), ('public.svc_provider_description_next(integer)'), ('security.ops_learning_retry_check_v1(text,text,text)'),
                                 ('security.toolset_setting(text,text)'), ('security.pipeline_num_v1(text,numeric)'), ('security.provider_description_identity_v1(uuid,text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  -- fixed: this change edits the lease function as 20261109182000 leaves it
  if md5((select p.prosrc from pg_proc p where p.oid = 'public.svc_provider_description_next(integer)'::regprocedure)) not in ('90275ff3bc7da9989c2a3430b16cb94f', 'd2635ebd4545fc45a8dd84c2007f90f6') then
    raise exception 'public.svc_provider_description_next differs from the definition this change edits (apply 20261109182000 first)';
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

-- ----------------------------------------------------------------------------------------------------------------------------------------- setting (G2: the identity rules that are re-offered are a setting, changed on Settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.identity_reeval_rules', 'Provider descriptions: identity holds read again when the reader changes',
  'Hold rules (provider_name_conflict, provider_name_not_proved, provider_subunit_source) that come from the reader''s identity proof of an official page. When the reader that made such a hold is not the current reader (its behaviour version differs), the provider is offered to the current reader once more, using the stored official page. A hold the current reader still refuses stays held. Empty: identity holds are never offered again before the recheck period.',
  'list', '["provider_name_conflict", "provider_name_not_proved", "provider_subunit_source"]'::jsonb, 0, null, 'rules', 1023, 'Provider descriptions', 'security.provider_description_selection_v1',
  'CF-247 F-PDESC Directive 3 (Platform Admin, 9 Nov 2026): identity holds made by an earlier reader are read again by the current reader, with the stored page and the same governed checks')
on conflict (toolset_key, key) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the reader that is running (one row, kept by the stamps the worker writes)
create table if not exists pipeline.pdesc_reader_state (
  singleton boolean primary key default true check (singleton),
  version text not null,
  seen_at timestamptz not null default now()
);
comment on table pipeline.pdesc_reader_state is 'CF-247 F-PDESC: the behaviour version of the provider-description reader that is running now (one row). Kept by triggers on pipeline.provider_description_reads from the stamp the worker writes on each identity check (checks.identity.reader_behavior_version). Read by security.pdesc_reader_behaviour_v1 for the re-offer of identity holds.';
alter table pipeline.pdesc_reader_state enable row level security;
revoke all on pipeline.pdesc_reader_state from public, anon, authenticated;
-- seeded from the newest stamped read (a one-off scan when this runs)
insert into pipeline.pdesc_reader_state(singleton, version, seen_at)
select true, z.v, z.t from (select x.checks->'identity'->>'reader_behavior_version' v, x.created_at t from pipeline.provider_description_reads x
                             where x.checks->'identity'->>'reader_behavior_version' is not null order by x.created_at desc limit 1) z
on conflict (singleton) do nothing;

create or replace function security.pdesc_reader_stamp_v1() returns trigger
language plpgsql security definer set search_path to '' as $f$
begin
  -- the newest stamp written by a worker is the reader that is running; unchanged when it is the same
  insert into pipeline.pdesc_reader_state(singleton, version, seen_at) values (true, new.checks->'identity'->>'reader_behavior_version', now())
  on conflict (singleton) do update set version = excluded.version, seen_at = excluded.seen_at where pipeline.pdesc_reader_state.version is distinct from excluded.version;
  return null;
end $f$;
comment on function security.pdesc_reader_stamp_v1() is 'CF-247 F-PDESC: trigger function; records the reader behaviour version a worker stamped on a provider-description read as the reader that is running (pipeline.pdesc_reader_state).';
revoke all on function security.pdesc_reader_stamp_v1() from public, anon, authenticated;

do $t$
begin
  if not exists (select 1 from pg_trigger where tgname = 'pdesc_reader_stamp_ins' and tgrelid = 'pipeline.provider_description_reads'::regclass) then
    create trigger pdesc_reader_stamp_ins after insert on pipeline.provider_description_reads for each row
      when (new.checks->'identity'->>'reader_behavior_version' is not null) execute function security.pdesc_reader_stamp_v1();
  end if;
  if not exists (select 1 from pg_trigger where tgname = 'pdesc_reader_stamp_upd' and tgrelid = 'pipeline.provider_description_reads'::regclass) then
    create trigger pdesc_reader_stamp_upd after update of checks on pipeline.provider_description_reads for each row
      when (new.checks->'identity'->>'reader_behavior_version' is not null and new.checks->'identity'->>'reader_behavior_version' is distinct from old.checks->'identity'->>'reader_behavior_version')
      execute function security.pdesc_reader_stamp_v1();
  end if;
end $t$;

create or replace function security.pdesc_reader_behaviour_v1() returns text
language sql stable security definer set search_path to '' as $f$
  -- the reader that is running: one row, kept by the stamps the worker writes (pipeline.pdesc_reader_state)
  select s.version from pipeline.pdesc_reader_state s where s.singleton
$f$;
comment on function security.pdesc_reader_behaviour_v1() is 'CF-247 F-PDESC: the behaviour version of the provider-description reader that is running now (the newest stamp a worker wrote on an identity check; pipeline.pdesc_reader_state, one row). Used to offer identity holds of an earlier reader once more. Read only.';
revoke all on function security.pdesc_reader_behaviour_v1() from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded edits of the live definitions
select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', 'c8dd7882a5a6c5b174a829972d475d40', 'b51801e562a1569940c88c8413596cc4',
array[
$old$v_pat text[]:=security.pdesc_about_like_patterns_v1();$old$,
$old$when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) then 'unchanged_unsuitable_evidence'$old$,
$old$(r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) then 'retry_wait'$old$],
array[
$new$v_pat text[]:=security.pdesc_about_like_patterns_v1(); v_cur text:=security.pdesc_reader_behaviour_v1(); v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);$new$,
$new$when r.state in ('held','rejected') and r.content_hash is not null and r.content_hash=coalesce(a.content_hash,a.id::text) and not (r.state='held' and v_idr ? r.rule and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'unchanged_unsuitable_evidence'$new$,
$new$(r.state='held' or (r.source_url is not null and not coalesce((security.provider_description_page_v1(p.id,r.source_url)->>'ok')::boolean,true)))) and not (r.state='held' and v_idr ? r.rule and coalesce(r.checks->'identity'->>'reader_behavior_version','') is distinct from coalesce(v_cur,'')) then 'retry_wait'$new$]);

select pg_temp.edit_all('public.svc_provider_description_next(integer)', '90275ff3bc7da9989c2a3430b16cb94f', 'd2635ebd4545fc45a8dd84c2007f90f6',
array[
$old$v_ws text[]; v_stored jsonb;$old$,
$old$  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure'$old$,
$old$where x.state='queued' and not coalesce((security.ops_learning_retry_check_v1($old$,
$old$and coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,$old$,
$old$coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true)$old$],
array[
$new$v_ws text[]; v_stored jsonb; v_reoffer uuid[];$new$,
$new$  -- identity re-offer (9 Nov 2026): a provider whose latest finished read was held on an identity rule (pdesc.identity_reeval_rules) by another reader than the one running now (security.pdesc_reader_behaviour_v1) is not held or skipped on recovery knowledge:
  -- that knowledge recorded the earlier reader's failure. Found once here from the latest finished read of each provider. A failure of any other kind, or of the current reader, keeps its memory.
  v_reoffer := array(select l.provider_id from (select distinct on (o.provider_id) o.provider_id, o.state, o.rule, o.checks from pipeline.provider_description_reads o
                        where o.state not in ('queued', 'reading') order by o.provider_id, o.created_at desc) l
                      where l.state = 'held' and coalesce(security.toolset_setting('pipeline', 'pdesc.identity_reeval_rules'), '[]'::jsonb) ? l.rule
                        and coalesce(l.checks->'identity'->>'reader_behavior_version', '') is distinct from coalesce(security.pdesc_reader_behaviour_v1(), ''));
  update pipeline.provider_description_reads r set state='held',rule='recovery_knowledge_unchanged_failure'$new$,
$new$where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not coalesce((security.ops_learning_retry_check_v1($new$,
$new$and (r.provider_id = any(v_reoffer) or coalesce((security.ops_learning_retry_check_v1('provider_description:official_about',r.provider_id::text,$new$,
$new$coalesce(r.prompt_version,'provider-description-v2')))->>'allowed')::boolean,true))$new$]);
