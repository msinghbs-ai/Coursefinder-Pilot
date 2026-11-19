CREATE OR REPLACE FUNCTION public.website_v3_course(p_identifier text, p_edu_country text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := public.website_v2_course(p_identifier, p_edu_country); v_course uuid; v_provider uuid; v_cc text := upper(btrim(coalesce(p_edu_country, '')));
begin
  if v ? 'item' then v := jsonb_set(v, '{item}', public.website_v3_course_item_r28(v->'item')); end if;
  if jsonb_typeof(v #> '{item,entry,resolution,rows}') = 'array' then
    select d.course_id, d.provider_id into v_course, v_provider from search.course_documents d
     where lower(d.course_stable_key) = lower(v->'item'->>'course_id') and d.course_stable_key is not null limit 1;
    v := jsonb_set(v, '{item,entry,resolution,rows}', (select coalesce(jsonb_agg(r || jsonb_build_object('source_url', coalesce(
             (select m.source_url from catalogue.provider_entry_matrix m
               where m.provider_id = v_provider and m.status = 'active' and m.country_code = v_cc and m.quote = r->>'quote' order by m.updated_at desc limit 1),
             (select x.source_url from catalogue.course_entry_requirements x
               where x.course_id = v_course and x.status = 'active' and x.quote = r->>'quote' order by x.updated_at desc limit 1))) order by o), '[]'::jsonb)
        from jsonb_array_elements(v #> '{item,entry,resolution,rows}') with ordinality t(r, o)));
  end if;
  if jsonb_typeof(v->'item') = 'object' then v := jsonb_set(v, '{item}', security.course_roadmap_item_v1(v->'item')); end if;  -- RM1A (O29, O28)
  return v;
end $function$
