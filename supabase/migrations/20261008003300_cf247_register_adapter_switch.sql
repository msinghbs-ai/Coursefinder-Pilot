-- CF-247 Phase 2 (8 Oct 2026, Platform Admin: "Switch on CRICOS, NZQA, PRISMS"): switching a register adapter on is its own logged
-- Platform Admin step. `admin_register_adapter_switch` turns an adapter on only when its latest finished side-by-side replay passed and the
-- spec has not been edited since that replay; turning off is always allowed. A Layer 1 worker asks `svc_register_adapter_reader` for the
-- adapter by code: when one is switched on, the worker reads the published files with the adapter spec instead of its own reader
-- (fetching, evidence, identity checks and the apply functions are unchanged). Nothing is switched by this migration.
alter table pipeline.register_adapters add column if not exists switched_at timestamptz, add column if not exists switch_reason text;

create or replace function public.svc_register_adapter_reader(p_code text)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare a pipeline.register_adapters%rowtype;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into a from pipeline.register_adapters where code = p_code and switched_on;
  if a.code is null then return null; end if;
  return jsonb_build_object('code', a.code, 'version', a.version, 'spec', a.spec, 'switched_at', a.switched_at);
end $f$;
revoke all on function public.svc_register_adapter_reader(text) from public, anon, authenticated;
grant execute on function public.svc_register_adapter_reader(text) to service_role;

create or replace function public.admin_register_adapter_switch(p_code text, p_on boolean, p_reason text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare a pipeline.register_adapters%rowtype; r pipeline.register_replay_runs%rowtype;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(btrim(coalesce(p_reason, ''))) < 4 then raise exception 'give a reason (kept in the log)'; end if;
  select * into a from pipeline.register_adapters where code = p_code for update;
  if a.code is null then raise exception 'no register adapter %', p_code; end if;
  if p_on then
    select * into r from pipeline.register_replay_runs where source_id = a.source_id and done_at is not null and error is null and result is not null
     order by created_at desc limit 1;
    if r.id is null then raise exception 'no finished side-by-side replay for %', p_code; end if;
    if coalesce((r.result->>'pass')::boolean, false) is not true then raise exception 'the latest replay for % did not pass (%)', p_code, r.label; end if;
    if a.updated_at > r.done_at then raise exception 'the % spec changed after its latest replay; replay it again first', p_code; end if;
  end if;
  update pipeline.register_adapters
     set switched_on = p_on, switched_at = case when p_on then now() else switched_at end, switch_reason = left(p_reason, 500), updated_by = auth.uid()
   where code = p_code;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('layer1', case when p_on then 'register_adapter_on' else 'register_adapter_off' end, p_code,
          jsonb_build_object('source_id', a.source_id, 'replay_run', r.id, 'replay_label', r.label, 'replay_result', r.result, 'reason', left(p_reason, 500)), auth.uid());
  return jsonb_build_object('ok', true, 'code', p_code, 'switched_on', p_on, 'replay', r.label);
end $f$;
revoke all on function public.admin_register_adapter_switch(text, boolean, text) from public, anon;
grant execute on function public.admin_register_adapter_switch(text, boolean, text) to authenticated;
