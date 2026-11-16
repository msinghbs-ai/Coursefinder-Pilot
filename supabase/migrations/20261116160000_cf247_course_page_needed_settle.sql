-- CF-247 Layer 4 "Course page needed" list: settle entries whose outcome is already on record (Platform Admin 16 Nov 2026 20:14, quick win A).
-- Replaces: nothing (security.course_page_needed_convert_v1 still moves items onto the list; security.course_page_needed_decide_v1 stays the
--           person's action).
-- Retires: nothing.
--
-- Found (read only, 16 Nov 2026 20:40 AEDT): 2,108 open entries. The list has no throughput setting that clears it: each entry needs a person's
-- choice (add the page, search again with Firecrawl, or record that no page exists), so a bulk pass cannot clear it without either deciding a
-- page with no evidence or spending on searches. 242 open entries already carry the outcome a person's choice would record:
--   * 236 courses have a confirmed absence in pipeline.course_no_page (kind no_page, state confirmed or confirmed_auto): the same record the
--     person's "no page" choice writes. They become no_page_exists.
--   * 6 courses already hold an active official course link (catalogue.course_links official_course, active): the page was added elsewhere.
--     They become page_added.
-- Everything else stays open for a person (454 have a bound page waiting: Phase 5 grid).
--
-- security.course_page_needed_settle_v1(p_limit, p_apply): deterministic, zero AI, no search, no external spend; p_apply false counts only;
-- Platform Admin or no signed-in user; each applied call is audited in pipeline.admin_control_events. The migration settles nothing itself.
-- Batch: layer4.page_needed_convert_batch (existing setting). No job (G1), no consumer API object (G3), nothing dropped or deleted.

create or replace function security.course_page_needed_settle_v1(p_limit integer default null, p_apply boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = pg_catalog, public
as $function$
declare v_max int := security.pipeline_num_v1('layer4.page_needed_convert_batch', 500)::int; v_lim int; v_no int := 0; v_added int := 0;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  v_lim := least(greatest(coalesce(p_limit, v_max), 0), v_max);
  with c as (
    select n.course_id,
           case when exists (select 1 from catalogue.course_links l where l.course_id = n.course_id and l.link_type = 'official_course' and l.status = 'active') then 'page_added'
                when exists (select 1 from pipeline.course_no_page x where x.course_id = n.course_id and x.kind = 'no_page' and x.state in ('confirmed', 'confirmed_auto')) then 'no_page_exists'
           end to_state
      from pipeline.course_page_needed n
     where n.state = 'open'
     order by n.created_at, n.course_id),
  pick as (select * from c where to_state is not null limit v_lim),
  upd as (
    update pipeline.course_page_needed n
       set state = p.to_state, decided_by = null, decided_at = now(), updated_at = now(),
           decision = jsonb_build_object('choice', 'settled_by_rule', 'rule', 'cpn-settle-v1',
                                         'basis', case p.to_state when 'page_added' then 'the course holds an active official course link'
                                                                  else 'pipeline.course_no_page holds a confirmed absence' end)
      from pick p
     where p_apply and n.course_id = p.course_id and n.state = 'open'
    returning n.state)
  select coalesce((select count(*) filter (where to_state = 'no_page_exists') from pick), 0),
         coalesce((select count(*) filter (where to_state = 'page_added') from pick), 0)
    into v_no, v_added;
  if p_apply and v_no + v_added > 0 then
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('layer4', 'course_page_needed_settle', 'pipeline.course_page_needed',
            jsonb_build_object('rule', 'cpn-settle-v1', 'no_page_exists', v_no, 'page_added', v_added, 'limit', v_lim), auth.uid());
  end if;
  return jsonb_build_object('rule', 'cpn-settle-v1', 'applied', p_apply, 'no_page_exists', v_no, 'page_added', v_added, 'limit', v_lim,
                            'open_after', (select count(*) from pipeline.course_page_needed where state = 'open'));
end;
$function$;
comment on function security.course_page_needed_settle_v1(integer, boolean) is
  'CF-247 Layer 4 (Platform Admin 16 Nov 2026 20:14): settles open Course page needed entries whose outcome is on record (confirmed no-page record -> no_page_exists; active official link -> page_added). Deterministic, no search; p_apply false counts only; audited.';
revoke all on function security.course_page_needed_settle_v1(integer, boolean) from public, anon, authenticated;
grant execute on function security.course_page_needed_settle_v1(integer, boolean) to service_role;

insert into pipeline.component_register (kind, name, layer, area, purpose, status, replaces, introduced_in)
values ('function', 'security.course_page_needed_settle_v1', 'layer4', 'official_course_url',
        'Settles Course page needed entries whose outcome is on record (confirmed absence, or an active official link); run on demand', 'active', '{}', '20261116160000')
on conflict (kind, name) do nothing;

do $post$
declare r jsonb;
begin
  r := security.course_page_needed_settle_v1(null, false);
  if (r->>'applied')::boolean then raise exception 'post-check: the count call must not apply'; end if;
end $post$;
