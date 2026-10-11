CREATE OR REPLACE FUNCTION public.svc_scholarship_listing_record(p_id bigint, p_status text, p_http_status integer, p_items jsonb, p_error text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_items jsonb := case when jsonb_typeof(p_items) = 'array' then p_items else '[]'::jsonb end; v_hash text;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select md5(coalesce(string_agg(lower(btrim(e->>'name')), '|' order by lower(btrim(e->>'name'))), '')) into v_hash from jsonb_array_elements(v_items) e;
  update pipeline.scholarship_listing_pages
     set status = case when p_status = 'read' then 'read' else 'failed' end, http_status = p_http_status, read_at = now(), error = left(p_error, 300),
         items = case when p_status = 'read' then v_items else items end, item_hash = case when p_status = 'read' then v_hash else item_hash end,
         next_read_at = case when p_status = 'read' then now() + interval '7 days' else now() + interval '1 day' end
   where id = p_id;
  return jsonb_build_object('ok', true, 'items', jsonb_array_length(v_items));
end $function$
