-- CF-247 (22 Oct 2026). Hotfix to 20261022014000 (unpublished providers pause). In two functions the pause check named provider_id
-- without its table, so inside the check it meant the pause list's own column and was always true: no queued onboarding started (726
-- waiting) and no automatic enrichment plan moved (27 open, last change 00:50 UTC). The check now names the table's column.
-- Replaces: security.provider_onboarding_tick_v1, security.enrich_plan_tick_v1 (pause check names its table). md5-guarded.
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

do $guard$
begin
  if md5(pg_get_functiondef('security.provider_onboarding_tick_v1()'::regprocedure)) <> '44e74bdeec8217b12ec9378a73386f57'
     or md5(pg_get_functiondef('security.enrich_plan_tick_v1(uuid)'::regprocedure)) <> '9f5993e605179d6f8d6d03c8ff184f1d' then
    raise exception 'live onboarding or plan tick differs from the definition this change replaces';
  end if;
end $guard$;

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits', p_sig; end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.provider_onboarding_tick_v1()', '44e74bdeec8217b12ec9378a73386f57', array[
  [$o$for o in select id from pipeline.provider_onboarding where status = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = provider_id)$o$,
   $n$for o in select q.id from pipeline.provider_onboarding q where q.status = 'queued' and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = q.provider_id)$n$],
  [$o$            order by priority desc, created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop$o$,
   $n$            order by q.priority desc, q.created_at limit greatest(coalesce(s.max_active, 0) - v_active, 0) loop$n$]]);

select pg_temp.edit_once('security.enrich_plan_tick_v1(uuid)', '9f5993e605179d6f8d6d03c8ff184f1d', array[
  [$o$and (mode <> 'auto' or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = provider_id))$o$,
   $n$and (mode <> 'auto' or not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = pipeline.enrich_plan_runs.provider_id))$n$]]);

select security.provider_onboarding_tick_v1();
