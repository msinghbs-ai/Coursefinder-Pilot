CREATE OR REPLACE FUNCTION security.provider_onboarding_ready_v1(p_q jsonb)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'ready', coalesce(jsonb_agg(f.k) filter (where f.why is null), '[]'::jsonb),
    'held', coalesce(jsonb_object_agg(f.k, f.why) filter (where f.why is not null), '{}'::jsonb))
  from (select k, case
          when not coalesce((x->>'pass')::boolean, false) then coalesce(x->>'why', 'does not pass')
          when coalesce((x->>'read')::int, 0) < 5 then 'read on fewer than 5 pages'
          when coalesce((x->>'agree')::int, 0) < 3 or x->>'agree_share' is null then 'not enough held values to check against (needs 3 agreeing courses)'
          when (x->>'agree_share')::numeric < 0.9 then 'agrees on under 90% of checked courses' end why
        from jsonb_each(coalesce(p_q->'fields', '{}'::jsonb)) e(k, x) where k in ('intakes', 'english', 'fee', 'delivery')) f
$function$
