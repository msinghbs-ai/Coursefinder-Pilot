-- CF-247 s775: no-page-propose no longer times out in its match-scope refresh (IQ-00426; Platform Admin 19 Nov 2026 15:18 AEDT, chat S1-Build).
-- Measured in rolled-back live dry runs (GitHub Actions, 19 Nov 2026 15:20-15:35 AEDT):
--   * no-page-propose failed at 11:37 and 13:37 on the 120 s statement limit and ran 90-102 s otherwise. The failures are in its first step,
--     security.bind_match_scope_refresh_v1 ("pipeline_list_v1 ... enrich_focus_v1 ... insert into pipeline.bind_match_scope"), not in the
--     candidate query (2.5 s) that a smaller provider batch would shorten.
--   * The refresh calls security.enrich_focus_v1(provider) once for every unlinked active Australian course (tens of thousands of calls), although
--     its answer depends only on the provider (859 providers). Inside it, security.flag_provider_held_v1 took about 13 ms a call: the only
--     index on pipeline.enrichment_flags by provider holds every raised flag of the provider, course flags included, while the function asks
--     for provider flags only (857 of 95,536 rows).
-- What changes (md5-guarded; no table, column or job; signatures and grants unchanged):
--   1. Index enrichment_flags_provider_raised_idx (provider_id, reason_code) for raised provider flags: the flag check took 0.34 ms a call
--      with it in the dry run (was about 13 ms).
--   2. security.bind_match_scope_refresh_v1 groups the unlinked courses by provider first, then checks the focus rule once per provider, in
--      order of courses without a page, stopping at the bind.match_scope_top_n providers that pass; providers with a tranche override are
--      checked and kept as before. The rows written are the same: the providers outside focus that are overrides or among the top N by
--      courses without a page, with the same reason and count (providers with equal counts at the cut-off were and are taken in no set order).
-- Replaces: the per-course focus check of the match-scope refresh.
-- Retires: nothing.
-- G1: no job added or changed. G2: no new setting. G3: untouched.

create index if not exists enrichment_flags_provider_raised_idx
  on pipeline.enrichment_flags (provider_id, reason_code) where state = 'raised' and entity = 'provider';
comment on index pipeline.enrichment_flags_provider_raised_idx is
  's775 (19 Nov 2026, IQ-00426): raised provider-level flags by provider and reason, for security.flag_provider_held_v1 (the focus rule and the hold checks).';

do $$
begin
  if md5(replace(pg_get_functiondef('security.bind_match_scope_refresh_v1()'::regprocedure), chr(13), '')) <> '752a2ae75ca9ae3965ecbb6b520f7738' then
    raise exception 'pre-check: security.bind_match_scope_refresh_v1 changed since it was read (19 Nov 2026 15:30)';
  end if;
end $$;

create or replace function security.bind_match_scope_refresh_v1()
 returns integer
 language plpgsql
 security definer
 set search_path to ''
as $function$
declare v_n int; v_top int := security.pipeline_num_v1('bind.match_scope_top_n', 100)::int;
begin
  -- s775 (IQ-00426): unlinked Australian courses grouped by provider first; the focus rule (security.enrich_focus_v1) is checked once per
  -- provider, in order of courses without a page, until v_top providers pass; tranche overrides are checked and kept as before
  with u as materialized (
    select c.provider_id, count(*) unbound
      from catalogue.courses c join catalogue.providers p on p.id = c.provider_id join ref.countries k on k.id = p.country_id
     where c.lifecycle_status = 'active' and k.iso_alpha2 = 'AU'
       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = c.provider_id)
       and not exists (select 1 from catalogue.course_links l where l.course_id = c.id and l.link_type = 'official_course' and l.status = 'active')
     group by c.provider_id),
  ovr as materialized (
    select u.provider_id from u where exists (select 1 from pipeline.firecrawl_targets t where t.provider_id = u.provider_id and t.included)),
  top as materialized (
    -- offset 0 keeps the focus check above the ordering, so it stops once v_top providers have passed
    select s.provider_id from (select u.provider_id, u.unbound from u order by u.unbound desc offset 0) s
     where not security.enrich_focus_v1(s.provider_id) limit v_top),
  keep as (
    select u.provider_id, case when u.provider_id in (select provider_id from ovr) then 'tranche override' else 'top by courses without a page' end why, u.unbound
      from u
     where u.provider_id in (select provider_id from top)
        or (u.provider_id in (select provider_id from ovr) and not security.enrich_focus_v1(u.provider_id)))
  insert into pipeline.bind_match_scope(provider_id, why, unbound)
  select k.provider_id, k.why, k.unbound from keep k
  on conflict (provider_id) do update set why = excluded.why, unbound = excluded.unbound, refreshed_at = now();
  get diagnostics v_n = row_count;
  return v_n;
end $function$;

-- post-checks
do $$
declare v_t timestamptz; v_ms numeric; v_ms2 numeric; v_n int; v jsonb;
begin
  if position('top as materialized' in (select prosrc from pg_proc where oid = 'security.bind_match_scope_refresh_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: the match-scope refresh is not the per-provider version';
  end if;
  if to_regclass('pipeline.enrichment_flags_provider_raised_idx') is null then raise exception 'post-check: the provider flag index is missing'; end if;
  v_t := clock_timestamp();
  v_n := security.bind_match_scope_refresh_v1();
  v_ms := extract(epoch from clock_timestamp() - v_t) * 1000;
  v_t := clock_timestamp();
  v := security.no_page_propose_v1();
  v_ms2 := extract(epoch from clock_timestamp() - v_t) * 1000;
  perform set_config('cf.diag', coalesce(current_setting('cf.diag', true), '') || format('s775 scope_rows=%s scope_ms=%s no_page_propose_ms=%s result=%s; ', v_n, round(v_ms), round(v_ms2), v), true);
  if v_ms > 30000 then raise exception 'post-check: the match-scope refresh took % ms', round(v_ms); end if;  -- fixed: post-check bound
  if v_ms2 > 60000 then raise exception 'post-check: no-page-propose took % ms', round(v_ms2); end if;  -- fixed: post-check bound
end $$;
