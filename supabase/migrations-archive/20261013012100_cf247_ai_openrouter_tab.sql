-- CF-247 v2.15.264 (Platform Admin, 13 Oct 2026 00:09): "Layer 3 has removed the configuration of OpenAI and access to toolsets and
-- limits; restore them as a tab in Models & services." Decisions: three tabs (Services · AI & OpenRouter · Toolsets & limits); the
-- scholarship AI model order and qualification shown and editable in the AI tab.
-- When Layer 3 was retired (v2.15.252) its Control tab and the "Extract values (Layer 3)" settings went with it. The AI that runs
-- now (scholarship pages, adapter proposals, central pages, course-page matching) kept its guards on Toolsets, its key on Settings
-- and its scholarship models on Scholarships › Extraction. This brings them together:
--   public.admin_ai_config_read()  one read for the AI & OpenRouter tab (rank 3+): OpenRouter balance, mode, floor and warning,
--                                   the key (one OpenRouter key, OPENROUTER_API_KEY, shared by every profile), each AI use with its
--                                   model, guard, spend and calls today, the central pages settings, the model profiles (prompts,
--                                   versions, holdout) and recent AI changes;
--   public.admin_ai_config(action, args)  Platform Admin with a reason: central pages model (one of the scholarship AI models that
--                                   is not retired) and central pages AI on or off. Guards, floor, mode and the adapter proposal
--                                   model keep using admin_toolsets_write; scholarship models keep using admin_scholarship_ai.
-- Nothing is dropped or deleted.

create or replace function public.admin_ai_config_read() returns jsonb
language plpgsql stable security definer set search_path = '' as $f$
declare v_rank int := security.current_role_rank();
begin
  if auth.uid() is null or coalesce(v_rank, 0) < 3 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  return jsonb_build_object(
    'can_manage', v_rank >= 6, 'generated_at', now(),
    'openrouter', (select jsonb_build_object(
        'mode', coalesce((select t.enforcement from pipeline.platform_toolsets t where t.key = 'openrouter'), 'stop'),
        'mode_reason', (select t.reason from pipeline.platform_toolsets t where t.key = 'openrouter'),
        'credit_floor_usd', (security.toolset_setting('openrouter', 'credit_floor_usd'))::text::numeric,
        'low_balance_warn_usd', (security.toolset_setting('openrouter', 'low_balance_warn_usd'))::text::numeric,
        'balance', (select jsonb_build_object('remaining_usd', round(o.remaining_usd, 2), 'total_credits', coalesce(o.payload->>'total_credits', o.payload#>>'{data,total_credits}')::numeric, 'observed_at', o.observed_at)
                      from pipeline.layer3_openrouter_observations o where o.kind = 'credits' order by o.observed_at desc limit 1),
        'key', jsonb_build_object('secret', 'OPENROUTER_API_KEY', 'shared_by_profiles', (select count(*) from pipeline.layer3_model_profiles p where p.secret_env_key = 'OPENROUTER_API_KEY'),
                                  'profile_id', (select p.id from pipeline.layer3_model_profiles p where p.code = (security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}')),
                                  'profile_code', security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}'))),
    'uses', (select coalesce(jsonb_agg(jsonb_build_object('use', g.use, 'label', g.label, 'spent_today', g.spent, 'guard', g.guard, 'calls', g.calls,
                 'allowed', security.ai_use_allowed_v1(g.use),
                 'models', case g.use
                   when 'scholarship_ai' then (select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'label', m.label, 'model', m.model_identifier, 'status', m.status) order by m.status <> 'active', m.code), '[]'::jsonb)
                                                 from pipeline.scholarship_ai_models m where m.status = 'active')
                   when 'adapter_builder' then jsonb_build_array(jsonb_build_object('model', security.toolset_setting('firecrawl', 'builder_model') #>> '{}', 'profile', security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}', 'set_on', 'firecrawl.builder_model'))
                   when 'central_ai' then (select jsonb_build_array(jsonb_build_object('code', c.model_code, 'model', c.model_identifier, 'enabled', c.enabled, 'calls_at_once', c.calls_at_once, 'reason', c.reason, 'changed_at', c.changed_at)) from pipeline.central_ai_settings c where c.id = 1)
                   when 'course_match' then jsonb_build_array(jsonb_build_object('model', 'qwen/qwen3-30b-a3b-instruct-2507', 'fixed', 'worker coverage-sweep (AI_MATCH_MODEL)'))
                 end)), '[]'::jsonb)
               from security.ai_spend_today_v1() g),
    'central_choices', (select coalesce(jsonb_agg(jsonb_build_object('code', m.code, 'label', m.label, 'model', m.model_identifier, 'status', m.status) order by m.code), '[]'::jsonb)
                          from pipeline.scholarship_ai_models m where m.status <> 'retired' and m.model_identifier <> 'person'),
    'profiles', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'code', p.code, 'model', p.model_identifier, 'enabled', p.enabled, 'paused', p.paused,
                    'prompt_version', p.prompt_profile_version, 'prompt_chars', length(coalesce(p.prompt_system, '')), 'prompt_hash', left(md5(coalesce(p.prompt_system, '')), 12),
                    'tasks', p.allowed_task_classes, 'requests_per_day', p.requests_per_day, 'cost_ceiling_usd', p.cost_ceiling_usd, 'holdout', p.holdout_qualification,
                    'used_now', p.code = (security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}'))
                    order by p.code = (security.toolset_setting('firecrawl', 'builder_model_profile') #>> '{}') desc, p.enabled desc, p.code), '[]'::jsonb)
                   from pipeline.layer3_model_profiles p where p.retired_at is null),
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.created_at, 'area', e.area, 'action', e.action, 'target', e.target, 'reason', e.detail->>'reason') order by e.created_at desc), '[]'::jsonb)
                 from (select * from pipeline.admin_control_events e where e.area in ('ai_config', 'scholarship_ai', 'openrouter') or (e.area = 'toolsets' and e.target like 'openrouter%')
                        order by e.created_at desc limit 20) e));
