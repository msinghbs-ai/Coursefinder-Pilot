CREATE OR REPLACE FUNCTION public.website_v3_sync(p_cursor text, p_full boolean, p_entities text[], p_page_size integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v2_sync(p_cursor, p_full, p_entities, p_page_size);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(case when not (x ? 'item') or jsonb_typeof(x->'item') <> 'object' then x
                                                                  when x->>'entity' = 'course' then jsonb_set(x, '{item}', public.website_v3_course_item_r28(x->'item'))
                                                                  when x->>'entity' = 'provider' then jsonb_set(x, '{item}', public.website_v3_provider_item(x->'item'))
                                                                  when x->>'entity' = 'scholarship' then jsonb_set(x, '{item}', public.website_v3_scholarship_item(x->'item'))
                                                                  else x end order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $function$
