-- CF-247 (24 Oct 2026, v2.15.349). Platform Admin decision D1.4 (19:23): "the target rule reports which condition failed per university —
-- permanent, cache-proof reasons. Catalogued change, its own tiny release." Record: admin repo
-- docs/platform/nz-enrichment-brief/2026-10-24-target-only-audit.md (thread).
-- Why: the target_only audit's write-back (reasons in firecrawl_target_cache.override_reason) was overwritten within a minute, because job
-- firecrawl-targets rebuilds every cache row from security.firecrawl_targets_v1() and override_reason holds a person's override reason.
-- Now: a separate column rule_reason says which condition of the targets rule a university fails (first failing condition, in rule
-- order), worked out by the same minute refresh, so every rule exclusion carries its reason for good. override_reason keeps its meaning
-- (an override set by hand). The rule itself, who is included and every setting are unchanged.
-- Replaces: nothing (security.firecrawl_targets_refresh_v1 edited in place, md5-guarded)
-- Retires: nothing

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

alter table pipeline.firecrawl_target_cache add column if not exists rule_reason text;
comment on column pipeline.firecrawl_target_cache.rule_reason is 'Which condition of the Firecrawl targets rule this university fails (first failing condition, in rule order); null when the rule matches. Worked out each minute by firecrawl-targets (CF-247 v2.15.349)';

create or replace function security.firecrawl_target_rule_reasons_v1() returns table(provider_id uuid, reason text)
language plpgsql stable security definer set search_path = '' as $$
declare v_countries text[]; v_pat text; v_excl text; v_regs text[]; v_min jsonb := '{}'::jsonb; x text;
begin
  -- the same settings and conditions as security.firecrawl_targets_v1, read once
  select coalesce(array_agg(upper(btrim(e))), '{}') into v_countries from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_countries'), '[]'::jsonb)) e;
  v_pat := coalesce(security.firecrawl_setting('target_name_pattern') #>> '{}', '(^|[^a-z])universit(y|ies)([^a-z]|$)');
  v_excl := nullif(btrim(coalesce(security.firecrawl_setting('target_exclude_pattern') #>> '{}', '')), '');
  select coalesce(array_agg(lower(btrim(e))), '{}') into v_regs from jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_registers'), '[]'::jsonb)) e;
  for x in select jsonb_array_elements_text(coalesce(security.firecrawl_setting('target_min_courses'), '[]'::jsonb)) loop
    if x ~ '^\s*[A-Za-z]{2}\s*:\s*[0-9]+\s*$' then v_min := v_min || jsonb_build_object(upper(btrim(split_part(x, ':', 1))), btrim(split_part(x, ':', 2))::int); end if;
  end loop;
  return query
  select c.provider_id,
         case
           when not (k.iso_alpha2::text = any (v_countries)) then 'country ' || k.iso_alpha2 || ' is not a target country'
           when coalesce(p.display_name, p.canonical_name) !~* v_pat then 'name does not match the target name pattern'
           when v_excl is not null and coalesce(p.display_name, p.canonical_name) ~* v_excl then 'name has an excluded word (' || substring(lower(coalesce(p.display_name, p.canonical_name)) from v_excl) || ')'
           when n.n < coalesce((v_min->>k.iso_alpha2::text)::int, 0) then 'fewer than ' || (v_min->>k.iso_alpha2::text) || ' active courses (' || n.n || ')'
           when not (p.enrols_international is true or exists (select 1 from catalogue.provider_registrations r where r.provider_id = p.id and lower(r.registration_scheme) = any (v_regs)))
             then 'no international registration (' || array_to_string(v_regs, ', ') || ') and not marked as enrolling internationals'
         end
    from pipeline.firecrawl_target_cache c
    join catalogue.providers p on p.id = c.provider_id
    join ref.countries k on k.id = p.country_id
    cross join lateral (select count(*)::int n from catalogue.courses cc where cc.provider_id = p.id and cc.lifecycle_status = 'active') n;
end $$;
comment on function security.firecrawl_target_rule_reasons_v1() is 'CF-247 v2.15.349: for each university in the Firecrawl target cache, the first condition of the targets rule it fails (null when it matches)';

select pg_temp.edit_n('security.firecrawl_targets_refresh_v1()', '2d3661f1f5e90354e522a0885b9ca9bb', array[
  array[$o$  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;$o$,
        $n$  update pipeline.firecrawl_target_cache set included = false, refreshed_at = now() where refreshed_at < now() - interval '30 seconds' and included;
  -- v2.15.349 (Platform Admin 24 Oct 2026): which rule condition each university fails, kept with the row for good
  update pipeline.firecrawl_target_cache c set rule_reason = r.reason
    from security.firecrawl_target_rule_reasons_v1() r where r.provider_id = c.provider_id and c.rule_reason is distinct from r.reason;$n$]],
  array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.firecrawl_target_rule_reasons_v1', 'Layer 2', 'which Firecrawl targets rule condition each university fails', 'active', '{}', '20261024012000')
on conflict (kind, name) do nothing;

do $t$ declare t timestamptz := clock_timestamp(); begin perform security.firecrawl_targets_refresh_v1();
  raise exception 'DRYRUN OK refresh %ms | excluded: % | included with a failing rule (overrides): % | sample: %', round(extract(epoch from clock_timestamp()-t)*1000),
    (select jsonb_object_agg(k, n) from (select regexp_replace(rule_reason, ' \(.*$', '') k, count(*) n from pipeline.firecrawl_target_cache where not included group by 1) z),
    (select count(*) from pipeline.firecrawl_target_cache where included and rule_reason is not null),
    (select string_agg(name || ': ' || rule_reason, ' / ') from (select name, rule_reason from pipeline.firecrawl_target_cache where not included and country = 'AU' order by name limit 4) s); end $t$;
