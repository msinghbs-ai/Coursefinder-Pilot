CREATE OR REPLACE FUNCTION security.layer4_inbox_items_v1()
 RETURNS TABLE(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- CF-247 Layer 4 Inbox performance (4 Nov 2026): every item that needs a person, one row each, from security.layer4_inbox_items_v2
  select * from security.layer4_inbox_items_v2(null, null, null, true)
$function$
