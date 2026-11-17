-- CF-247 F-PDESC P0 (Platform Admin directive, 9 Nov 2026: unique, source-backed university descriptions): an admitted register-fact ("basic") description no longer takes the provider out of source-backed enrichment.
--
-- What was wrong (project fxcwkweaxjtknorudmwp, SELECT only, 9 and 10 Nov 2026):
--   * About 910 providers hold (912 on 10 Nov 2026) a register-fact profile (rule registry_factual, worker registry-factual-v1, machine admission tier registry_factual). Every gate of the source-backed reader treated that profile as "the provider already has a description":
--     the automatic queue pre-filter (provider_description_selection_v1: description is null), the selection (description_current), the machine block (provider_description_machine_blocked_v1: description_already_held),
--     the machine admission (provider_description_machine_admit_v1: before_value_not_empty, description_already_held) and the lease pick (svc_provider_description_next: description is null). A profile therefore was the end of the road.
--   * 304 of those providers have a website and 184 have a stored About page (10 Nov 2026): official evidence that could make a source-backed description exists for them and could not be used.
--   * Separate fault found while diagnosing the queue (see the next block): a queued read whose provider cannot pass the identity test (no website, or another provider holds the host) was neither read nor held. It stayed queued for ever, and the registry
--     tier never took the provider because the tier skips a provider with a queued read.
--
-- Queue fault (reported, "241 queued, all due and untried, oldest 9 h", 9 Nov 2026 18:20 UTC): measured read only. The scheduled lease is NOT stopped by pdesc.pending_max: with pdesc.machine_admit_on = 1 both
-- public.svc_provider_description_next (cap = pdesc.concurrency_max) and security.provider_description_fire_v1 ignore the Layer 4 waiting count. pdesc.pending_max still gates Run Now (admin_provider_description_run_v1 review_full, the cohort size) and security.provider_description_resume_v1.
-- The oldest rows are 96 reads (65 no website, 31 provider_host_conflict, e.g. RMIT) that fail the identity test in the lease pick and so are skipped on every call without being held. The other 145 were being read at 2 to 10 a call: a record call that hits the 8 s
-- limit (3 of 14 dispatches between 16:06 and 18:16 UTC) leaves its reads in state reading for the 20 minute claim, which leaves room for 2 items on the next calls (pdesc.concurrency_max 12).
--
-- What this changes (the consumer API is not touched; no ceiling, schedule, job or existing setting value changes; nothing is switched on):
--   1 security.provider_description_basic_profile_v1(provider) NEW: returns the register-fact profile the provider holds now (admission, read, text, time) or null. It is not null only when the setting is on, the provider's CURRENT text is exactly the text of its live
--     machine admission of tier registry_factual, and that admission's read is the admitted registry_factual read. A text a person changed, a later admission of any other tier, a withdrawn admission or a cleared description all give null.
--   2 ONE new setting (G2, section Provider descriptions): pdesc.registry_upgrade_on (0/1, created OFF). Platform Admin rule 10 Nov 2026: no threshold becomes a setting, so the revisit, the rate and the identity-test count are derived from existing settings: a profile is looked at again by the same rules as a provider with no description (pdesc.recheck_days, same-evidence parking, retry on a changed page), at most pdesc.queue_per_run upgrade reads are queued a run and none while pdesc.queue_cap reads already wait, and at most batch.provider_description queued reads are tested for identity a call.
--   3 security.provider_description_machine_blocked_v1: a register-fact profile no longer counts as "a description already held" (only while the setting is on); every other block is unchanged and still applies to such a provider: manual lock, earlier Layer 4 rejection,
--     withdrawn awaiting review, open identity finding, unusable name. A profile a person edited is not a profile (the text differs) and stays "already held". An admission closed by an upgrade does not count as a withdrawal.
--   4 security.provider_description_machine_admit_v1: an item whose before text is the provider's current profile may be admitted when its tier is a source tier (stored, direct, firecrawl), the text differs from the profile, and it has at least pdesc.min_sentences
--     quote-verified sentences (the same quote, identity and lineage checks, proved again at admission, and the same machine text gate). The profile admission is closed (withdrawn_reason "Upgraded ...", never deleted), the profile read becomes superseded (existing line),
--     the new admission records before_description = the profile text and checks.upgrade (prior admission and read, source address and hash, evidence, sentence count). Withdrawing the new admission restores the profile text (existing withdraw route).
--   5 security.provider_description_selection_v1: with the new argument upgrade = true (only while the setting is on and only for the automatic queue) the pre-filter lists providers that hold a profile and have a website or a stored About page, without queued/reading/proposed work; the profile is not "description_current". The revisit is the existing one (same-evidence parking, retry_wait for pdesc.recheck_days unless the stored page changed, or the read was held by the identity hold and the provider now passes the identity test). Every other eligibility test (scope, lock, identity of the stored page, recovery memory) is the one the missing-description list uses.
--   6 security.provider_description_enqueue_v1: after the missing-description queue, up to pdesc.queue_per_run upgrade reads are queued (only while pdesc.registry_upgrade_on = 1, and not while pdesc.queue_cap or more reads already wait). A provider with a lock, rejection, withdrawal or edited text is never selected.
--   7 public.svc_provider_description_next: the lease pick accepts a queued read of a provider that holds a profile (same condition). Identity hold: after the stored About copies are found (once, in v_stored, so no second lookup), up to batch.provider_description due queued reads of ACTIVE, PUBLISHED providers are tested for identity,
--     the ones tested longest ago first (each tested read is marked checks.identity_checked_at, so the same oldest reads are not tested on every call). ONLY the outcomes wrong_host (this includes a provider with no website) and provider_host_conflict hold the read, with the identity rule and reason and the mark checks.identity_hold.
--     Every other outcome (provider_inactive, a lifecycle hold, an open identity finding) leaves the read queued, as before. wrong_host is taken by the register-fact tier (pdesc.registry_after_rules); provider_host_conflict waits for a person to resolve the duplicate host. Not applied to a Run Now cohort.
--     Measured on live (read only, 10 Nov 2026): the identity test of 10 queued reads takes about 50 ms; the stored About copy lookup that 20261109233000 removed from the per-row path is not repeated.
--   8 Re-offer after a correction (no new setting): public.svc_provider_description_next marks the read it holds (checks.identity_hold), and provider_description_selection_v1 does not park such a read in retry_wait once the provider passes the identity test again (website or host corrected). pdesc.recheck_days therefore never delays a corrected provider.
--   Free sources first: the lease and worker are unchanged (stored About evidence first, then a direct read; Firecrawl only up to pdesc.firecrawl_reads_max, which is used up, so none). No ceiling is changed. No word list is changed.
--   What is enforced for an upgrade (there is no richness score): every sentence of the new text quotes the official page (validated, proved again at admission), identity and lineage are clear, the same machine text gate as a first description passes, the text has at least pdesc.min_sentences sentences, and it differs from the profile. Anything else is a person's call in Layer 4.
--   A text the machine rule declines for a word (for example "campus") waits in Layer 4 for a person (pdesc.machine_pending_max) with the profile as the before text; nothing is published until a person decides.
--
-- Live definitions this change edits (pg_proc.prosrc md5, read 9 Nov 2026 UTC, project fxcwkweaxjtknorudmwp), before -> after:
--   security.provider_description_machine_blocked_v1(uuid) 46634e38c0469cbcbd6c23158dfadc94 -> e23fa20639a882233ad07c44299de4c0
--   security.provider_description_machine_admit_v1(uuid) 5decbd99c8ecd5e0b072d22ed6f68962 -> dedf28930cc7a12ad31570dec0d2f334
--   security.provider_description_selection_v1(jsonb) 04acb9419b9965b5d6aab420059c7e84 -> 41c9e5ffaba74453c699fd84e9135648
--   security.provider_description_enqueue_v1() 803478538da3dd9594ba08be38284c3e -> e97170e51cb27dee62db0cef3e07bb43
--   public.svc_provider_description_next(integer) 7583808609dc2dea1d3fc251607405a1 -> 504678d725b0131785f7e3541a6c3695
-- Each edit is guarded by the md5 of the live body: if a function differs, the migration raises and nothing is applied; applying it again changes nothing.
-- Forward recovery (md5 back to the text above, byte for byte): supabase/held/pdesc_basic_profile_upgrade_forward_recovery.sql.
-- Consumer API (G3): nothing in public.website_v2_*, website_edge_*, website_api_v2_*, zoho_edge_*, svc_website_settings_v1, schema api or the five edge functions is read, changed, dropped or renamed. Consumer API change approved: not applicable (no change).
-- Replaces: the "a register-fact profile is a description already held" tests (queue pre-filter, description_current, description_already_held, before_value_not_empty, lease pick description test) in the functions above; a queued read that fails the identity test is held instead of skipped for ever
-- Retires: nothing
-- Nothing is dropped, deleted or renamed by this migration. A passing check never switches anything on: pdesc.registry_upgrade_on is created OFF and is switched on by the Platform Admin or the release controller.

