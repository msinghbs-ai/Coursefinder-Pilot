-- CF-247 (3 Oct 2026, 01:10 AEST). Platform Admin, 00:57: "In English policies, make it bulk approval and some of the
-- approved one still shoeing the greyed approve icon. Where so I increase search cap?"
-- 1. One approved document per university and kind: approving an English policy (or an academic calendar) closes the
--    university's other waiting documents of that kind (status superseded, with a note). They were the rows still showing
--    an Approve button, greyed where most course pages disagree with them. md5 guard on admin_provider_policy_decide.
--    Waiting documents of universities that already have an approved one are closed the same way now.
-- 2. admin_provider_policy_decide_bulk: approve or reject several documents in one action (Platform Admin). Each goes
--    through admin_provider_policy_decide with all its checks; one that cannot be approved is skipped and reported.
-- 3. admin_course_link_search_settings: the course-link search monthly credit cap (pipeline.course_link_search_settings),
--    read by Pipeline Operator and above, changed by a Platform Admin (1,000 to 500,000), with this month's use.
do $p$
declare s text; d text;
  o1 text := $o$  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', p_action, x.kind || ': ' || x.url, jsonb_build_object('decision', 'Decision 227', 'proposal_id', x.id, 'provider_id', x.provider_id), auth.uid());$o$;
  n1 text := $n$  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('policies', p_action, x.kind || ': ' || x.url, jsonb_build_object('decision', 'Decision 227', 'proposal_id', x.id, 'provider_id', x.provider_id), auth.uid());
  -- one approved document per university and kind: its other waiting documents are closed
  if p_action = 'approve' then
    update pipeline.provider_policy_proposals
       set status = 'superseded', decided_at = now(), updated_at = now(),
           decision_note = 'Closed: another document for this university was approved (' || x.url || ')'
     where provider_id = x.provider_id and kind = x.kind and status = 'proposed' and id <> x.id;
  end if;$n$;
begin
  select p.prosrc, pg_get_functiondef(p.oid) into s, d from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname = 'admin_provider_policy_decide';
  if md5(s) is distinct from '878f85c1a27d9f5aa16cac9504855a10' then raise exception 'admin_provider_policy_decide changed (md5 %); not replacing', md5(s); end if;
  if (length(d) - length(replace(d, o1, ''))) / length(o1) <> 1 then raise exception 'piece not found once'; end if;
  execute replace(d, o1, n1);
end $p$;

update pipeline.provider_policy_proposals w
   set status = 'superseded', decided_at = now(), updated_at = now(),
       decision_note = 'Closed: another document for this university is already approved'
 where w.status = 'proposed'
   and exists (select 1 from pipeline.provider_policy_proposals a where a.provider_id = w.provider_id and a.kind = w.kind and a.status = 'approved');

create or replace function public.admin_provider_policy_decide_bulk(p_ids uuid[], p_action text, p_note text default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_id uuid; v_ok int := 0; v_fill int := 0; v_skip jsonb := '[]'::jsonb; r jsonb; v_status text;
begin
  if auth.uid() is null or security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  if p_action not in ('approve', 'reject') then raise exception 'action must be approve or reject'; end if;
  if coalesce(cardinality(p_ids), 0) = 0 or cardinality(p_ids) > 200 then raise exception 'choose between 1 and 200 documents'; end if;
  foreach v_id in array p_ids loop
    -- a document closed earlier in this same action (another of its university was approved) is skipped
    select status into v_status from pipeline.provider_policy_proposals where id = v_id;
    if v_status is distinct from 'proposed' then
      v_skip := v_skip || jsonb_build_object('id', v_id, 'reason', case when v_status = 'superseded' then 'another document for this university was approved' else 'already decided' end);
      continue;
    end if;
    begin
      r := public.admin_provider_policy_decide(v_id, p_action, p_note);
      v_ok := v_ok + 1; v_fill := v_fill + coalesce((r->>'to_fill')::int, 0);
    exception when others then
      v_skip := v_skip || jsonb_build_object('id', v_id, 'reason', sqlerrm);
    end;
  end loop;
  return jsonb_build_object('done', v_ok, 'to_fill', v_fill, 'skipped', v_skip);
end $f$;
revoke all on function public.admin_provider_policy_decide_bulk(uuid[], text, text) from public, anon;
grant execute on function public.admin_provider_policy_decide_bulk(uuid[], text, text) to authenticated;

create or replace function public.admin_course_link_search_settings(p_monthly_credit_cap int default null)
returns jsonb language plpgsql security definer set search_path to '' as $f$
declare v_old int;
begin
  if auth.uid() is null or security.current_role_rank() < 4 then raise exception 'Pipeline Operator role required' using errcode = '42501'; end if;
  if p_monthly_credit_cap is not null then
    if security.current_role_rank() < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
    if p_monthly_credit_cap < 1000 or p_monthly_credit_cap > 500000 then raise exception 'the cap must be between 1,000 and 500,000 credits'; end if;
    select monthly_credit_cap into v_old from pipeline.course_link_search_settings where id = 1 for update;
    update pipeline.course_link_search_settings set monthly_credit_cap = p_monthly_credit_cap, updated_at = now(), updated_by = auth.uid() where id = 1;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('course_link_search', 'set_cap', 'monthly credit cap', jsonb_build_object('from', v_old, 'to', p_monthly_credit_cap), auth.uid());
  end if;
  return (select jsonb_build_object('enabled', s.enabled, 'monthly_credit_cap', s.monthly_credit_cap, 'updated_at', s.updated_at,
           'used_this_month', (select coalesce(sum(u.units), 0) from pipeline.coverage_vendor_usage u where u.purpose = 'course_link_search' and u.at >= date_trunc('month', now())),
           'queued', (select count(*) from pipeline.course_link_search q where q.state = 'queued'),
           'can_change', security.current_role_rank() >= 6)
            from pipeline.course_link_search_settings s where s.id = 1);
end $f$;
revoke all on function public.admin_course_link_search_settings(int) from public, anon;
grant execute on function public.admin_course_link_search_settings(int) to authenticated;
