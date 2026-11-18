-- CF-247 operating model 3.3.2 (Platform Admin 12 Nov 2026 21:07) and evidence-first crawling (Platform Admin 13 Nov 2026 15:31: "We should use firecrawl
--   for maximize crawling and storing the evidence for layer 3 data admission. the attaching to the course, nationality and other AI prompt based enrichment
--   can take place"): an on-demand request covering course search actually runs course page searches.
-- Evidence (13 Nov 2026 15:40 AEDT): 3,737 course page searches for AER-eligible providers are queued (2,151 courses whose page did not match, 597 with no
--   page, 376 whose bound page now answers 404). svc_course_link_search_next cut every pick to the day's course-search share (800 units, used by 15:00) and the
--   daily picked cap (search.daily_picked_cap), and took only focus providers and target universities. An open on-demand request did not change that: the
--   waiver in svc_fc_spend (#1083) was never reached because nothing was picked, and the worker refused non-target providers before asking the database.
-- What:
--   1. public.svc_course_link_search_next (md5-guarded): two passes. Pass 1 takes the queued searches of providers covered by an open on-demand request
--      whose purpose groups include course search, up to the run size, with no day share, daily picked cap, focus or target-list cut. Pass 2 is the scheduled
--      pick as before (share, daily cap, focus, target list), for every other provider. Both keep every policy: hidden providers, directory sites,
--      search.skip_providers, the stop gate, few/unchecked sites and site list first.
--   2. public.svc_fc_on_demand_covers_v1(provider, purpose): whether an open on-demand request covers the spend; the worker (v0.84.0) asks it before refusing
--      a provider that is not on the target list, so the waiver reaches the database rule (svc_fc_spend) that records it against the request.
-- Guards: G2 (no new value), G3 (no consumer API object), Decision 260; nothing deleted.
-- Live definition this change edits (md5 of pg_get_functiondef, read 13 Nov 2026 15:45 AEDT): public.svc_course_link_search_next 00f7add9839d659f7dfc7efe6bd82216.
-- Replaces: the single scheduled pick of svc_course_link_search_next (now pass 2). Retires: nothing.

create or replace function public.svc_fc_on_demand_covers_v1(p_provider uuid, p_purpose text) returns boolean
language plpgsql stable security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  return p_provider is not null and security.on_demand_request_for_v2(p_provider, p_purpose) is not null;
end $f$;
comment on function public.svc_fc_on_demand_covers_v1(uuid, text) is 'CF-247 operating model 3.3.2: whether an open on-demand request covers a Firecrawl spend (provider and purpose group); the worker asks it before a target-list refusal.';
revoke all on function public.svc_fc_on_demand_covers_v1(uuid, text) from public, anon, authenticated;
grant execute on function public.svc_fc_on_demand_covers_v1(uuid, text) to service_role;

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

select pg_temp.edit_n('public.svc_course_link_search_next(integer)', '00f7add9839d659f7dfc7efe6bd82216', array[
  array[$o$v jsonb; v_stopped uuid[];$o$,
        $n$v jsonb; v_stopped uuid[];
        -- CF-247 operating model 3.3.2: providers of an open on-demand request covering course search (pass 1), the scheduled room (pass 2)
        v_od uuid[]; v_sched int; v_pass int; v_take int; v_part jsonb;$n$],
  array[$o$  v_lim := least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int);
  if v_lim < 1 then return '[]'::jsonb; end if;$o$,
        $n$  -- 13 Nov 2026 (operating model 3.3.2): the share and the daily cap below hold the scheduled pick (pass 2) only; an open on-demand request's
  -- providers are picked first (pass 1) up to the run size
  v_od := array(select distinct x from pipeline.on_demand_requests r, unnest(r.provider_ids) x
                 where r.state = 'open' and r.expires_at > now() and 'firecrawl' = any (r.toolsets)
                   and (r.purpose_groups is null or security.fc_purpose_group_v1('course_link_search') = any (r.purpose_groups)));
  v_sched := greatest(0, least(v_lim, floor(security.fc_budget_left_v1('course_link_search') / 2)::int));
  if v_sched < 1 and cardinality(v_od) = 0 then return '[]'::jsonb; end if;$n$],
  array[$o$  if v_room > 0 then v_lim := least(v_lim, v_room); end if;$o$,
        $n$  if v_room > 0 then v_sched := least(v_sched, v_room); end if;$n$],
  array[$o$  -- 22 Oct 2026 (Platform Admin 18:26): provider-level checks once per provider$o$,
        $n$  v := '[]'::jsonb;
  for v_pass in 1 .. 2 loop
  v_take := case v_pass when 1 then case when cardinality(v_od) > 0 then v_lim else 0 end else least(v_sched, v_lim - jsonb_array_length(v)) end;
  continue when v_take < 1;
  -- 22 Oct 2026 (Platform Admin 18:26): provider-level checks once per provider$n$],
  array[$o$and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true)$o$,
        $n$and (not coalesce((security.firecrawl_setting('target_only') #>> '{}')::boolean, true) or q.provider_id = any (v_od)$n$],
  array[$o$and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id)))$o$,
        $n$and (case when v_pass = 1 then s.provider_id = any (v_od)
                 else not (s.provider_id = any (v_od)) and (v_room > 0 or (v_person and security.link_search_person_task_v1(s.provider_id, s.course_id))) end)$n$],
  array[$o$and (pv.focus or s.requested_at is not null)$o$,
        $n$and (v_pass = 1 or pv.focus or s.requested_at is not null)$n$],
  array[$o$     limit v_lim
     for update of s skip locked$o$,
        $n$     limit v_take
     for update of s skip locked$n$],
  array[$o$into v from upd;
  return v;$o$,
        $n$into v_part from upd;
  v := v || v_part;
  end loop;
  return v;$n$]
], array[1, 1, 1, 1, 1, 1, 1, 1, 1]);

comment on function public.svc_course_link_search_next(integer) is 'Course page searches to send: pass 1 the providers of an open on-demand request covering course search (operating model 3.3.2, no share or daily cap), pass 2 the scheduled pick (day share, daily picked cap, focus, target list). Policies hold in both.';