do $g$
declare r record;
begin
  for r in select * from (values ('security.provider_description_machine_blocked_v1(uuid)'), ('security.provider_description_machine_admit_v1(uuid)'), ('security.provider_description_selection_v1(jsonb)'),
                                 ('security.provider_description_enqueue_v1()'), ('public.svc_provider_description_next(integer)'), ('security.provider_description_identity_v1(uuid,text)'),
                                 ('security.provider_description_stored_v1(uuid)'), ('security.provider_description_stored_candidate_v1(uuid,text[])'), ('security.pipeline_num_v1(text,numeric)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.provider_description_machine_admissions') is null or to_regclass('pipeline.provider_description_reads') is null then raise exception 'required pipeline tables are missing'; end if;
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

-- ----------------------------------------------------------------------------------------------------------------------------------------- settings (G2: label, range, unit and used_by; changed on Settings with a reason)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'pdesc.registry_upgrade_on', 'Provider descriptions: upgrade a register-fact profile from a verified official page',
  'On: a provider whose description is the automatic register-fact profile stays eligible for source-backed enrichment. The machine rule may replace the profile only when the new text differs from it, has at least the minimum number of sentences (pdesc.min_sentences), every sentence quotes the provider''s official page (checked again at admission) and it passes the same machine text rules as a first description. Anything else waits for a person in Layer 4. The profile is kept as the earlier version in the admission record and is restored by withdrawing. Off: a profile is a description already held, as before. A lock, an earlier rejection, a withdrawal or a text changed by hand always keeps the provider out.',
  'number', to_jsonb(0), 0, 1, 'on/off', 1030, 'Provider descriptions', 'security.provider_description_basic_profile_v1; machine_blocked_v1; machine_admit_v1; selection_v1; enqueue_v1; svc_provider_description_next',
  'CF-247 F-PDESC P0 (Platform Admin directive, 9 Nov 2026): unique, source-backed university descriptions. Created OFF; switched on by the Platform Admin or the release controller')
