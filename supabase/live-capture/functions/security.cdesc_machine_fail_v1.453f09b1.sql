CREATE OR REPLACE FUNCTION security.cdesc_machine_fail_v1(p_rule text, p_reason text, p_next text, p_transient boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select jsonb_build_object('ok', false, 'rule', p_rule, 'reason', p_reason, 'next_action', p_next, 'transient', p_transient)
$function$
