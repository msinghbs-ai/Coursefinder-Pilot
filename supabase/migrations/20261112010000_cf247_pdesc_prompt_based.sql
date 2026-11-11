-- CF-247 F-PDESC prompt-based provider descriptions (Platform Admin direction 11 Nov 2026 14:51 and 14:57 AEDT):
--   "make the provider description prompt based that can fit and can be easily modified rather than stringent rules that keeps failing";
--   "for operators a simple button to fill in a provider's description, the Platform Admin maintains the prompt in the settings from the UI;
--    the on-demand fill has no applicable limits; the regular scan honours the Firecrawl and AI limits; a description written by hand is never
--    replaced by AI or the scan".
--
-- Finding (live, 11 Nov 2026 14:50 AEDT): since 20261110250000, 170 AI reads returned NO sentences (the built-in prompt v2 offers the model an
-- exit, "set about_page false and give no sentences", and lists nine prohibitions); only about a third of AI reads passed. The University of
-- Sydney's stored About page gave sentences under worker v0.59.15 and none under v0.66.0.
--
-- What this does (the worker side is coverage-sweep v0.69.0 in the same change):
--   1 pipeline.provider_description_prompts: the prompt, versioned. One version is active. The Platform Admin edits it on Models & services ›
--     AI & OpenRouter › Provider description prompt (public.admin_provider_description_prompt_v1, with a reason); a save is a new version, never
--     an edit in place. Seeded with version 3. Setting pdesc.prompt_on (1) uses it; 0 goes back to the worker's built-in prompt v2.
--   2 The lease (svc_provider_description_next) hands the active prompt to the worker and records its version on each leased read
--     (prompt_version 'provider-description-p<version>'), so the recovery memory (security.provider_description_signature_v1) treats a new
--     prompt as new knowledge: a page that failed under an older prompt is read again once under the new one.
--   3 security.provider_description_validate_v1, prompt profile (pdesc.prompt_on 1): the wording is the prompt's job. The checks a machine applies
--     reliably stay: own website and About page, identity (unchanged, before any AI call), every quote on the page, every number in its quote,
--     a complete sentence, support of each sentence by its quotes (pdesc.prompt_support_min_share), a list of words a description never carries
--     whatever the page says (pdesc.prompt_refused_words: rankings, awards, outcomes, promotion, fees, visas), the first sentence names the
--     provider, length, age, duplicate. Left to the prompt in this profile: superlatives and claim words matched against the quote, the
--     campus/scholarship/guarantee claim check, the verbatim-copy span and the historic-context rule. With pdesc.prompt_on 0 every rule applies
--     exactly as before.
--   4 On demand (public.admin_provider_description_fill_v1, operators): queues each selected provider at the front, marked checks.on_demand, and
--     starts a worker call at once. An on-demand read is not held by the lane AI ceiling (pdesc.ai_usd_max), the lane daily guard
--     (openrouter.guard_provider_description), the Firecrawl allowance (pdesc.firecrawl_reads_max) or the Firecrawl daily share (purpose
--     provider_description_on_demand in svc_fc_spend), nor by the "same page already failed" memory. It still stops for: a manual lock, the
--     provider's identity proof, the platform-wide AI rule (security.ai_use_allowed_v1: OpenRouter credit floor and platform daily ceiling) and
--     the Firecrawl monthly plan limit (the account's own limits). The mark counts only within pdesc.on_demand_minutes of the click
--     (security.pdesc_on_demand_live_v1): after that the read is an ordinary read of the regular scan. The scheduled scan keeps every limit.
--   5 A description written by hand (admin_provider_edit sets a manual lock) is never replaced: the lease, the record and the on-demand fill skip
--     a locked provider (unchanged rules, now also stated on the fill result).
--   6 security.provider_description_self_heal_v1 (c): a held read whose AI answer failed a check under an older prompt version is put back in the
--     queue once for the active prompt (pdesc.prompt_reoffer_rules, at most pdesc.self_heal_requeue_per_run a run).
--   7 Settings: the Run & Validate card on Enrich fields is retired (component_register: retiring) in favour of the Fill description button and
--     the prompt; the wording-rule settings used only by the built-in prompt move to section "Provider descriptions › built-in prompt only".
--     pdesc.machine_refused_words drops campuses, partner(s), partnership and pathway(s), which the prompt asks the model to state.
-- Consumer API (G3): not touched. Nothing is dropped or deleted. No description is written by applying this migration.
-- Forward recovery: supabase/held/pdesc_prompt_based_forward_recovery.sql sets pdesc.prompt_on to 0 (the built-in prompt v2 and every wording
-- rule apply again; the on-demand exemptions act only on reads marked by Fill description).
-- Replaces: the Run & Validate card (screen ProviderDescriptionRunValidate) and the built-in worker prompt v2 as the default.
-- Retires: screen ProviderDescriptionRunValidate (retiring, replaced by the Fill description button and the provider description prompt).

do $g$
begin
  if md5(pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) <> 'd4a4d31a8786a84fe18c28022f68a398' then raise exception 'validate_v1 is not the reviewed body'; end if;
  if md5(pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure)) <> '82bfe2daae5c95059ada6aa6305e0dde' then raise exception 'svc_provider_description_next is not the reviewed body'; end if;
  if md5(pg_get_functiondef('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'::regprocedure)) <> 'bcd9bec36a7dcf106d0976a1a7ec896b' then raise exception 'reserve_v1 is not the reviewed body'; end if;
  if md5(pg_get_functiondef('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure)) <> 'ee400f93352eef2be4158d4edacdc716' then raise exception 'svc_fc_spend is not the reviewed body'; end if;
  if md5(pg_get_functiondef('security.fc_purpose_group_v1(text)'::regprocedure)) <> '8041bf166d40460f8b255ed0bcbc8312' then raise exception 'fc_purpose_group_v1 is not the reviewed body'; end if;
  if md5(pg_get_functiondef('security.provider_description_self_heal_v1()'::regprocedure)) <> 'aaca6407c251641c164a10352abcfcfd' then raise exception 'self_heal_v1 is not the reviewed body'; end if;
  if md5(pg_get_functiondef('security.provider_description_fire_v1()'::regprocedure)) <> 'c6a9ed0a39d68ee2e88500e771e047c8' then raise exception 'fire_v1 is not the reviewed body'; end if;
end $g$;

-- a helper for the guarded replacements below: the anchor must stand exactly once in the live body
create or replace function pg_temp.pdesc_swap(p_fn regprocedure, p_old text, p_new text) returns void language plpgsql as $s$
declare d text := pg_get_functiondef(p_fn);
begin
  if (length(d) - length(replace(d, p_old, ''))) / length(p_old) <> 1 then raise exception '%: anchor not found exactly once: %', p_fn, left(p_old, 80); end if;
  execute replace(d, p_old, p_new);
end $s$;

-- 1 -------------------------------------------------------------------------------------------------------------- the prompt, versioned
create table if not exists pipeline.provider_description_prompts (
  version int primary key,
  system_prompt text not null check (length(btrim(system_prompt)) >= 200),
  status text not null default 'draft' check (status in ('draft', 'active', 'retired')),
  reason text not null check (length(btrim(reason)) >= 4),
  created_by uuid,
  created_at timestamptz not null default now(),
  activated_at timestamptz,
  activated_by uuid
);
comment on table pipeline.provider_description_prompts is 'CF-247 F-PDESC (20261112010000): the provider-description prompt, one row a version; exactly one is active. Edited by the Platform Admin on Models & services › AI & OpenRouter (admin_provider_description_prompt_v1), never in place. Read by the lease (security.provider_description_prompt_active_v1) while pdesc.prompt_on is 1.';
create unique index if not exists provider_description_prompts_one_active on pipeline.provider_description_prompts ((true)) where status = 'active';
alter table pipeline.provider_description_prompts enable row level security;
revoke all on pipeline.provider_description_prompts from anon, authenticated;

insert into pipeline.provider_description_prompts(version, system_prompt, status, reason, activated_at) values (3,
$p$You write the "About" description of one education provider for a course-search website used by international students. Use only the page text you are given: it is the provider's own official page.

Write 3 to 4 sentences (about 60 to 110 words) in plain Australian English, third person, present tense. Begin the first sentence with the provider's full name as given. Where the page says it, cover: what kind of institution it is; where it is (city, state, campuses); what it teaches (main study areas, levels, how it is delivered); and one or two facts that make it distinct (founding year, history, specialisation, community or partners).

Rules:
- Every fact must come from the page. No outside knowledge, no guessing.
- Leave out rankings, awards, star ratings, graduate employment or salary figures, and comparisons with other institutions, even when the page states them.
- Turn promotional wording into neutral fact ("world-leading research" becomes "conducts research in ..."). No superlatives.
- Write in your own words; never copy more than 8 words in a row from the page.
- Do not mention fees, scholarships, visas or entry requirements.

For each sentence, list the exact page passage or passages that support it, each copied character for character from the page text, in the order they appear on the page.
Only if the page says nothing about the institution itself (a login, news or course page), return no sentences and give the reason.$p$,
 'active', 'CF-247 F-PDESC (Platform Admin 11 Nov 2026 14:51/14:57): prompt-based provider descriptions, first version', now())
on conflict (version) do nothing;

create or replace function security.provider_description_prompt_active_v1() returns jsonb
language sql stable security definer set search_path to '' as $f$
  -- CF-247 F-PDESC (20261112010000): the active prompt while pdesc.prompt_on is 1; null means the worker's built-in prompt v2
  select case when security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1 then
    (select jsonb_build_object('version', 'provider-description-p' || p.version, 'system', p.system_prompt) from pipeline.provider_description_prompts p where p.status = 'active')
  end
$f$;
comment on function security.provider_description_prompt_active_v1() is 'CF-247 F-PDESC (20261112010000): the active provider-description prompt and its version string, or null (built-in prompt v2) while pdesc.prompt_on is 0.';
revoke all on function security.provider_description_prompt_active_v1() from public, anon, authenticated;

create or replace function security.pdesc_on_demand_live_v1(p_checks jsonb) returns boolean
language sql stable security definer set search_path to '' as $f$
  -- CF-247 F-PDESC (20261112010000): a read's on-demand mark counts only within pdesc.on_demand_minutes of the click; after that the read is
  -- an ordinary read of the regular scan with every limit (a mark left on a requeued read gives nothing)
  select coalesce(p_checks ? 'on_demand' and (p_checks->'on_demand'->>'at')::timestamptz > now() - make_interval(mins => security.pipeline_num_v1('pdesc.on_demand_minutes', 15)::int), false)
$f$;
comment on function security.pdesc_on_demand_live_v1(jsonb) is 'CF-247 F-PDESC (20261112010000): true while a read''s Fill description mark is within pdesc.on_demand_minutes; every on-demand exemption uses it.';
revoke all on function security.pdesc_on_demand_live_v1(jsonb) from public, anon, authenticated;

create or replace function security.pdesc_on_demand_due_v1() returns boolean
language sql stable security definer set search_path to '' as $f$
  -- CF-247 F-PDESC (20261112010000): a live on-demand read is due (and can still be tried)
  select exists (select 1 from pipeline.provider_description_reads x
                  where security.pdesc_on_demand_live_v1(x.checks) and x.tries < security.pipeline_num_v1('pdesc.tries', 3)
                    and ((x.state = 'queued' and x.next_try_at <= now()) or (x.state = 'reading' and x.leased_until < now())))
$f$;
comment on function security.pdesc_on_demand_due_v1() is 'CF-247 F-PDESC (20261112010000): true while a Fill description read asked for within pdesc.on_demand_minutes is due.';
revoke all on function security.pdesc_on_demand_due_v1() from public, anon, authenticated;

-- settings (G2)
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason, control_class) values
 ('pipeline', 'pdesc.prompt_on', 'Provider descriptions: use the prompt from Settings',
  '1: the reader uses the active prompt (Models & services › AI & OpenRouter › Provider description prompt) and the prompt profile of checks. 0: the worker''s built-in prompt v2 and every wording rule, as before.',
  'number', '1'::jsonb, 0, 1, 'switch', 1034, 'Provider descriptions', 'security.provider_description_prompt_active_v1; security.provider_description_validate_v1',
  'CF-247 F-PDESC (Platform Admin 11 Nov 2026 14:51): prompt-based descriptions', 'human'),
 ('pipeline', 'pdesc.prompt_support_min_share', 'Provider descriptions: support of a sentence by its quotes (prompt)',
  'With the prompt on: the share of a sentence''s words that its supporting passages must contain; below it the sentence is left out.',
  'number', '0.5'::jsonb, 0, 1, 'share', 1035, 'Provider descriptions', 'security.provider_description_validate_v1',
  'CF-247 F-PDESC (20261112010000): one check for invented content, lighter than the built-in 0.6 because a sentence may draw on several passages', 'automatic'),
 ('pipeline', 'pdesc.prompt_refused_words', 'Provider descriptions: words a description never carries (prompt)',
  'With the prompt on: a sentence holding any of these is left out whatever the page says (rankings, awards, outcomes, promotion, fees, visas).',
  'list', '["ranked","ranking","rankings","rated","qs","times higher","award-winning","five-star","5-star","star rating","salary","salaries","employment rate","employability","graduate outcomes","best","leading","world-class","world class","world-leading","top-ranked","premier","renowned","prestigious","excellent","outstanding","unrivalled","unparalleled","finest","elite","cutting-edge","number one","#1","first-class","exceptional","forefront","fee","fees","tuition","scholarship","scholarships","visa","visas","guaranteed"]'::jsonb,
  null, null, 'words', 1036, 'Provider descriptions', 'security.provider_description_validate_v1',
  'CF-247 F-PDESC (20261112010000): the prompt''s exclusions as a check', 'automatic'),
 ('pipeline', 'pdesc.prompt_reoffer_rules', 'Provider descriptions: held answers read again for a new prompt',
  'A held read whose AI answer failed one of these checks under an older prompt version is read again once with the active prompt (job provider-description-self-heal).',
  'list', '["not_stated","unsupported_sentence","unsupported_claim","unsupported_marketing","unsupported_numeric_claim","quote_not_on_page","verbatim_passage","length","sentence_count","incomplete_sentence","historic_claim_context","claim_unsupported_by_quote","claim_negated_in_source","refused_topic","first_sentence_no_name","machine_declined_machine_text_refused_word"]'::jsonb,
  null, null, 'rules', 1037, 'Provider descriptions', 'security.provider_description_self_heal_v1',
  'CF-247 F-PDESC (20261112010000): a new prompt is new knowledge', 'automatic'),
 ('pipeline', 'pdesc.on_demand_minutes', 'Provider descriptions: on-demand priority',
  'For this long after Fill description, the provider''s read goes first and is not held by the lane limits; after it, a read that could not be taken (for example its page lost its identity proof) joins the regular scan, so the scan never waits on it.',
  'number', '15'::jsonb, 1, 1440, 'minutes', 1039, 'Provider descriptions', 'security.pdesc_on_demand_due_v1',
  'CF-247 F-PDESC (20261112010000): on demand never stalls the regular scan', 'automatic'),
 ('pipeline', 'pdesc.fill_max_per_click', 'Provider descriptions: providers in one Fill click',
  'The most providers one click of Fill description queues on demand.',
  'number', '25'::jsonb, 1, 200, 'providers', 1038, 'Provider descriptions', 'public.admin_provider_description_fill_v1',
  'CF-247 F-PDESC (Platform Admin 11 Nov 2026 14:57): a simple operator button', 'automatic')
on conflict (toolset_key, key) do nothing;

-- the wording rules the prompt now carries are used only while pdesc.prompt_on is 0
update pipeline.platform_toolset_settings set section = 'Provider descriptions › built-in prompt only', updated_at = now(),
       reason = 'CF-247 F-PDESC 20261112010000: used only while pdesc.prompt_on is 0 (the prompt carries the wording)'
 where toolset_key = 'pipeline' and key in ('pdesc.superlatives', 'pdesc.claim_words', 'pdesc.evidence_claim_words', 'pdesc.verbatim_span_max_chars', 'pdesc.support_min_share');

update pipeline.platform_toolset_settings set value = '["visa","visas","migration","immigration","fee","fees","tuition","funding","loan","loans","bursary","bursaries","scholarships","guaranteed","accredited"]'::jsonb, updated_at = now(),
       reason = 'CF-247 F-PDESC 20261112010000: campuses, partner(s), partnership and pathway(s) removed: the prompt asks the model to state campuses and partners'
 where toolset_key = 'pipeline' and key = 'pdesc.machine_refused_words';

-- 2 -------------------------------------------------------------------------------------------------------------- the lease: prompt, prompt version, on demand
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$v_afford numeric;$o$,
  $n$v_afford numeric; v_od boolean; v_over boolean := false; v_pv text := security.provider_description_prompt_active_v1()->>'version'; -- 20261112010000: on demand, over a lane limit, the active prompt version$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;$o$,
  $n$  -- 20261112010000: a read an operator asked for (checks.on_demand) is not held by the lane limits; while one is due, this call takes on-demand reads only
  v_od := security.pdesc_on_demand_due_v1();
  if v_od then v_over := true; end if;
  if v_spent >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_ceiling', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$    if v_afford < 1 then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;$o$,
  $n$    if v_afford < 1 and not v_od then return jsonb_build_object('idle', true, 'reason', 'ai_spend_committed', 'spent_usd', v_spent, 'items', '[]'::jsonb); end if;
    if v_od then v_afford := null; end if;$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;$o$,
  $n$                    else greatest(0, security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0)::int - v_fc_used) end;
  if v_od then v_fc_left := security.pipeline_num_v1('pdesc.firecrawl_per_call', 5)::int; end if; -- 20261112010000: on demand, the per-call share only (spent as purpose provider_description_on_demand)$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not coalesce($o$,
  $n$    where x.state='queued' and not (x.provider_id = any(v_reoffer)) and not security.pdesc_on_demand_live_v1(x.checks) and not coalesce($n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(x.prompt_version,'provider-description-v2')))$o$,
  $n$security.provider_description_signature_v1(coalesce(a.content_hash,a.id::text),v_model,coalesce(v_pv,x.prompt_version,'provider-description-v2')))$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$               select r.id, r.provider_id, r.prompt_version from pipeline.provider_description_reads r$o$,
  $n$               select r.id, r.provider_id, r.prompt_version, r.checks from pipeline.provider_description_reads r$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$                   and r.tries < v_tries
                   and ((select$o$,
  $n$                   and r.tries < v_tries
                   and (not v_over or security.pdesc_on_demand_live_v1(r.checks))
                   and ((select$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$                 order by case when v_mach then$o$,
  $n$                 order by security.pdesc_on_demand_live_v1(r.checks) desc, case when v_mach then$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$                and (c.provider_id = any(v_reoffer) or coalesce($o$,
  $n$                and (c.provider_id = any(v_reoffer) or security.pdesc_on_demand_live_v1(c.checks) or coalesce($n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(c.prompt_version,'provider-description-v2')))$o$,
  $n$security.provider_description_signature_v1((select coalesce(a.content_hash,a.id::text) from pipeline.evidence_artifacts a where a.id=(v_stored->>c.provider_id::text)::uuid),v_model,coalesce(v_pv,c.prompt_version,'provider-description-v2')))$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, checks=$o$,
  $n$  upd as (update pipeline.provider_description_reads r set state = 'reading', tries = r.tries + 1, prompt_version = coalesce(v_pv, r.prompt_version), checks=$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id,$o$,
  $n$  select coalesce(jsonb_agg(jsonb_build_object('item_id', u.id, 'provider_id', u.provider_id, 'on_demand', security.pdesc_on_demand_live_v1(u.checks),$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$  return jsonb_build_object('model', v_model,$o$,
  $n$  return jsonb_build_object('model', v_model, 'prompt', security.provider_description_prompt_active_v1(),$n$);

-- on demand checks the platform-wide AI rule only (credit floor, platform daily ceiling): security.ai_use_refusal_v1 applies a lane's own guard
-- only to a use that has one, and 'provider_description_on_demand' has none
select pg_temp.pdesc_swap('public.svc_provider_description_next(integer)'::regprocedure,
  $o$  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if;$o$,
  $n$  if not security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end) then return jsonb_build_object('idle', true, 'reason', 'ai_refused', 'items', '[]'::jsonb); end if; -- 20261112010000$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'::regprocedure,
  $o$ if security.pipeline_num_v1('pdesc.enabled',0)<1 or not security.ai_use_allowed_v1('provider_description') then$o$,
  $n$ if security.pipeline_num_v1('pdesc.enabled',0)<1 or not security.ai_use_allowed_v1(case when security.pdesc_on_demand_live_v1(r.checks) then 'provider_description_on_demand' else 'provider_description' end) then -- 20261112010000$n$);
select pg_temp.pdesc_swap('security.provider_description_fire_v1()'::regprocedure,
  $o$  if not security.ai_use_allowed_v1('provider_description') then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if;$o$,
  $n$  if not security.ai_use_allowed_v1(case when security.pdesc_on_demand_due_v1() then 'provider_description_on_demand' else 'provider_description' end) then return jsonb_build_object('queued', v_q, 'ai', 'stopped', 'dead_letter', v_dead); end if; -- 20261112010000$n$);

-- the fire: an on-demand read is dispatched even while the lane ceiling is reached
select pg_temp.pdesc_swap('security.provider_description_fire_v1()'::regprocedure,
  $o$  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) then$o$,
  $n$  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening') >= security.pipeline_num_v1('pdesc.ai_usd_max', 1) and not security.pdesc_on_demand_due_v1() then -- 20261112010000$n$);

-- the reservation: the active prompt's memory; on demand is not held by the lane ceiling or the lane daily guard
select pg_temp.pdesc_swap('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'::regprocedure,
  $o$ if not coalesce((security.ops_learning_retry_check_v1($o$,
  $n$ if not security.pdesc_on_demand_live_v1(r.checks) and not coalesce((security.ops_learning_retry_check_v1($n$);
select pg_temp.pdesc_swap('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'::regprocedure,
  $o$ if v_spent+v_reserved+p_max_cost>v_cap then$o$,
  $n$ if v_spent+v_reserved+p_max_cost>v_cap and not security.pdesc_on_demand_live_v1(r.checks) then -- 20261112010000: on demand is not held by the lane ceiling$n$);
select pg_temp.pdesc_swap('public.svc_provider_description_reserve_v1(uuid,text,numeric,text)'::regprocedure,
  $o$ if v_today+v_reserved+p_max_cost>v_daily then$o$,
  $n$ if v_today+v_reserved+p_max_cost>v_daily and not security.pdesc_on_demand_live_v1(r.checks) then -- 20261112010000: nor by the lane daily guard$n$);

-- Firecrawl: an on-demand page read is not held by the daily shares (the monthly plan limit and the directory rule still apply)
select pg_temp.pdesc_swap('public.svc_fc_spend(numeric,text,uuid,text)'::regprocedure,
  $o$  elsif v_od is not null then$o$,
  $n$  elsif p_purpose = 'provider_description_on_demand' then
    v_why := null;  -- 20261112010000: an operator asked for this provider's description (Fill description); the daily shares do not apply
  elsif v_od is not null then$n$);
select pg_temp.pdesc_swap('security.fc_purpose_group_v1(text)'::regprocedure,
  $o$              when p = 'provider_description' then 'pdesc'$o$,
  $n$              when p in ('provider_description', 'provider_description_on_demand') then 'pdesc'$n$);

-- 3 -------------------------------------------------------------------------------------------------------------- validation: the prompt profile
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$v_min_sup numeric := security.pipeline_num_v1('pdesc.support_min_share', 0.6);$o$,
  $n$v_light boolean := security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1; -- 20261112010000: the prompt profile
        v_min_sup numeric := case when security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1 then security.pipeline_num_v1('pdesc.prompt_support_min_share', 0.5) else security.pipeline_num_v1('pdesc.support_min_share', 0.6) end;$n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w$o$,
  $n$      if v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.prompt_refused_words'), '[]'::jsonb)) w where security.pdesc_has_term_v1(t, w)) then
        v_bad := jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'refused_topic', 'checks', v_checks, 'reason', 'a word a description never carries (ranking, award, outcome, promotion, fees, visas): ' || left(t, 120)); exit chk;
      end if;
      if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.superlatives'), '[]'::jsonb)) w$n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$      if exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w$o$,
  $n$      if not v_light and exists (select 1 from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'pdesc.claim_words'), '[]'::jsonb)) w$n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb)$o$,
  $n$case when v_light then '[]'::jsonb else coalesce(security.toolset_setting('pipeline', 'pdesc.evidence_claim_words'), '[]'::jsonb) end$n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$      if exists(select 1 from generate_series($o$,
  $n$      if not v_light and exists(select 1 from generate_series($n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$      if coalesce(s->>'quote','')~* $o$,
  $n$      if not v_light and coalesce(s->>'quote','')~* $n$);
select pg_temp.pdesc_swap('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure,
  $o$  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or$o$,
  $n$  -- 20261112010000 (prompt profile): the first sentence names the provider (no description opens with "It ..." or "They ...")
  if v_light and not exists (select 1 from catalogue.providers p cross join lateral unnest(array[p.canonical_name, p.display_name, p.short_name]) nm
                              where p.id = p_provider and length(btrim(coalesce(nm, ''))) >= security.pipeline_num_v1('pdesc.name_min_chars', 3)
                                and security.pdesc_has_term_v1((select btrim(x->>'text') from jsonb_array_elements(case when v_drop and jsonb_array_length(v_dropped) > 0 then v_keep else v_s end) with ordinality e(x, o) order by o limit 1), btrim(nm))) then
    return jsonb_build_object('ok', false, 'outcome', 'held', 'rule', 'first_sentence_no_name', 'checks', v_checks, 'reason', 'the first sentence does not name the provider');
  end if;
  if length(v_text) < security.pipeline_num_v1('pdesc.min_chars', 150) or$n$);

-- 4 -------------------------------------------------------------------------------------------------------------- on demand: the operator's Fill description
create or replace function public.admin_provider_description_fill_v1(p_provider_ids uuid[]) returns jsonb
language plpgsql security definer set search_path to '' as $fn$
-- CF-247 F-PDESC (Platform Admin 11 Nov 2026 14:57): "a simple button to fill in a provider's description". Each provider is queued at the
-- front (checks.on_demand) and a worker call is started at once. Not held by the lane AI ceiling, the lane daily guard, the Firecrawl allowance
-- or share, or the "same page already failed" memory; a manual lock, the identity proof and the platform-wide AI rule still apply.
declare v_out jsonb := '[]'::jsonb; v_pid uuid; p catalogue.providers%rowtype; r pipeline.provider_description_reads%rowtype; v_q int := 0; v_word text;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'An operator is required' using errcode = '42501'; end if;
  if coalesce(array_length(p_provider_ids, 1), 0) = 0 then raise exception 'choose at least one provider'; end if;
  if array_length(p_provider_ids, 1) > security.pipeline_num_v1('pdesc.fill_max_per_click', 25) then
    raise exception 'one click fills at most % providers (Settings › Pipeline settings › Provider descriptions)', security.pipeline_num_v1('pdesc.fill_max_per_click', 25)::int;
  end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then raise exception 'The provider description reader is switched off'; end if;
  foreach v_pid in array p_provider_ids loop
    select * into p from catalogue.providers where id = v_pid;
    v_word := null;
    if p.id is null then v_word := 'not_found';
    elsif exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all')) then v_word := 'manual';
    elsif nullif(btrim(p.description), '') is not null and security.provider_description_basic_profile_v1(p.id) is null then v_word := 'has_description';
    elsif p.lifecycle_status <> 'active' or p.publication_status <> 'published' then v_word := 'not_live';
    elsif not coalesce((security.provider_description_identity_v1(p.id, coalesce((select a.source_url from pipeline.evidence_artifacts a where a.id = security.provider_description_stored_v1(p.id)), p.website))->>'ok')::boolean, false) then v_word := 'identity';
    end if;
    if v_word is null then
      select * into r from pipeline.provider_description_reads x where x.provider_id = p.id and x.state in ('queued', 'reading', 'proposed') limit 1;
      if r.id is not null and r.state in ('reading', 'proposed') then v_word := 'in_progress';
      elsif r.id is not null then
        update pipeline.provider_description_reads set next_try_at = now(), tries = 0, updated_at = now(),
               checks = coalesce(checks, '{}'::jsonb) || jsonb_build_object('on_demand', jsonb_build_object('by', auth.uid(), 'at', now()))
         where id = r.id;
        v_word := 'queued'; v_q := v_q + 1;
      else
        -- a new read: earlier reads stay as they are (the admission ledger refers to them)
        insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
        values (p.id, 'queued', now(), 'Operator asked to fill the description (on demand)', jsonb_build_object('on_demand', jsonb_build_object('by', auth.uid(), 'at', now())));
        v_word := 'queued'; v_q := v_q + 1;
      end if;
    end if;
    v_out := v_out || jsonb_build_object('provider_id', v_pid, 'name', coalesce(p.display_name, p.canonical_name), 'outcome', v_word);
  end loop;
  if v_q > 0 then
    perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'provider_description', 'limit', security.pipeline_num_v1('batch.provider_description', 3)::int));
  end if;
  return jsonb_build_object('queued', v_q, 'providers', v_out);
end $fn$;
comment on function public.admin_provider_description_fill_v1(uuid[]) is 'CF-247 F-PDESC (20261112010000): the operator''s Fill description. Queues each provider on demand (not held by the lane AI and Firecrawl limits) and starts a worker call; skips a manually maintained description.';
revoke all on function public.admin_provider_description_fill_v1(uuid[]) from public, anon;
grant execute on function public.admin_provider_description_fill_v1(uuid[]) to authenticated;

-- the Platform Admin's prompt editor
create or replace function public.admin_provider_description_prompt_v1(p_action text, p_args jsonb default '{}'::jsonb) returns jsonb
language plpgsql security definer set search_path to '' as $fn$
-- CF-247 F-PDESC (20261112010000): read (rank 3 and above, as Fill) and save (Platform Admin, with a reason). A save is a new active version.
declare v_text text := btrim(coalesce(p_args->>'system_prompt', '')); v_reason text := btrim(coalesce(p_args->>'reason', '')); v_ver int;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 3 then raise exception 'not allowed' using errcode = '42501'; end if; -- the same rank as Fill and the Enrich fields tab
  if p_action = 'read' then
    return jsonb_build_object(
      'prompt_on', security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1,
      'can_edit', coalesce(security.current_role_rank(), 0) >= 6,
      'active', (select to_jsonb(x) from (select version, system_prompt, reason, created_at, activated_at from pipeline.provider_description_prompts where status = 'active') x),
      'history', (select coalesce(jsonb_agg(to_jsonb(x) order by x.version desc), '[]'::jsonb) from (select version, status, reason, created_at, activated_at, left(system_prompt, 160) preview from pipeline.provider_description_prompts order by version desc limit 20) x),
      'refused_words', security.toolset_setting('pipeline', 'pdesc.prompt_refused_words'),
      'length', jsonb_build_object('min_sentences', security.pipeline_num_v1('pdesc.min_sentences', 2), 'max_sentences', security.pipeline_num_v1('pdesc.max_sentences', 5),
                                   'min_chars', security.pipeline_num_v1('pdesc.min_chars', 150), 'max_chars', security.pipeline_num_v1('pdesc.max_chars', 900)),
      -- AI spend, Firecrawl use, controls and progress for the screens (Platform Admin 11 Nov 2026 06:11: "should be visible on UI")
      'status', jsonb_build_object(
        'ai_spent_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening'),
        'ai_ceiling_usd', security.pipeline_num_v1('pdesc.ai_usd_max', 1),
        'ai_today_usd', (select round(coalesce(sum(l.cost_usd), 0), 4) from pipeline.ai_spend_ledger l where l.lane = 'provider_description' and l.source <> 'opening' and l.at >= date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'),
        'ai_daily_guard_usd', coalesce((security.toolset_setting('openrouter', 'guard_provider_description') #>> '{}')::numeric, 1),
        'firecrawl_used_window', (select coalesce(sum(x.firecrawl_reads), 0) from pipeline.provider_description_reads x where x.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int)),
        'firecrawl_allowance', security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0), 'firecrawl_window_hours', security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24),
        'firecrawl_share_left_today', security.fc_budget_left_v1('provider_description'), 'firecrawl_share_day', security.fc_setting_num_v1('daily_share_pdesc', 0),
        'reader_every_minutes', security.pipeline_num_v1('pdesc.every_minutes', 10), 'batch', security.pipeline_num_v1('batch.provider_description', 3),
        'admitted_24h', (select count(*) from pipeline.provider_description_machine_admissions a where a.outcome = 'admitted' and a.created_at > now() - interval '24 hours'), -- fixed: a display window
        'described', (select count(*) from catalogue.providers p where nullif(btrim(p.description), '') is not null and p.lifecycle_status = 'active' and p.publication_status = 'published'),
        'queued', (select count(*) from pipeline.provider_description_reads x where x.state = 'queued'),
        'on_demand_waiting', (select count(*) from pipeline.provider_description_reads x where x.state in ('queued', 'reading') and security.pdesc_on_demand_live_v1(x.checks)),
        'held', (select count(*) from pipeline.provider_description_reads x where x.state = 'held'),
        'manual', (select count(*) from pipeline.manual_locks l where l.entity = 'provider' and l.field in ('description', 'p_description')),
        'self_heal_last', (select jsonb_build_object('at', d.start_time, 'status', d.status) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-self-heal' order by d.start_time desc limit 1),
        'reader_last', (select jsonb_build_object('at', d.start_time, 'status', d.status) from cron.job_run_details d join cron.job j on j.jobid = d.jobid where j.jobname = 'provider-description-read' order by d.start_time desc limit 1)));
  elsif p_action = 'save' then
    if coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
    if length(v_reason) < 4 then raise exception 'a reason is required'; end if;
    if length(v_text) < 200 then raise exception 'the prompt is too short (200 characters or more)'; end if; -- fixed: the table's own check (a prompt is never empty)
    if v_text = (select system_prompt from pipeline.provider_description_prompts where status = 'active') then raise exception 'the prompt is unchanged'; end if;
    perform pg_advisory_xact_lock(hashtext('cf247 provider description prompt'));
    select coalesce(max(version), 2) + 1 into v_ver from pipeline.provider_description_prompts;
    update pipeline.provider_description_prompts set status = 'retired' where status = 'active';
    insert into pipeline.provider_description_prompts(version, system_prompt, status, reason, created_by, activated_at, activated_by)
    values (v_ver, v_text, 'active', v_reason, auth.uid(), now(), auth.uid());
    return jsonb_build_object('ok', true, 'version', v_ver);
  end if;
  raise exception 'unknown action %', p_action;
end $fn$;
comment on function public.admin_provider_description_prompt_v1(text, jsonb) is 'CF-247 F-PDESC (20261112010000): read and save the provider-description prompt (Models & services › AI & OpenRouter). A save is a new active version with a reason; nothing is edited in place.';
revoke all on function public.admin_provider_description_prompt_v1(text, jsonb) from public, anon;
grant execute on function public.admin_provider_description_prompt_v1(text, jsonb) to authenticated;

-- 6 -------------------------------------------------------------------------------------------------------------- self-heal (c): a new prompt reads failed answers again once
create or replace function security.provider_description_self_heal_v1() returns jsonb
language plpgsql security definer set search_path to '' as $fn$
-- CF-247 F-PDESC (20261110250000, 20261110251000, 20261112010000): the provider-description reader recovers by itself. Writes only through
-- svc_provider_description_record (a) and the read row's own queue fields (b, c). One open read a provider (provider_description_reads_open_uq).
declare r record; v_n int := 0; v_q int := 0; v_p int := 0; v_err int := 0; v_out jsonb; v_tally jsonb := '{}'::jsonb; v_fc_used int; v_fc_ok boolean;
        v_pv text := security.provider_description_prompt_active_v1()->>'version'; v_max int := greatest(0, security.pipeline_num_v1('pdesc.self_heal_requeue_per_run', 20)::int);
begin
  if not pg_try_advisory_xact_lock(hashtext('cf247 provider description self heal')) then return jsonb_build_object('skipped', 'in_flight'); end if;
  if security.pipeline_num_v1('pdesc.enabled', 0) < 1 then return jsonb_build_object('enabled', false); end if;
  -- (a) answers held only for the model's flag: the stored sentences are recorded again (the read is leased now, exactly as the reader leases it)
  for r in select x.id, x.provider_id from pipeline.provider_description_reads x
            where x.state = 'held' and x.rule = 'not_stated' and x.evidence_id is not null
              and jsonb_array_length(coalesce(x.proposal->'sentences', '[]'::jsonb)) > 0
              and not coalesce(x.checks ? 'self_heal', false)
            order by x.updated_at desc
            limit greatest(0, security.pipeline_num_v1('pdesc.self_heal_per_run', 5)::int) loop
    begin
      if exists (select 1 from pipeline.provider_description_reads o where o.provider_id = r.provider_id and o.state in ('queued', 'reading', 'proposed')) then
        update pipeline.provider_description_reads x set checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('self_heal', jsonb_build_object('at', now(), 'skipped', 'open_read', 'release', '20261112010000'))
         where x.id = r.id;
        v_tally := v_tally || jsonb_build_object('skipped_open_read', coalesce((v_tally->>'skipped_open_read')::int, 0) + 1);
        continue;
      end if;
      update pipeline.provider_description_reads x set state = 'reading', leased_until = now() + interval '5 minutes', -- fixed: one record call
             checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('description_at_lease', (select p.description from catalogue.providers p where p.id = x.provider_id),
                       'identity_snapshot', security.provider_description_identity_snapshot_v1(x.provider_id),
                       'self_heal', jsonb_build_object('at', now(), 'from_rule', 'not_stated', 'release', '20261112010000'))
       where x.id = r.id;
      v_out := public.svc_provider_description_record(jsonb_build_array((select jsonb_build_object('item_id', x.id,
                 'answer', jsonb_build_object('about_page', false, 'sentences', x.proposal->'sentences'),
                 'model', x.model, 'prompt_version', x.prompt_version, 'worker', x.worker) from pipeline.provider_description_reads x where x.id = r.id)));
      v_tally := v_tally || coalesce((select jsonb_object_agg(k, coalesce((v_tally->>k)::int, 0) + coalesce((v_out->>k)::int, 0)) from jsonb_object_keys(coalesce(v_out, '{}'::jsonb)) k), '{}'::jsonb);
      v_n := v_n + 1;
    exception when others then
      v_err := v_err + 1;  -- the sub-transaction is rolled back; the read stays as it was and is offered again next run
    end;
  end loop;
  -- (b) reads that stopped only because the Firecrawl allowance was used up go back in the queue once the window allows Firecrawl again
  select coalesce(sum(x.firecrawl_reads), 0) into v_fc_used from pipeline.provider_description_reads x
   where x.updated_at > now() - make_interval(hours => security.pipeline_num_v1('pdesc.firecrawl_window_hours', 24)::int);
  v_fc_ok := security.pipeline_num_v1('pdesc.acquire_firecrawl', 0) >= 1 and v_fc_used < security.pipeline_num_v1('pdesc.firecrawl_reads_max', 0);
  if v_fc_ok then
    for r in select distinct on (x.provider_id) x.id, x.provider_id, x.updated_at from pipeline.provider_description_reads x
              where x.state = 'held' and x.reason ilike '%Firecrawl ceiling reached%'
                and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = x.provider_id and o.state in ('queued', 'reading', 'proposed'))
              order by x.provider_id, x.updated_at desc loop
      exit when v_q >= v_max;
      begin
        update pipeline.provider_description_reads x set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = null,
               reason = 'put back: the Firecrawl allowance renewed (provider-description-self-heal)', updated_at = now()
         where x.id = r.id and x.state = 'held';
        v_q := v_q + 1;
      exception when others then
        v_err := v_err + 1;
      end;
    end loop;
  end if;
  -- (c) 20261112010000: the latest read of a provider still without a description, held on an AI-answer check under an older prompt version, is read
  -- again once with the active prompt (the recovery memory counts the prompt version, so the same failure is never asked twice)
  if v_pv is not null then
    for r in select l.id from (select distinct on (x.provider_id) x.id, x.provider_id, x.state, x.rule, x.prompt_version, x.updated_at
                                 from pipeline.provider_description_reads x order by x.provider_id, x.created_at desc) l
              join catalogue.providers p on p.id = l.provider_id
             where l.state = 'held' and coalesce(l.prompt_version, '') is distinct from v_pv
               and coalesce(security.toolset_setting('pipeline', 'pdesc.prompt_reoffer_rules'), '[]'::jsonb) ? l.rule
               and (nullif(btrim(p.description), '') is null or security.provider_description_basic_profile_v1(p.id) is not null)
               and not exists (select 1 from pipeline.manual_locks k where k.entity = 'provider' and k.entity_id = p.id and k.field in ('description', 'p_description', 'all'))
               and not exists (select 1 from pipeline.provider_description_reads o where o.provider_id = l.provider_id and o.state in ('queued', 'reading', 'proposed'))
             order by l.updated_at desc loop
      exit when v_p >= v_max;
      begin
        update pipeline.provider_description_reads x set state = 'queued', tries = 0, next_try_at = now(), leased_until = null, rule = null,
               reason = 'put back: a new provider-description prompt (' || v_pv || ')', updated_at = now()
         where x.id = r.id and x.state = 'held';
        v_p := v_p + 1;
      exception when others then
        v_err := v_err + 1;
      end;
    end loop;
  end if;
  return jsonb_build_object('rechecked', v_n, 'outcomes', v_tally, 'requeued_firecrawl', v_q, 'requeued_prompt', v_p, 'skipped_error', v_err, 'firecrawl_used_window', v_fc_used, 'firecrawl_open', v_fc_ok, 'prompt_version', v_pv);
end $fn$;
comment on function security.provider_description_self_heal_v1() is 'CF-247 F-PDESC (20261110250000, 20261110251000, 20261112010000): job provider-description-self-heal. Re-records held not_stated reads with stored sentences (no AI), requeues reads stopped by the Firecrawl allowance once it renews, and reads failed AI answers again once for a new prompt version.';
revoke all on function security.provider_description_self_heal_v1() from public, anon, authenticated;

-- 7 -------------------------------------------------------------------------------------------------------------- register
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.provider_description_prompts', 'Layer 2', 'Provider descriptions', 'F-PDESC: the provider-description prompt, versioned', 'active', '{}', '20261112010000'),
 ('function', 'security.provider_description_prompt_active_v1', 'Layer 2', 'Provider descriptions', 'F-PDESC: the active prompt for the lease', 'active', '{}', '20261112010000'),
 ('function', 'public.admin_provider_description_fill_v1', 'Layer 2', 'Provider descriptions', 'F-PDESC: Fill description (on demand)', 'active', '{}', '20261112010000'),
 ('function', 'public.admin_provider_description_prompt_v1', 'Layer 2', 'Provider descriptions', 'F-PDESC: the prompt editor', 'active', '{}', '20261112010000')
on conflict do nothing;
insert into pipeline.component_register(kind, name, layer, area, purpose, status, replaces, replaced_by, introduced_in, retire_after) values
 ('screen', 'ProviderDescriptionRunValidate', 'Layer 2', 'Provider descriptions', 'Run & Validate card (cohort preview, prepare, run)', 'retiring', '{}', 'Fill description button and the provider description prompt', '20261112010000', current_date + 14)
on conflict (kind, name) do update set status = 'retiring', replaced_by = excluded.replaced_by, retire_after = excluded.retire_after, updated_at = now();

-- post-checks
do $post$
declare d text;
begin
  if security.provider_description_prompt_active_v1()->>'version' <> 'provider-description-p3' then raise exception 'post-check: active prompt'; end if;
  d := pg_get_functiondef('public.svc_provider_description_next(integer)'::regprocedure);
  if position('on_demand' in d) = 0 or position('prompt_active_v1' in d) = 0 then raise exception 'post-check: lease'; end if;
  if position('first_sentence_no_name' in pg_get_functiondef('security.provider_description_validate_v1(uuid,text,timestamptz,jsonb)'::regprocedure)) = 0 then raise exception 'post-check: validate'; end if;
  if security.fc_purpose_group_v1('provider_description_on_demand') <> 'pdesc' then raise exception 'post-check: Firecrawl group'; end if;
end $post$;