on conflict (toolset_key, key) do nothing;

-- ----------------------------------------------------------------------------------------------------------------------------------------- the one rule for "this description is a register-fact profile"
create or replace function security.provider_description_basic_profile_v1(p_provider uuid) returns jsonb
language sql stable security definer set search_path to '' as $f$
  -- the profile the provider holds now, or null. Off (pdesc.registry_upgrade_on = 0), a text a person changed, a later admission of another tier, a withdrawal or a cleared description all give null.
  select jsonb_build_object('admission_id', a.id, 'read_id', a.read_id, 'text', a.after_description, 'admitted_at', a.created_at, 'evidence_id', a.evidence_id)
    from catalogue.providers p
    join pipeline.provider_description_machine_admissions a on a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null and a.tier = 'registry_factual'
   where p.id = p_provider
     and security.pipeline_num_v1('pdesc.registry_upgrade_on', 0) >= 1
     and nullif(btrim(p.description), '') is not null and btrim(p.description) = btrim(a.after_description)
     and exists (select 1 from pipeline.provider_description_reads r where r.id = a.read_id and r.state = 'admitted' and r.rule = 'registry_factual' and r.worker = 'registry-factual-v1')
$f$;
comment on function security.provider_description_basic_profile_v1(uuid) is 'CF-247 F-PDESC P0: the register-fact profile (rule registry_factual, worker registry-factual-v1, live machine admission of tier registry_factual) a provider holds now, as {admission_id, read_id, text, admitted_at, evidence_id}, or null. Null when pdesc.registry_upgrade_on is 0, when the current text is not exactly the admitted profile text (a person changed it), or when the admission was withdrawn. One rule for "this description may still be upgraded"; locks, rejections and withdrawals are checked by security.provider_description_machine_blocked_v1.';
revoke all on function security.provider_description_basic_profile_v1(uuid) from public, anon, authenticated;

