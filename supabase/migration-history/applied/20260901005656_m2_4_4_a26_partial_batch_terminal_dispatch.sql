-- CF-CHG-20260830-048
-- M2.4.4 A26: reconciled partial batches are terminal and must not block a later
-- scheduled scope wave merely because they share the same source profile.
-- Duplicate protection remains for queued/running batches.

do $$
declare
  v_oid oid;
  v_def text;
  v_old text := 'if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in(''queued'',''running'',''partial'')) then';
  v_new text := 'if exists(select 1 from pipeline.layer2_run_batches b where b.profile_id=r.profile_id and b.status in(''queued'',''running'')) then';
begin
  select p.oid into v_oid
  from pg_proc p
  join pg_namespace n on n.oid=p.pronamespace
  where n.nspname='security'
    and p.proname='layer2_wave_dispatch_request'
    and pg_get_function_identity_arguments(p.oid)='p_request_id uuid'
  limit 1;

  if v_oid is null then
    raise exception 'security.layer2_wave_dispatch_request(uuid) not found';
  end if;

  select pg_get_functiondef(v_oid) into v_def;

  if position(v_new in v_def)>0 then
    return;
  end if;
  if position(v_old in v_def)=0 then
    raise exception 'expected profile duplicate-protection predicate not found';
  end if;

  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end $$;
