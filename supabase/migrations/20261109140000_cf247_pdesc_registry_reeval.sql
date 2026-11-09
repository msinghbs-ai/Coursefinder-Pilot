-- CF-247 F-PDESC (Platform Admin Directive 3, 9 Nov 2026, Blocker C "Registry-factual descriptions"): providers held by the register-fact tier for too few verified facts are looked at again when the required number of facts is lowered.
--
-- Live evidence (read 9 Nov 2026 15:40 AEDT, project fxcwkweaxjtknorudmwp): 472 Canadian providers were held `insufficient_verified_facts` at 2 of 3 required facts (register listing with stored evidence, and location). The Platform Admin
-- set pdesc.registry_min_facts to 2 through the Admin UI (audited, 9 Nov 2026 15:37 AEDT) after reading the first admissions and a rolled-back dry run (100 of 100 Canadian profiles built, each truthful and tied to its register evidence).
-- Without this change those holds would not be read again for pdesc.recheck_days (180): security.provider_description_registry_tier_v1 skips a provider with a recent registry hold and only selects a provider whose latest read
-- is held for a rule in pdesc.registry_after_rules.
--
-- The three edits (made in place, the function is not replaced):
--  1 the latest-read lateral also returns its checks;
--  2 a registry hold made when more facts were needed than are needed now no longer blocks a new look (holds for every other reason, and holds at the current or a lower requirement, still block for pdesc.recheck_days);
--  3 a latest read held `insufficient_verified_facts` by this tier at a higher requirement than the current one is selected again.
-- No new setting, number, job, table or schedule. The facts a profile needs, the machine gate, the withdraw route, the ceilings and the consumer API are unchanged. No AI call, no page read.
--
-- Live definition this change edits (pg_proc.prosrc md5, read 9 Nov 2026): security.provider_description_registry_tier_v1() b14315e77beb36aba6005efbed208b62 -> 1f9cbb77a59ab392a2e59b6aff317adb
-- Replaces: the registry tier's "recent hold" and "retry rule" selection clauses in security.provider_description_registry_tier_v1 (edited in place)
-- Retires: nothing
-- Nothing is dropped or deleted. No consumer API object is touched (G3).

do $g$
begin
  if to_regprocedure('security.provider_description_registry_tier_v1()') is null then raise exception 'required security.provider_description_registry_tier_v1() is missing'; end if;
end $g$;

create or replace function pg_temp.edit_one(p_sig text, p_before text, p_after text, p_old text, p_new text, p_final text) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after or md5(v_src) = p_final then return p_sig || ': already applied'; end if; -- the final md5 covers a second run of the whole chain
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change edits (body md5 %)', p_sig, md5(v_src); end if;
  v_def := replace(v_def, chr(13), '');
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

select pg_temp.edit_one('security.provider_description_registry_tier_v1()', 'b14315e77beb36aba6005efbed208b62', '20813d8101fd3878a183c0afe3ca0f8e',
$old$left join lateral (select x.state, x.rule, x.updated_at from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true$old$,
$new$left join lateral (select x.state, x.rule, x.updated_at, x.checks from pipeline.provider_description_reads x where x.provider_id = p.id order by x.created_at desc, x.id desc limit 1) lr on true$new$, '1f9cbb77a59ab392a2e59b6aff317adb');

select pg_temp.edit_one('security.provider_description_registry_tier_v1()', '20813d8101fd3878a183c0afe3ca0f8e', '7d19ed9f0010ea77975d42f3b2adb322',
$old$h.state = 'held' and h.checks->>'tier' = 'registry_factual' and h.updated_at >$old$,
$new$h.state = 'held' and h.checks->>'tier' = 'registry_factual' and coalesce(case when (h.checks->>'facts_needed') ~ '^[0-9]+$' then (h.checks->>'facts_needed')::numeric end, 0) <= security.pipeline_num_v1('pdesc.registry_min_facts', 3) and h.updated_at >$new$, '1f9cbb77a59ab392a2e59b6aff317adb');

select pg_temp.edit_one('security.provider_description_registry_tier_v1()', '7d19ed9f0010ea77975d42f3b2adb322', '1f9cbb77a59ab392a2e59b6aff317adb',
$old$and ((lr.state = 'held' and v_rules ? lr.rule) or lr.state = 'dead_letter'$old$,
$new$and ((lr.state = 'held' and (v_rules ? lr.rule or (lr.rule = 'insufficient_verified_facts' and lr.checks->>'tier' = 'registry_factual' and (lr.checks->>'facts_needed') ~ '^[0-9]+$' and (lr.checks->>'facts_needed')::numeric > security.pipeline_num_v1('pdesc.registry_min_facts', 3)))) or lr.state = 'dead_letter'$new$, '1f9cbb77a59ab392a2e59b6aff317adb');

comment on function security.provider_description_registry_tier_v1() is 'CF-247 F-PDESC tier 4 (registry_factual): runs the register-fact profile for providers with no page to read; a hold made at a higher facts requirement than the current pdesc.registry_min_facts is looked at again (Directive 3, Blocker C).';
