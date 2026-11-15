-- CF-247 Models & services › AI loads again (Platform Admin 16 Nov 2026 07:41: "Opening Models & services › AI currently fails with: The database
-- took too long to answer and stopped the request").
-- Cause (measured 16 Nov 2026 on fxcwkweaxjtknorudmwp, read-only, as a Platform Admin): public.admin_ai_overview_v1() took 5.6 to 20.7 s, over the
--   website/admin statement limit. Its parts together took about 3 s; the rest came from its services list: the lateral subquery
--   (select security.ai_route_v1(r.service_code) j) rt is a simple subquery, so the planner pulled it up and evaluated security.ai_route_v1 again
--   for every one of its 15 rt.j references, about 225 route evaluations instead of 15.
-- Fix:
--   1. "offset 0" keeps that subquery as one evaluation per service (a planner fence; same rows, same answer). In a rolled-back live run the
--      read took 1.0 to 1.1 s and returned the same 167,300 characters.
--   2. An index for the last call of each service (pipeline.ai_invocations service_code, at desc, id desc): 449 ms of backward index scans today.
--   3. An index for the page's last 20 changes (pipeline.admin_control_events area, created_at desc): a sequential scan of 114 MB today.
--   4. The read also returns the prompt registry's parity report (security.prompt_registry_parity_v1, v2.16.9) for the AI tab.
-- The edit is md5-guarded against the live definition and must match exactly once each. No write path, no worker and no consumer API object
-- changes (G3: security.consumer_api_check_v1() before and after).
-- Replaces: public.admin_ai_overview_v1() (same name and signature; md5-guarded edit in place). Retires: nothing. Nothing is dropped or deleted.

set local lock_timeout = '5s';

create index if not exists ai_invocations_service_at_idx on pipeline.ai_invocations (service_code, at desc, id desc);
create index if not exists admin_control_events_area_created_idx on pipeline.admin_control_events (area, created_at desc);

-- 2. The edit helper (this transaction only) ------------------------------------------------------------------------------------------------
-- p_edits: one row per edit {kind, old, new, n}: kind 'swap' replaces old with new; kind 'mark' appends " -- fixed: <new>" to each line that
-- contains old. Each edit must match exactly n times, or nothing is changed.
create or replace function pg_temp.cf_g2_edit(p_fn text, p_md5 text, p_done text, p_edits jsonb) returns text language plpgsql as $edit$
declare v_def text := pg_get_functiondef(p_fn::regprocedure); v_new text; e jsonb; v_n int; v_pat text;
begin
  if position(p_done in v_def) > 0 then return 'already'; end if;
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_fn, md5(v_def); end if;
  v_new := v_def;
  for e in select * from jsonb_array_elements(p_edits) loop
    v_n := (length(v_new) - length(replace(v_new, e->>'old', ''))) / length(e->>'old');
    if v_n <> (e->>'n')::int then raise exception '%: "%" found % time(s), expected %', p_fn, e->>'old', v_n, e->>'n'; end if;
    if e->>'kind' = 'swap' then
      v_new := replace(v_new, e->>'old', e->>'new');
    else
      v_pat := regexp_replace(e->>'old', '([.^$*+?()\[\]{}|\\])', '\\\1', 'g') || '[^\n]*';
      v_new := regexp_replace(v_new, v_pat, '\& -- fixed: ' || (e->>'new'), 'g');
    end if;
  end loop;
  if position(p_done in v_new) = 0 then raise exception '%: the edited definition does not carry %', p_fn, p_done; end if;
  execute v_new;
  return md5(pg_get_functiondef(p_fn::regprocedure));
end $edit$;

-- 3. The edit -------------------------------------------------------------------------------------------------------------------------------
do $$
declare v_out text;
begin
  v_out := pg_temp.cf_g2_edit('public.admin_ai_overview_v1()', 'c757ac6eed57a7e7a9945ed8fd7205fe', 'j offset 0) rt', jsonb_build_array(
       jsonb_build_object('kind', 'swap', 'old', 'cross join lateral (select security.ai_route_v1(r.service_code) j) rt', 'new', 'cross join lateral (select security.ai_route_v1(r.service_code) j offset 0) rt', 'n', 1),
       jsonb_build_object('kind', 'swap', 'old', '''guard'', security.ai_route_guard_v1()->''not_allowed_named'',', 'new', '''guard'', security.ai_route_guard_v1()->''not_allowed_named'',
    ''prompt_registry'', security.prompt_registry_parity_v1(),  -- v2.16.10: the prompt registry (shadow) on Models & services › AI', 'n', 1)));
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_models', 'migration', 'public.admin_ai_overview_v1()', jsonb_build_object('migration', '20261116060000', 'md5', v_out,
          'why', 'Models & services › AI timed out: the route state was evaluated once per reference; now once per service'), null);
end $$;

-- 4. Post-check -----------------------------------------------------------------------------------------------------------------------------
do $$
begin
  if position('j offset 0) rt' in pg_get_functiondef('public.admin_ai_overview_v1()'::regprocedure)) = 0
     or position('prompt_registry_parity_v1' in pg_get_functiondef('public.admin_ai_overview_v1()'::regprocedure)) = 0 then
    raise exception 'post-check: public.admin_ai_overview_v1 was not edited';
  end if;
  if to_regclass('pipeline.ai_invocations_service_at_idx') is null or to_regclass('pipeline.admin_control_events_area_created_idx') is null then
    raise exception 'post-check: an index is missing';
  end if;
end $$;
