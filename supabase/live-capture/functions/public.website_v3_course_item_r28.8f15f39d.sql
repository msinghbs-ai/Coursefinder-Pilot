CREATE OR REPLACE FUNCTION public.website_v3_course_item_r28(p_item jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_course uuid; v_out jsonb;
begin
  if p_item is null or jsonb_typeof(p_item) <> 'object' then return p_item; end if;
  select d.course_id into v_course from search.course_documents d
   where lower(d.course_stable_key) = lower(p_item->>'course_id') and d.course_stable_key is not null limit 1;
  -- 18 Nov 2026 (S1-RM-Design): study_load, empty_reason_code, campuses[].locality and provider.accreditations on every v3 course item
  if jsonb_typeof(p_item->'intakes') is distinct from 'array' then return security.course_v3_fields_v1(p_item, v_course); end if;
  select coalesce(jsonb_agg(e || jsonb_build_object('start_date_status',
           case when nullif(e->>'start_date', '') is not null then 'known'
                else coalesce((select security.intake_start_date_status_v1(i.id)
                                 from catalogue.course_intakes i
                                where i.course_id = v_course and i.status = 'active'
                                  and lower(btrim(i.intake_label)) = lower(btrim(e->>'label'))
                                  and i.intake_year is not distinct from (case when jsonb_typeof(e->'year') = 'number' then (e->>'year')::int end)
                                order by i.start_date is not null desc, i.id limit 1), 'not_yet_read') end)
           order by ord), '[]'::jsonb)
    into v_out
    from jsonb_array_elements(p_item->'intakes') with ordinality x(e, ord);
  return security.course_v3_fields_v1(jsonb_set(p_item, '{intakes}', v_out), v_course);
end $function$
