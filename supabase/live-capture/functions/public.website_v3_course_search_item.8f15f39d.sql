CREATE OR REPLACE FUNCTION public.website_v3_course_search_item(p_item jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v3_course_item_r28(p_item); v_desc text;
begin
  if v is null or jsonb_typeof(v) <> 'object' then return v; end if;
  select nullif(btrim(d.description), '') into v_desc from search.course_documents d
   where lower(d.course_stable_key) = lower(v->>'course_id') and d.course_stable_key is not null limit 1;
  if v_desc is not null and length(v_desc) > 240 then  -- fixed: API contract (build brief WP-1.7: first 240 characters, whole words)
    v_desc := coalesce(nullif(regexp_replace(left(v_desc, 240), '\s+\S*$', ''), ''), left(v_desc, 240)) || '…';  -- fixed: as above
  end if;
  return v || jsonb_build_object('description_excerpt', v_desc);
end $function$
