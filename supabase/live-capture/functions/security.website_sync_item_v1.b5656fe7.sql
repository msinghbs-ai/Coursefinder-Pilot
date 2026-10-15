CREATE OR REPLACE FUNCTION security.website_sync_item_v1(p_entity text, p_ref uuid, p_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb;
begin
  if p_entity = 'course' then v := case when p_ref is null then null else api.website_v2_course_item(p_ref, null, null) end;  -- the search item (Wix CF_Courses)
  elsif p_entity = 'scholarship' then v := public.website_v2_scholarship(p_key)->'item';
  elsif p_entity = 'reference' then v := public.website_v2_reference();
  elsif p_entity in ('provider', 'logo', 'rankings') then
    if p_ref is null or exists (select 1 from security.provider_hidden_v1 h where h.provider_id = p_ref)
       or not exists (select 1 from search.course_documents d where d.provider_id = p_ref) then return null; end if;
    if p_entity = 'provider' then v := public.website_v2_provider(p_key)->'item';
    elsif p_entity = 'logo' then
      v := api.website_v2_provider_logo(p_ref);
      v := case when v is null or v = 'null'::jsonb then null else jsonb_build_object('provider_id', p_key, 'logo', v) end;
    else
      v := public.website_v2_provider_rankings(p_ref);
      v := case when v is null or jsonb_typeof(v) <> 'array' or jsonb_array_length(v) = 0 then null else jsonb_build_object('provider_id', p_key, 'rankings', v) end;
    end if;
  end if;
  return case when v = 'null'::jsonb then null else v end;
end $function$
