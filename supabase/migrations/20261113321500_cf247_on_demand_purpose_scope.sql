-- CF-247 operating model 3.3.2 correction: an on-demand request waives limits only for the work it was opened for, not for scheduled work of the same providers.
-- Evidence (request f053937d, AER source discovery for 795 providers, 13 Nov 2026 08:41 to 14:45 AEDT): 4,430 Firecrawl units were recorded against it, of
--   which 123 (sch_map 107, sch_scrape 16) were the scheduled scholarship lane and 17 the provider-facts reader for the same providers. The request named
--   providers only, so svc_fc_spend waived every purpose for them. Platform Admin 12 Nov 2026 21:07: "only scheduled tasks should obey toolset limits".
-- What:
--   1. pipeline.on_demand_requests.purpose_groups (text[], null = every group, as before): the Firecrawl purpose groups (security.fc_purpose_group_v1) a request
--      covers. security.on_demand_scope_v1(id, groups) sets it; the open AER discovery request 5f2f9937 is scoped to the central group.
--   2. security.on_demand_request_for_v2(provider, purpose): the open request for the provider whose groups include the purpose's group.
--   3. public.svc_fc_spend (md5-guarded): uses v2 with the spend's purpose.
-- Guards: G2 (no new value), G3 (no consumer API object), Decision 260; nothing deleted.
-- Live definition this change edits (md5 of pg_get_functiondef, read 13 Nov 2026 14:50 AEDT): public.svc_fc_spend 521d7e98ef897e92eda1bb6fd8e46af8.
-- Replaces: security.on_demand_request_for_v1 in svc_fc_spend (v1 stays; marked retiring in the component register by the hygiene job when unused). Retires: nothing.

alter table pipeline.on_demand_requests add column if not exists purpose_groups text[];
comment on column pipeline.on_demand_requests.purpose_groups is 'Firecrawl purpose groups (security.fc_purpose_group_v1) the request covers; null covers every group.';

create or replace function security.on_demand_request_for_v2(p_provider uuid, p_purpose text) returns uuid language sql stable security definer set search_path to '' as $f$
  select r.id from pipeline.on_demand_requests r
   where r.state = 'open' and r.expires_at > now() and p_provider = any (r.provider_ids) and 'firecrawl' = any (r.toolsets)
     and (r.purpose_groups is null or security.fc_purpose_group_v1(p_purpose) = any (r.purpose_groups))
   order by r.opened_at desc limit 1
$f$;

create or replace function security.on_demand_scope_v1(p_id uuid, p_groups text[]) returns jsonb language plpgsql security definer set search_path to '' as $f$
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' and coalesce(security.current_role_rank(), 0) < 3 then
    raise exception 'Curator role or above, or the service, required' using errcode = '42501';
  end if;
  update pipeline.on_demand_requests set purpose_groups = p_groups where id = p_id and state = 'open';
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('on_demand', 'scope', 'pipeline.on_demand_requests', jsonb_build_object('id', p_id, 'purpose_groups', p_groups), auth.uid());
  return jsonb_build_object('id', p_id, 'purpose_groups', p_groups);
end $f$;

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

select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', '521d7e98ef897e92eda1bb6fd8e46af8', array[
  array[$o$security.on_demand_request_for_v1(p_provider_id)$o$, $n$security.on_demand_request_for_v2(p_provider_id, p_purpose)$n$]
], array[1]);

update pipeline.on_demand_requests set purpose_groups = array['central'] where id = '5f2f9937-6a9c-4269-ab77-f5333de9439e' and state = 'open';
