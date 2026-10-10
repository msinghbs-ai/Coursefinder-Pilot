-- CF-CHG-20260910-093
-- Direct fresh-preview runs must not inherit a historical handoff_started binding for the
-- same profile/scope. The current scheduler preview token is propagated transaction-locally;
-- if present, only that exact binding may influence deterministic handoff semantics.

do $migration$
declare
  v_reg regprocedure := 'public.layer2_scope_profile_batch_service(uuid,uuid,uuid[])'::regprocedure;
  v_def text;
  v_old_decl text := $old$  v_terminal_negative_count integer:=0;$old$;
  v_new_decl text := $new$  v_terminal_negative_count integer:=0;
  v_expected_preview uuid:=nullif(current_setting('coursefinder.scheduler_preview_token',true),'')::uuid;$new$;
  v_old_select text := $old$  select * into v_binding
  from pipeline.scheduler_workflow_async_bindings b
  where b.actor_id=p_actor
    and b.profile_id=p_profile_id
    and b.sync_course_ids=v_sync
    and b.status in ('active','handoff_started')
  order by b.created_at desc
  limit 1
  for update;$old$;
  v_new_select text := $new$  if v_expected_preview is not null then
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.preview_token=v_expected_preview
      and b.actor_id=p_actor
      and b.profile_id=p_profile_id
      and b.sync_course_ids=v_sync
      and b.status in ('active','handoff_started')
    order by b.created_at desc
    limit 1
    for update;
  else
    select * into v_binding
    from pipeline.scheduler_workflow_async_bindings b
    where b.actor_id=p_actor
      and b.profile_id=p_profile_id
      and b.sync_course_ids=v_sync
      and b.status in ('active','handoff_started')
    order by b.created_at desc
    limit 1
    for update;
  end if;$new$;
begin
  select pg_get_functiondef(v_reg) into v_def;
  if position(v_old_decl in v_def)=0 or position(v_old_select in v_def)=0 then
    raise exception 'CF-093 preview-context binding isolation patch target not found';
  end if;
  v_def:=replace(v_def,v_old_decl,v_new_decl);
  v_def:=replace(v_def,v_old_select,v_new_select);
  execute v_def;
end
$migration$;
