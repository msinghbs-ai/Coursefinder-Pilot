-- CF-247 (19 Oct 2026). Platform Admin 22:47: "finish unis without adapter in waves, following scholarship and data enrichment"; choice
-- "20+ and 5-19 re-find; 1-4 CRICOS-only (Recommended)" (one Firecrawl re-find per provider that enrols international students).
-- Found: of the 169 stopped providers with 5 or more courses that enrol international students, 42 never had their site mapped. Their
-- discovery was skipped while the daily Firecrawl map allowance was used up ("map:budget"), each skip counted as a try, and after three it
-- stopped for good; since 15 Oct page search and discovery run only for the top 50 Australian focus providers (Waste rules), so nothing
-- tried again. A plain onboarding retry would therefore search nothing new.
-- 1 security.enrich_focus_v1: a provider in a re-find wave (Layer 2 > Build adapter wave named "refind-...") is in focus, so its page
--   search, site map and AI page matching run while it is in that wave. The top-50 rule is unchanged for everyone else.
-- 2 Site discovery tried again from scratch (attempts 0, due now) for providers in a re-find wave whose last discovery never mapped the
--   site (skipped for the map allowance) or failed; their URL lists are kept.
-- The wave itself is started from Layer 2 > Build adapter (or admin_adapter_build 'build' with a wave name), under the Platform Admin;
-- security.refind_wave_discovery_v1(wave) then re-opens discovery for it.
-- Replaces: security.enrich_focus_v1(uuid) (re-find waves added; nothing else changes)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $chk$ begin
  if md5(pg_get_functiondef('security.enrich_focus_v1(uuid)'::regprocedure)) <> '73e1bcfd65528f5ae1e922a28437eeef' then
    raise exception 'live security.enrich_focus_v1 differs from the definition this change replaces';
  end if;
end $chk$;

CREATE OR REPLACE FUNCTION security.enrich_focus_v1(p_provider_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- page search runs for every provider when the setting is 0, for providers outside Australia, and for the Australian focus providers
  -- CF-247 19 Oct 2026: and for a provider in a re-find wave (Layer 2 > Build adapter, wave named "refind-...")
  select security.pipeline_num_v1('enrich.focus_top_n', 50) = 0
      or coalesce(security.coverage_country(p_provider_id), '') <> 'AU'
      or exists (select 1 from pipeline.enrich_focus_providers f where f.provider_id = p_provider_id and f.in_focus)
      or exists (select 1 from pipeline.adapter_builds b where b.provider_id = p_provider_id and b.wave like 'refind-%')
$function$;

-- Discovery again for re-find wave providers whose site was never mapped. Run once per wave after the wave is started (service only);
-- safe to run again (only rows that failed, were skipped for the allowance or are missing are touched).
CREATE OR REPLACE FUNCTION security.refind_wave_discovery_v1(p_wave text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_n int := 0; v_new int := 0;
begin
  if p_wave is null or p_wave not like 'refind-%' then return 0; end if;
  update pipeline.coverage_provider_discovery d set status = 'pending', attempts = 0, next_due_at = now(), leased_until = null, updated_at = now(),
         last_error = coalesce(d.last_error, '') || ' | tried again for wave ' || p_wave
    from pipeline.adapter_builds b join catalogue.providers p on p.id = b.provider_id
   where b.wave = p_wave and d.provider_id = b.provider_id and nullif(p.website, '') is not null
     and (d.status = 'failed' or (d.status = 'pending' and d.attempts > 0) or coalesce(d.method, '') like '%map:budget%');
  get diagnostics v_n = row_count;
  insert into pipeline.coverage_provider_discovery(provider_id, website, status, attempts, next_due_at, updated_at)
  select b.provider_id, p.website, 'pending', 0, now(), now()
    from pipeline.adapter_builds b join catalogue.providers p on p.id = b.provider_id
   where b.wave = p_wave and nullif(p.website, '') is not null
  on conflict (provider_id) do nothing;
  get diagnostics v_new = row_count;
  return v_n + v_new;
end $function$;
revoke execute on function security.refind_wave_discovery_v1(text) from public, anon, authenticated;
comment on function security.refind_wave_discovery_v1(text) is 'CF-247 19 Oct 2026: site discovery tried again for the providers of a re-find wave whose site was never mapped';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('function', 'security.refind_wave_discovery_v1', 'Layer 2', 'Re-find waves: site discovery again for providers whose site was never mapped', 'active', '20261019110000')
on conflict (kind, name) do nothing;
