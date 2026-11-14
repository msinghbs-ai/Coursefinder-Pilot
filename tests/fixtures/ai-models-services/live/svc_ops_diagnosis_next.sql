CREATE OR REPLACE FUNCTION public.svc_ops_diagnosis_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
-- Hands queued AI diagnosis requests to the worker while ops.ai_diagnosis_on is 1, within ops.ai_requests_per_day and while today's AI spend is
-- under budgets.ai_daily_ceiling_usd. Each comes with the pinned model and the context it may quote.
declare v jsonb; v_today int; v_room int; v_ref text; v_tz text := 'Australia/Melbourne';  -- fixed: the platform's reporting time zone
begin
  if security.pipeline_num_v1('ops.ai_diagnosis_on', 0) < 1 then return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_on is 0'); end if;
  if (select coalesce(sum(t.spent), 0) from security.ai_spend_today_v1() t) >= security.pipeline_num_v1('budgets.ai_daily_ceiling_usd', 14) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'daily AI ceiling reached');
  end if;
  -- the lane's spend must count in the daily ceiling (security.ai_spend_today_v1 lists the lanes it sums)
  if not exists (select 1 from security.ai_spend_today_v1() t where t.use = 'ops_diagnose') then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'the ops_diagnose lane is not counted in the daily AI ceiling yet (security.ai_spend_today_v1)');
  end if;
  v_ref := security.ai_use_refusal_v1('ops_diagnose');  -- the existing guard: credit floor, daily ceiling, lane guard (stop mode)
  if v_ref is not null then return jsonb_build_object('items', '[]'::jsonb, 'held', v_ref); end if;
  if (select coalesce(sum(l.cost_usd), 0) from pipeline.ai_spend_ledger l where l.lane = 'ops_diagnose' and l.at >= (date_trunc('day', now() at time zone 'UTC') at time zone 'UTC'))  -- fixed: the UTC day the AI guards count
     >= security.pipeline_num_v1('ops.ai_diagnosis_usd_per_day', 0.5) then
    return jsonb_build_object('items', '[]'::jsonb, 'held', 'ops.ai_diagnosis_usd_per_day reached');
  end if;
  select count(*) into v_today from pipeline.ops_ai_diagnosis_requests q where q.state in ('leased', 'answered') and (q.requested_at at time zone v_tz)::date = (now() at time zone v_tz)::date;
  v_room := greatest(least(coalesce(p_limit, 1), security.pipeline_num_v1('ops.ai_requests_per_day', 20)::int - v_today), 0);
  with c as (select q.id from pipeline.ops_ai_diagnosis_requests q where q.state = 'queued' or (q.state = 'leased' and q.leased_until < now())
              order by q.requested_at limit v_room for update skip locked)
  update pipeline.ops_ai_diagnosis_requests q set state = 'leased', leased_until = now() + interval '10 minutes',  -- fixed: lease timer
         model = coalesce(security.toolset_setting('pipeline', 'ops.ai_diagnosis_model') #>> '{}', 'openai/gpt-4.1-mini')
    from c where q.id = c.id;
  select coalesce(jsonb_agg(jsonb_build_object('id', q.id, 'model', q.model, 'lease_until', q.leased_until, 'contract', 'ops-diagnose-v1', 'context', q.context,
           'instructions', 'You diagnose one StudySearch integration issue from the context only. Choose exactly one root_cause from the codes in context.root_causes. '
                           || 'Give confidence from 0 to 1. Give evidence as short quotes copied exactly, character for character, from text values in the context (not paraphrased). '
                           || 'Do not propose actions, settings or code changes. Answer with one JSON object that matches response_schema and nothing else.',
           'response_schema', jsonb_build_object('type', 'object', 'required', jsonb_build_array('root_cause', 'confidence', 'evidence'), 'additionalProperties', false,
             'properties', jsonb_build_object(
               'root_cause', jsonb_build_object('type', 'string', 'enum', (select jsonb_agg(c.code order by c.code) from pipeline.ops_root_causes c)),
               'confidence', jsonb_build_object('type', 'number', 'minimum', 0, 'maximum', 1),
               'evidence', jsonb_build_object('type', 'array', 'minItems', 1, 'items', jsonb_build_object('type', 'string')),
               'reasoning', jsonb_build_object('type', 'string'))))), '[]'::jsonb) into v
    from pipeline.ops_ai_diagnosis_requests q where q.state = 'leased' and q.leased_until > now();
  return jsonb_build_object('items', v, 'contract', 'ops-diagnose-v1');
end $function$