-- ----------------------------------------------------------------------------------------------------------------------------------------- guarded edits of the live definitions
select pg_temp.edit_all('security.provider_description_machine_blocked_v1(uuid)', '46634e38c0469cbcbd6c23158dfadc94', 'e23fa20639a882233ad07c44299de4c0',
array[
$old$if nullif(btrim(p.description), '') is not null then
    return jsonb_build_object('rule', 'description_already_held'$old$,
$old$if exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null) then$old$,
$old$and a.withdrawn_at is not null$old$],
array[
$new$if nullif(btrim(p.description), '') is not null and security.provider_description_basic_profile_v1(p.id) is null then -- a register-fact profile is not a description held (pdesc.registry_upgrade_on); every check below still applies to it
    return jsonb_build_object('rule', 'description_already_held'$new$,
$new$if nullif(btrim(p.description), '') is null and exists (select 1 from pipeline.provider_description_machine_admissions a where a.provider_id = p.id and a.outcome = 'admitted' and a.withdrawn_at is null) then$new$,
$new$and a.withdrawn_at is not null and coalesce(a.withdrawn_reason, '') not like 'Upgraded to a source-verified description%'$new$]);

select pg_temp.edit_all('security.provider_description_machine_admit_v1(uuid)', '5decbd99c8ecd5e0b072d22ed6f68962', 'dedf28930cc7a12ad31570dec0d2f334',
array[
$old$v_url text; v_hash text; v_reason text; v_decline text;
begin$old$,
$old$  v_decline := null;
  if v_read.id is null then v_decline := 'no_proposed_read';$old$,
$old$if v_decline is null and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;$old$,
$old$if v_now is not null then v_decline := 'description_already_held'; end if;$old$,
$old$insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description,$old$,
$old$values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', v_reason, null, v_text,$old$,
$old$return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier,$old$],
array[
$new$v_url text; v_hash text; v_reason text; v_decline text; v_basic jsonb; v_upg boolean := false;
begin$new$,
$new$  v_decline := null;
  -- upgrade of a register-fact profile (pdesc.registry_upgrade_on): the item's before text is the profile the provider holds now and the proposal comes from a source tier
  v_basic := security.provider_description_basic_profile_v1(i.entity_id);
  v_upg := v_basic is not null and v_tier in ('stored', 'direct', 'firecrawl') and btrim(coalesce(i.before_value->>'description', '')) = btrim(v_basic->>'text');
  if v_read.id is null then v_decline := 'no_proposed_read';$new$,
$new$if v_decline is null and v_upg and (jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb)) < security.pipeline_num_v1('pdesc.min_sentences', 2) or v_text = btrim(v_basic->>'text')) then v_decline := 'upgrade_too_short_or_unchanged'; end if;
  if v_decline is null and not v_upg and i.before_value->>'description' is not null and nullif(btrim(i.before_value->>'description'), '') is not null then v_decline := 'before_value_not_empty'; end if;$new$,
$new$if v_now is not null and not (v_upg and v_now = btrim(v_basic->>'text')) then v_decline := 'description_already_held'; end if;$new$,
$new$if v_upg then
    -- the profile admission is closed, never deleted: its text stays as the earlier version (one live admission a provider)
    update pipeline.provider_description_machine_admissions set withdrawn_at = now(), withdrawn_by = v_sys,
           withdrawn_reason = 'Upgraded to a source-verified description from ' || coalesce(v_url, 'the official page') || '; the register-fact profile is kept in this row.'
     where id = (v_basic->>'admission_id')::uuid and outcome = 'admitted' and withdrawn_at is null;
  end if;
  insert into pipeline.provider_description_machine_admissions (provider_id, review_item_id, read_id, tier, rule, outcome, reason, before_description, after_description,$new$,
$new$values (i.entity_id, i.id, v_read.id, v_tier, v_rule, 'admitted', v_reason || case when v_upg then ' Upgrade of the register-fact profile, which is kept as the earlier version.' else '' end, case when v_upg then v_basic->>'text' end, v_text,$new$,
$new$if v_upg then
    update pipeline.provider_description_machine_admissions set checks = checks || jsonb_build_object('upgrade', jsonb_build_object('from_tier', 'registry_factual', 'prior_admission_id', v_basic->'admission_id', 'prior_read_id', v_basic->'read_id',
           'source_url', v_url, 'source_hash', v_hash, 'evidence_id', i.evidence_id, 'sentences', jsonb_array_length(coalesce(i.proposed_value->'sentences', '[]'::jsonb))))
     where review_item_id = i.id and outcome = 'admitted';
  end if;
  return jsonb_build_object('ok', true, 'provider_id', i.entity_id, 'tier', v_tier,$new$]);

select pg_temp.edit_all('security.provider_description_selection_v1(jsonb)', '04acb9419b9965b5d6aab420059c7e84', '41c9e5ffaba74453c699fd84e9135648',
array[
$old$v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);$old$,
$old$and security.provider_description_scope_v1(p.id) and nullif(btrim(p.description),'') is null and p.publication_status='published'$old$,
$old$and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))$old$,
$old$when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) then 'description_current'$old$,
$old$is distinct from coalesce(v_cur,'')) then 'retry_wait'$old$],
array[
$new$v_idr jsonb:=coalesce(security.toolset_setting('pipeline','pdesc.identity_reeval_rules'),'[]'::jsonb);
 -- upgrade mode (pdesc.registry_upgrade_on, argument upgrade): the list is the providers that hold a register-fact profile, not the providers with no description
 v_upg boolean := security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and security.pipeline_num_v1('pdesc.machine_admit_on',0)>=1 and coalesce((p_args->>'upgrade')::boolean,false);$new$,
$new$and security.provider_description_scope_v1(p.id) and case when v_upg then security.provider_description_basic_profile_v1(p.id) is not null else nullif(btrim(p.description),'') is null end and p.publication_status='published'$new$,
$new$and not exists(select 1 from pipeline.provider_description_reads x where x.provider_id=p.id and x.state in ('queued','reading','proposed'))
    and (not v_upg or ((nullif(btrim(p.website),'') is not null or security.provider_description_stored_candidate_v1(p.id,v_pat))))$new$,
$new$when r.state in ('admitted','verified') and nullif(btrim(p.description),'') is not null and coalesce(r.last_verified_at,r.updated_at)>now()-make_interval(days=>security.pipeline_num_v1('pdesc.recheck_days',180)::int) and not (v_upg and security.provider_description_basic_profile_v1(p.id) is not null) then 'description_current'$new$,
$new$is distinct from coalesce(v_cur,'')) and not (r.state='held' and coalesce(r.checks ? 'identity_hold',false) and coalesce((security.provider_description_identity_v1(p.id,coalesce(a.source_url,p.website))->>'ok')::boolean,false)) then 'retry_wait'$new$]);

