-- CF-247 S2-BOOST-Discovery (Platform Admin 18 Nov 2026 17:02 item 2: monitor the Course page needed re-search drain and promote what recurs).
-- What was read live (18:50 AEDT), of the 840 Course page needed items rule l4-page-needed-search-v1 has sent to the course-link search lane
-- (state search_requested, so off the Layer 4 list):
--   * 307: the search finished and found no page. Nothing brings such an item back: security.course_page_needed_add_v1 reopens an item only
--     when a page is refused again.
--   * 402: the search is still queued and the lane's stop gate (security.search_stop_gate_v1) holds it: the university search stop 381
--     (Adelaide University, Victoria University, Flinders, Monash, ICMS), no page published by the provider 11, the per-course stop 10. The gate
--     holds on-demand work too, so these searches do not run.
--   * 90 found a page that waits to be read and proved; 41 are queued with the gate open.
--   So 709 courses have left the list with nothing working on them. On-demand request S656 (20261118200000) has run what it could: 998 searches,
--   1,996 credits, no search in its last 20 minutes; while it stays open the lane's on-demand pass still runs close to the worker call limit.
-- What it changes (md5-guarded edit of security.course_page_needed_search_rule_v1; nothing else):
--   1. Before it asks for searches, the rule returns to the list every item it sent whose search found no page or ended in error, or whose
--      queued search the stop gate holds. The item's decision record keeps why (returned_because). The search count is kept.
--   2. It no longer asks for a search the stop gate would hold, nor repeats a search that already found no page for the course. Those items
--      stay on the list for a person, who can still ask again or record that no page exists.
--   3. The run's record and result carry returned_to_list.
--   The S656 on-demand request is closed through security.on_demand_close_v1, which records its actual use.
-- G2: no value added. G3: no consumer API object. Nothing is dropped or deleted.
-- Live definition this change edits (md5 of pg_get_functiondef, read 18 Nov 2026 18:50 AEDT): a2677bf22b788fc41434e50300b256e5.
-- Replaces: the unconditional send in security.course_page_needed_search_rule_v1
-- Retires: nothing

set local lock_timeout = '5s';

do $e$
declare v_sig regprocedure := 'security.course_page_needed_search_rule_v1(integer)'::regprocedure;
        v_def text := pg_get_functiondef(v_sig); i int; v_c int;
        v_edits text[][] := array[
          array[$o$v_ok jsonb := '{}'::jsonb; v_fail int := 0; v_held int;$o$,
                $n$v_ok jsonb := '{}'::jsonb; v_fail int := 0; v_held int; v_back int := 0;$n$, '1'],
          array[$o$  for w in$o$,
                $n$  -- 18 Nov 2026 (S658): an item this rule sent comes back to the list when its search cannot bring it back by itself: the search
  -- found no page or ended in error, or it is still queued and the lane's stop gate holds it
  with back as (
    select n.course_id,
           case when s.state in ('none', 'error') then 'the search found no page'
                else 'the search is held by the stop gate: ' || security.search_stop_gate_v1(n.provider_id, n.course_id) end why
      from pipeline.course_page_needed n
      join pipeline.course_link_search s on s.course_id = n.course_id
     where n.state = 'search_requested' and n.decision->>'reason' like '[rule l4-page-needed-search-v1]%'
       and (s.state in ('none', 'error') or (s.state = 'queued' and security.search_stop_gate_v1(n.provider_id, n.course_id) is not null)))
  update pipeline.course_page_needed n
     set state = 'open', updated_at = now(),
         decision = coalesce(n.decision, '{}'::jsonb) || jsonb_build_object('returned_by', 'l4-page-needed-search-v1', 'returned_at', now(), 'returned_because', b.why)
    from back b where n.course_id = b.course_id and n.state = 'search_requested';
  get diagnostics v_back = row_count;
  for w in$n$, '1'],
          array[$o$where n.state = 'open' and c.lifecycle_status = 'active' and n.searches_requested < v_max$o$,
                $n$where n.state = 'open' and c.lifecycle_status = 'active' and n.searches_requested < v_max
       -- 18 Nov 2026 (S658): never a search the stop gate would hold, nor a repeat of a search that found no page; those wait for a person
       and security.search_stop_gate_v1(n.provider_id, n.course_id) is null
       and not exists (select 1 from pipeline.course_link_search s0 where s0.course_id = n.course_id and s0.requested_at is not null and s0.state in ('none', 'error'))$n$, '1'],
          array[$o$'held_blocked_or_robots', v_held$o$, $n$'held_blocked_or_robots', v_held, 'returned_to_list', v_back$n$, '2']];
begin
  if position('18 Nov 2026 (S658)' in v_def) > 0 then raise notice 'already applied'; return; end if;
  if md5(v_def) <> 'a2677bf22b788fc41434e50300b256e5' then raise exception 'live % differs from the definition this change edits (md5 %)', v_sig, md5(v_def); end if;
  for i in 1 .. array_length(v_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, v_edits[i][1], ''))) / length(v_edits[i][1]);
    if v_c <> v_edits[i][3]::int then raise exception 'edit % must apply exactly % times (found %)', i, v_edits[i][3], v_c; end if;
    v_def := replace(v_def, v_edits[i][1], v_edits[i][2]);
  end loop;
  execute v_def;
end $e$;

-- the S656 on-demand request has run what it could: close it and record its actual use
do $d$
declare r record; v jsonb;
begin
  for r in select id from pipeline.on_demand_requests where state = 'open' and reason like '[S656 course page search]%' loop
    v := security.on_demand_close_v1(r.id);
    raise notice 'S656 on-demand request closed: %', v;
  end loop;
end $d$;

-- first run of the edited rule, at the job's own batch
create temp table cf_s658 on commit drop as
  select security.course_page_needed_search_rule_v1(security.pipeline_num_v1('layer4.page_needed_search_batch', 300)::int) r;

do $c$
declare v jsonb := (select r from cf_s658);
begin
  raise notice 'Rule l4-page-needed-search-v1 after S658: %', v;
  if coalesce((v->>'ok')::boolean, false) then
    if (v->>'failed')::int > 0 then raise exception 'post-check: % searches could not be asked: %', v->>'failed', v; end if;
    if v->>'returned_to_list' is null then raise exception 'post-check: the run does not report returned_to_list'; end if;
    if exists (select 1 from pipeline.course_page_needed n join pipeline.course_link_search s on s.course_id = n.course_id
                where n.state = 'search_requested' and n.decision->>'reason' like '[rule l4-page-needed-search-v1]%'
                  and (s.state in ('none', 'error') or (s.state = 'queued' and security.search_stop_gate_v1(n.provider_id, n.course_id) is not null))) then
      raise exception 'post-check: an item whose search cannot run or found nothing is still off the list';
    end if;
  end if;
  if exists (select 1 from pipeline.on_demand_requests where state = 'open' and reason like '[S656 course page search]%') then
    raise exception 'post-check: the S656 on-demand request is still open';
  end if;
  if not exists (select 1 from cron.job where jobname = 'layer4-page-needed-search' and active) then raise exception 'post-check: the job is not scheduled'; end if;
end $c$;
