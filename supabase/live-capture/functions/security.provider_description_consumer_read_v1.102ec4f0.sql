CREATE OR REPLACE FUNCTION security.provider_description_consumer_read_v1(p_consumer text, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb; v_error text;
begin
 if p_consumer='website' then v:=public.website_v2_provider(p_key);
 elsif p_consumer='zoho' then v:=public.zoho_v2_provider(p_key);
 else raise exception 'unsupported consumer'; end if;
 return v;
exception when others then
 get stacked diagnostics v_error=message_text;
 return jsonb_build_object('error',jsonb_build_object('code',sqlstate,'message',v_error),'consumer',p_consumer);
end $function$