end $f$;
revoke all on function public.admin_ai_config_read() from public, anon;
grant execute on function public.admin_ai_config_read() to authenticated;

create or replace function public.admin_ai_config(p_action text, p_args jsonb) returns jsonb
language plpgsql security definer set search_path = '' as $f$
declare v_reason text := trim(coalesce(p_args->>'reason', '')); m record;
begin
  if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required' using errcode = '42501'; end if;
  if length(v_reason) < 4 then raise exception 'a reason is required'; end if;
  if p_action = 'central_model' then
    select * into m from pipeline.scholarship_ai_models x where x.code = p_args->>'code' and x.status <> 'retired' and x.model_identifier <> 'person';
    if m.code is null then raise exception 'choose one of the scholarship AI models that is not retired'; end if;
    update pipeline.central_ai_settings set model_code = m.code, model_identifier = m.model_identifier, reason = v_reason, changed_at = now(), changed_by = auth.uid() where id = 1;
  elsif p_action = 'central_on' then
    update pipeline.central_ai_settings set enabled = coalesce((p_args->>'on')::boolean, false), reason = v_reason, changed_at = now(), changed_by = auth.uid() where id = 1;
  else
    raise exception 'unknown action %', p_action;
  end if;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('ai_config', p_action, 'central_ai', p_args - 'reason' || jsonb_build_object('reason', v_reason, 'change', 'CF-247 v2.15.264'), auth.uid());
  return public.admin_ai_config_read();
end $f$;
revoke all on function public.admin_ai_config(text, jsonb) from public, anon;
grant execute on function public.admin_ai_config(text, jsonb) to authenticated;

do $chk$ begin
  if to_regprocedure('public.admin_ai_config_read()') is null or to_regprocedure('public.admin_ai_config(text, jsonb)') is null then raise exception 'v2.15.264 post-check: functions missing'; end if;
end $chk$;