select pg_temp.edit_all('security.provider_description_enqueue_v1()', '803478538da3dd9594ba08be38284c3e', 'e97170e51cb27dee62db0cef3e07bb43',
array[
$old$  end loop;
  return v_n;$old$],
array[
$new$  end loop;
  -- register-fact profiles with a page to read (pdesc.registry_upgrade_on): after the providers with no description, a bounded number a run
  -- the upgrade lane is bounded by existing settings: pdesc.queue_per_run a run, and none while pdesc.queue_cap or more reads already wait (the providers with no description come first)
  if security.pipeline_num_v1('pdesc.registry_upgrade_on',0)>=1 and (select count(*) from pipeline.provider_description_reads q where q.state='queued')<security.pipeline_num_v1('pdesc.queue_cap',60) then
   v_sel:=security.provider_description_selection_v1(jsonb_build_object('filter','all','size',least(security.pipeline_num_v1('pdesc.queue_per_run',10),security.pipeline_num_v1('pdesc.queue_cap',60))::int,'prefilter',true,'upgrade',true,
    'mode',case when security.pipeline_num_v1('pdesc.acquire_direct',0)>=1 then 'approved' else 'stored' end));
   insert into pipeline.provider_description_reads(provider_id)
   select (x->>'provider_id')::uuid from jsonb_array_elements(v_sel->'providers') x
   where (x->>'eligible')::boolean on conflict do nothing;
   get diagnostics v_k=row_count; v_n:=v_n+v_k;
   insert into pipeline.provider_description_scan_marks(provider_id,scanned_at,last_reason)
   select u.pid::uuid,now(),'looked at' from (select jsonb_array_elements_text(coalesce(v_sel->'scanned','[]'::jsonb)) pid union select y->>'provider_id' from jsonb_array_elements(coalesce(v_sel->'providers','[]'::jsonb)) y) u
   on conflict (provider_id) do update set scanned_at=excluded.scanned_at,last_reason=excluded.last_reason;
  end if;
  return v_n;$new$]);

