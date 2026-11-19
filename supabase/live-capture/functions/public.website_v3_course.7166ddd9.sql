CREATE OR REPLACE FUNCTION public.website_v3_course(p_identifier text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v2_course(p_identifier);
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_roadmap_item_v1(v->'item')); end if;  -- RM1A (O29, O28)
  return v;
end $function$
