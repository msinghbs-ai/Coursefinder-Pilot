-- CF-247 S2-BOOST-Discovery (Platform Admin 18 Nov 2026 17:02 item 2: monitor the Course page needed re-search drain and promote what recurs).
-- What was read live (17:25 AEDT)
--   * The course-link search lane has picked nothing since 18 Nov 00:47 AEDT. Whenever it has room to pick (today's share at the day's start, or
--     the on-demand request opened by 20261118200000), public.svc_course_link_search_next ends with "canceling statement due to statement
--     timeout": 97 times in the seven days before that request, and on every tick since it opened. So the 600 Course page needed items rule
--     l4-page-needed-search-v1 sent to the lane are still queued with 0 attempts.
--   * Cause, measured: before it picks, the function works out the provider-level checks (focus, few pages, site checked, tier, directory
--     site) for every provider with a queued search: 306 providers, about 10 seconds, against the 8-second limit of a worker call. The cheap
--     checks (hidden, target list) and the pass a provider belongs to are applied only afterwards. After them 91 providers remain for the
--     on-demand pass and 60 for the scheduled pass.
-- What it changes: in public.svc_course_link_search_next (md5-guarded edit) the list of providers with a queued search is first cut to the
-- providers the pass can take (on-demand providers in pass 1, the others in pass 2), not hidden, and on the target list while Firecrawl is for
-- target universities only (on-demand providers excepted, as before). The provider-level functions then run for those alone. Every later
-- condition is unchanged and still applied, so the same searches are picked in the same order; only the work before the pick is smaller.
-- G2: no value added. G3: no consumer API object. Nothing is dropped or deleted.
-- Live definition this change edits (md5 of pg_get_functiondef, read 18 Nov 2026 17:25 AEDT): fdf5f2f5cd6a7a0be15d7909569d5ce2.
-- Replaces: the unfiltered provider list in public.svc_course_link_search_next
-- Retires: nothing

set local lock_timeout = '5s';

do $e$
declare v_sig regprocedure := 'public.svc_course_link_search_next(integer)'::regprocedure;
        v_def text := pg_get_functiondef(v_sig); v_c int;
        v_old text := $o$from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') q$o$;
        v_new text := $n$from (select d0.provider_id
              from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') d0
             -- 18 Nov 2026 (S657): only the providers this pass can take, and the plain checks first, so the provider-level functions run
             -- for those alone (the pick timed out once more than about 250 providers had a queued search)
             where (case when v_pass = 1 then d0.provider_id = any (v_od) else not (d0.provider_id = any (v_od)) end)
               and not exists (select 1 from security.provider_hidden_v1 h0 where h0.provider_id = d0.provider_id)
               and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or d0.provider_id = any (v_od)
                    or exists (select 1 from pipeline.firecrawl_target_cache tc0 where tc0.provider_id = d0.provider_id and tc0.included))
            offset 0) q$n$;
begin
  if position('18 Nov 2026 (S657)' in v_def) > 0 then raise notice 'already applied'; return; end if;
  if md5(v_def) <> 'fdf5f2f5cd6a7a0be15d7909569d5ce2' then raise exception 'live % differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old);
  if v_c <> 1 then raise exception 'the provider list must be found exactly once (found %)', v_c; end if;
  execute replace(v_def, v_old, v_new);
end $e$;

-- post-checks: the edit is in, the later conditions are still there, and the provider-level work now fits a worker call
do $c$
declare v_def text := pg_get_functiondef('public.svc_course_link_search_next(integer)'::regprocedure);
begin
  if position('18 Nov 2026 (S657)' in v_def) = 0 then raise exception 'post-check: the edit is missing'; end if;
  if position($k$where not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)$k$ in v_def) = 0
     or position($k$and not security.third_party_host_v1('https://' || rc.search_domain)$k$ in v_def) = 0
     or position($k$and (case when v_pass = 1 then s.provider_id = any (v_od)$k$ in v_def) = 0 then
    raise exception 'post-check: a later condition of the pick was lost';
  end if;
end $c$;

do $t$
declare v_od uuid[]; v_pass int; t0 timestamptz; v_n int; v_x int; v_ms numeric; v_limit interval;
begin
  select (regexp_replace(c, '^statement_timeout=', ''))::interval into v_limit
    from pg_roles r, unnest(r.rolconfig) c where r.rolname = 'authenticator' and c like 'statement_timeout=%';
  v_od := array(select distinct x from pipeline.on_demand_requests r, unnest(r.provider_ids) x
                 where r.state = 'open' and r.expires_at > now() and 'firecrawl' = any (r.toolsets)
                   and (r.purpose_groups is null or security.fc_purpose_group_v1('course_link_search') = any (r.purpose_groups)));
  for v_pass in 1 .. 2 loop
    t0 := clock_timestamp();
    select count(*) filter (where security.enrich_focus_v1(q.provider_id)) + count(*) filter (where security.site_few_course_pages_v1(q.provider_id))
         + count(*) filter (where security.site_not_checked_v1(q.provider_id)) + count(security.fc_provider_tier_v1(q.provider_id))
         + count(*) filter (where security.third_party_host_v1('https://' || rc.search_domain)), count(*)
      into v_x, v_n
      from (select d0.provider_id
              from (select distinct s0.provider_id from pipeline.course_link_search s0 where s0.state = 'queued') d0
             where (case when v_pass = 1 then d0.provider_id = any (v_od) else not (d0.provider_id = any (v_od)) end)
               and not exists (select 1 from security.provider_hidden_v1 h0 where h0.provider_id = d0.provider_id)
               and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or d0.provider_id = any (v_od)
                    or exists (select 1 from pipeline.firecrawl_target_cache tc0 where tc0.provider_id = d0.provider_id and tc0.included))
            offset 0) q
      join pipeline.course_link_recipes rc on rc.provider_id = q.provider_id and rc.active;
    v_ms := round(extract(epoch from clock_timestamp() - t0) * 1000);
    raise notice 'S657 pass %: provider-level checks for % providers took % ms (worker call limit %)', v_pass, v_n, v_ms, v_limit;
    if v_limit is not null and v_ms > extract(epoch from v_limit) * 1000 / 2 then  -- fixed: half the call limit is left for the pick itself
      raise exception 'post-check: pass % still spends % ms on provider-level checks (worker call limit %)', v_pass, v_ms, v_limit;
    end if;
  end loop;
end $t$;