select pg_temp.edit_all('public.svc_provider_description_next(integer)', '7583808609dc2dea1d3fc251607405a1', '504678d725b0131785f7e3541a6c3695',
array[
$old$-- identity re-offer (9 Nov 2026): a provider whose latest finished read was held$old$,
$old$own.state in ('admitted','verified'))))$old$],
array[
$new$-- identity hold (10 Nov 2026): due queued reads are tested for the provider identity, the ones tested longest ago first (each tested read is marked checks.identity_checked_at, so the same oldest reads are not tested on every call). The stored About copy is read from v_stored (found once, above).
  -- Only wrong_host (a provider with no website gives this too) and provider_host_conflict hold the read, with the identity rule and reason and the mark checks.identity_hold: the selection offers such a read again as soon as the provider passes (website or host corrected).
  -- Any other outcome (provider_inactive, a lifecycle hold, an open identity finding) leaves the read queued as before. wrong_host is taken by the register-fact tier; provider_host_conflict waits for a person. Not for a Run Now cohort (the job guard holds those).
  if v_mach and nullif(current_setting('cf.pdesc_cohort',true),'') is null and security.pipeline_num_v1('batch.provider_description', 3) >= 1 then
    update pipeline.provider_description_reads r set state=case when h.hold then 'held' else r.state end, rule=case when h.hold then h.idr else r.rule end, reason=case when h.hold then left(h.why,400) else r.reason end, -- fixed: the stored reason shows its first 400 characters
           leased_until=case when h.hold then null else r.leased_until end, updated_at=case when h.hold then now() else r.updated_at end,
           checks=coalesce(r.checks,'{}'::jsonb)||jsonb_build_object('identity_checked_at',now())||case when h.hold then jsonb_build_object('identity_hold',true) else '{}'::jsonb end
      from (select o.id, i.v->>'rule' idr, i.v->>'reason' why, (not coalesce((i.v->>'ok')::boolean,false) and i.v->>'rule' in ('wrong_host','provider_host_conflict')) hold
              from (select x.id, x.provider_id, pp.website from pipeline.provider_description_reads x join catalogue.providers pp on pp.id=x.provider_id and pp.lifecycle_status='active' and pp.publication_status='published'
                     where x.state='queued' and x.next_try_at<=now() order by (x.checks->>'identity_checked_at') nulls first, x.next_try_at, x.id limit security.pipeline_num_v1('batch.provider_description', 3)::int) o
              cross join lateral (select security.provider_description_identity_v1(o.provider_id, coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id=(v_stored->>o.provider_id::text)::uuid), o.website)) v offset 0) i) h
     where r.id=h.id and r.state='queued';
  end if;
  -- identity re-offer (9 Nov 2026): a provider whose latest finished read was held$new$,
$new$own.state in ('admitted','verified'))) or (v_mach and security.provider_description_basic_profile_v1(r.provider_id) is not null))$new$]);
