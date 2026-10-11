CREATE OR REPLACE FUNCTION public.svc_scholarship_register_detail_save(p_register text, p_evidence_id uuid, p_items jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_saved int := 0; v_remaining bigint; v_match jsonb;
begin
  if current_user <> 'postgres' and coalesce(auth.role(),'') <> 'service_role' then raise exception 'service_role required'; end if;
  update scholarship.register_listings l
     set website_url = case when nullif(x->>'error','') is null then nullif(x->>'website_url','') else l.website_url end,
         detail_error = nullif(left(x->>'error', 300),''),
         provider_cricos = coalesce(upper(nullif(x->>'provider_cricos','')), l.provider_cricos),
         provider_id = coalesce(public.svc_scholarship_resolve_au_provider(coalesce(upper(nullif(x->>'provider_cricos','')), l.provider_cricos)), l.provider_id),
         detail_read_at = now(), detail_hash = l.content_hash, detail_evidence_id = p_evidence_id
    from jsonb_array_elements(coalesce(p_items,'[]'::jsonb)) x
   where l.register_code = p_register and l.listing_id = x->>'id';
  get diagnostics v_saved = row_count;
  v_match := public.svc_scholarship_register_match(p_register);
  select count(*) into v_remaining from scholarship.register_listings l
   where l.register_code = p_register and l.departed_at is null and (l.detail_read_at is null or l.detail_hash is distinct from l.content_hash);
  return jsonb_build_object('saved', v_saved, 'remaining', v_remaining, 'match', v_match);
end $function$
