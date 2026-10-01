-- CF-247 One home per setting (screen review 1 Oct 2026, package 2: "Models & services = the single on/off place").
-- Platform settings › Models & services is the only place a model or fetching service is switched on or off.
--   1. Switching a model on there now needs it to have passed its tests: a passed quality benchmark, or the tier rule
--      (>= 80% right and 0 wrong on the frozen test pages) for one of its tasks. Passing never switches anything on by
--      itself; switching on stays a deliberate, logged step.
--   2. Adding a model to a cascade in Layer 3 › Control no longer switches the model on as a side effect (it did, without
--      the activation checks). The model must already be switched on in Models & services.
--   3. Models & services shows a model as passed when either test is met, so the switch is offered only then.
-- All three are md5(prosrc)-guarded in-place edits.
do $do$
declare v_def text; v_new text;
begin
  -- 1. admin_services_control: refuse switching on a model that has not passed its tests
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_services_control(text,uuid,boolean,text)'::regprocedure) <> '3341242a2d1894936c55e5f741a2a47e' then
    raise exception 'public.admin_services_control changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('public.admin_services_control(text,uuid,boolean,text)'::regprocedure);
  v_new := replace(v_def, $s$      raise exception 'this model was retired after failing its tests and cannot be switched on here';
    end if;$s$, $s$      raise exception 'this model was retired after failing its tests and cannot be switched on here';
    end if;
    if p_enabled and not exists (select 1 from pipeline.layer3_model_profiles m where m.id = p_id
        and (coalesce((m.quality_benchmark->>'pass')::boolean, false)
             or exists (select 1 from unnest(m.allowed_task_classes) t where coalesce((security.layer3_tier_evidence(t, m.id)->>'eligible')::boolean, false)))) then
      raise exception 'this model has not passed its tests for any task yet, so it cannot be switched on';
    end if;$s$);
  if v_new = v_def then raise exception 'expected text not found (services control)'; end if;
  execute v_new;

  -- 3. admin_services_read: passed = benchmark passed or tier rule met for one of its tasks
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_services_read()'::regprocedure) <> '2b5a463aa1b0f0998e9c30d4bd725160' then
    raise exception 'public.admin_services_read changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('public.admin_services_read()'::regprocedure);
  v_new := replace(v_def, $s$'qualified', coalesce((p.quality_benchmark->>'pass')::boolean, false)$s$,
                   $s$'qualified', coalesce((p.quality_benchmark->>'pass')::boolean, false) or exists (select 1 from unnest(p.allowed_task_classes) t where coalesce((security.layer3_tier_evidence(t, p.id)->>'eligible')::boolean, false))$s$);
  if v_new = v_def then raise exception 'expected text not found (services read)'; end if;
  execute v_new;

  -- 2. Layer 3 Control tier_add: the model must already be switched on; no side-effect switch-on
  if (select md5(prosrc) from pg_proc where oid = 'security.admin_layer3_control_v1(text,jsonb)'::regprocedure) <> '6c8cd94147a5b4e165f87a8c63cd6821' then
    raise exception 'security.admin_layer3_control_v1 changed since it was checked; not editing'; end if;
  v_def := pg_get_functiondef('security.admin_layer3_control_v1(text,jsonb)'::regprocedure);
  v_new := replace(v_def, $s$    update pipeline.layer3_model_profiles set enabled=true, paused=false, retired_at=null, retired_reason=null, updated_at=now() where id=p.id;
$s$, '');
  v_new := replace(v_new, $s$    e:=security.layer3_tier_evidence(v_task,p.id);
    if not coalesce((e->>'eligible')::boolean,false) then raise exception 'model has not passed the tier rule$s$,
                   $s$    if not (p.enabled and not p.paused and p.retired_at is null) then raise exception 'switch this model on in Platform settings › Models & services first'; end if;
    e:=security.layer3_tier_evidence(v_task,p.id);
    if not coalesce((e->>'eligible')::boolean,false) then raise exception 'model has not passed the tier rule$s$);
  if v_new = v_def or position('set enabled=true, paused=false' in v_new) > 0 or position('Models & services first' in v_new) = 0 then
    raise exception 'expected text not found (layer3 tier_add)'; end if;
  execute v_new;
end $do$;