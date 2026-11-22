-- CF-247 s981 (S2-Build; Platform Admin consolidated batch 23 Nov 2026 07:16 and 07:45 AEDT, Part 3: IQ-00555 and IQ-00029, coverage-sweep
-- HTTP 500): the scholarship hold check tests the per-university cap before the eligibility rule.
-- Measured live after s978 (rolled-back read-backs, 23 Nov 2026 08:31 to 08:56 AEDT): the listing claim still timed out at 8 s twice under load
-- (21:37 and 21:52 UTC, "svc_scholarship_listing_next: canceling statement due to statement timeout"). Its cost is security.fc_sch_held_v1 for
-- the 29 providers of the due pages: the eligibility rule (security.fc_sch_eligible_v1, about 40 ms quiet, three times that under load) ran for
-- every provider, although 24 of the 29 are held by their cap (the cap sum about 14 ms). security.fc_sch_held_v1 (md5-guarded, in place, same
-- signature) now returns false when the daily budget switch is off, true when the university's scholarship use has reached its cap, and only then
-- asks the eligibility rule. Same rule and same answer (budget_on AND ((discovery AND NOT eligible) OR used >= cap)); cheaper order. A covering
-- partial index serves the cap sum from the index (scholarship purposes only).
-- Every caller of the function (10) gets the same answers, faster. G1: no job. G2: no new value (the cap is the existing setting
-- scholarship_cap_per_uni). G3: no consumer object (checked before and after, 75/48). $0. Nothing dropped or removed.
-- Replaces: the evaluation order inside security.fc_sch_held_v1 (rewritten in place).
-- Retires: nothing.
set local lock_timeout = '5s';  -- fixed: lock wait for the function replace and the index

do $g$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'guard: the consumer API is not at its baseline before this change: %', v;
  end if;
  if position('s981 (23 Nov 2026)' in pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) = 0
     and md5(pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure)) <> 'f8d6fb4bf9196dfa596b8274819670a6' then
    raise exception 'guard: live security.fc_sch_held_v1 differs from the definition this change replaces';
  end if;
end $g$;

-- the definition replaced, kept for this transaction only, for the parity check below
do $o$
declare v_def text := pg_get_functiondef('security.fc_sch_held_v1(uuid,boolean)'::regprocedure);
begin
  if position('s981 (23 Nov 2026)' in v_def) > 0 then return; end if;
  execute replace(v_def, 'CREATE OR REPLACE FUNCTION security.fc_sch_held_v1(', 'CREATE OR REPLACE FUNCTION pg_temp.s981_old_held(');
end $o$;

do $i$
declare v_try int;
begin
  for v_try in 1 .. 10 loop  -- fixed: lock retry count for a busy table
    begin
      perform set_config('lock_timeout', '3s', true);  -- fixed: lock wait per try
      execute 'create index if not exists coverage_vendor_usage_sch_provider_at_idx on pipeline.coverage_vendor_usage (provider_id, at) include (units) where purpose like ''sch\_%''';
      exit;
    exception when lock_not_available then
      if v_try = 10 then raise; end if;
      perform pg_sleep(2);  -- fixed: pause between lock tries
    end;
  end loop;
  perform set_config('lock_timeout', '5s', true);  -- fixed: back to this change's lock wait
end $i$;

CREATE OR REPLACE FUNCTION security.fc_sch_held_v1(p_provider_id uuid, p_discovery boolean)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- D16 (31 Oct 2026): PL/pgSQL so its query plans are kept for the session; same rule as the SQL version
  -- s981 (23 Nov 2026, IQ-00555): same rule, cheaper order: the budget switch, then the per-university cap (one indexed sum), and the eligibility
  -- rule only for a university under its cap (24 of the 29 providers the listing claim checks are held by their cap)
  if not coalesce((select (s.value #>> '{}')::boolean from pipeline.platform_toolset_settings s where s.toolset_key = 'firecrawl' and s.key = 'daily_budget_on'), false) then
    return false;
  end if;
  if (select coalesce(sum(x.units), 0) from pipeline.coverage_vendor_usage x where x.provider_id = p_provider_id and x.purpose like 'sch\_%' and x.at > security.fc_sch_cap_since_v1(p_provider_id))
     >= security.fc_setting_num_v1('scholarship_cap_per_uni', 150) then
    return true;
  end if;
  return p_discovery and not security.fc_sch_eligible_v1(p_provider_id);
end $function$;

-- parity: the same answer as the replaced definition for every provider with a scholarship listing page or discovery row, both modes
do $p$
declare v_diff int;
begin
  if to_regprocedure('pg_temp.s981_old_held(uuid,boolean)') is null then return; end if;
  select count(*) into v_diff
    from (select distinct provider_id from pipeline.scholarship_listing_pages union select provider_id from pipeline.scholarship_discovery_providers) p,
         (values (true), (false)) m(disc)
   where pg_temp.s981_old_held(p.provider_id, m.disc) is distinct from security.fc_sch_held_v1(p.provider_id, m.disc);
  if v_diff <> 0 then raise exception 'parity: % provider answers differ from the replaced definition', v_diff; end if;
end $p$;

do $c$
declare v jsonb := security.consumer_api_check_v1();
begin
  if jsonb_array_length(coalesce(v->'drift', '[]'::jsonb)) <> 0 or (v->>'functions')::int <> 75 or (v->>'relations')::int <> 48 then
    raise exception 'post-check: the consumer API moved: %', v;
  end if;
end $c$;
