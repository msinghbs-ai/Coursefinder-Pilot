CREATE OR REPLACE FUNCTION public.website_v3_course_search(p_filters jsonb, p_page integer, p_page_size integer, p_sort text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v3_course_search_core(p_filters, p_page, p_page_size, p_sort);
begin
  if jsonb_typeof(v->'items') = 'array' then
    v := jsonb_set(v, '{items}', (select coalesce(jsonb_agg(public.website_v3_course_search_item(x) order by o), '[]'::jsonb)
                                    from jsonb_array_elements(v->'items') with ordinality t(x, o)));
  end if;
  return v;
end $function$
