CREATE OR REPLACE FUNCTION security.enrich_campus_list_apply_v1(p_item bigint)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare i pipeline.field_enrich_items%rowtype; x jsonb; v_cid uuid; v_min int := security.pipeline_num_v1('enrich.campus_min_pages', 2)::int;
        v_admitted jsonb := '[]'::jsonb; v_review jsonb := '[]'::jsonb; v_pages int; v_country uuid; v_sub uuid; r record; v_ids jsonb; v_linked int := 0;
begin
  select * into i from pipeline.field_enrich_items where id = p_item for update;
  select p.country_id, p.subdivision_id into v_country, v_sub from catalogue.providers p where p.id = i.provider_id;
  for x in select * from jsonb_array_elements(coalesce(i.value->'campuses', '[]'::jsonb)) loop
    -- agreement: the course pages that name this campus (its raw names) are counted from the job's own campus items
    select count(*) into v_pages from pipeline.field_enrich_items c
     where c.job_id = i.job_id and c.provider_id = i.provider_id and c.field = 'campus' and c.course_id is not null
       and exists (select 1 from jsonb_array_elements_text(coalesce(x->'raw', '[]'::jsonb)) rw where lower(c.quote) like '%' || lower(rw) || '%');
    if v_pages < v_min then v_review := v_review || (x || jsonb_build_object('pages', v_pages)); continue; end if;
    select ca.id into v_cid from catalogue.campuses ca where ca.provider_id = i.provider_id and lower(ca.name) = lower(x->>'name') limit 1;
    if v_cid is null then
      insert into catalogue.campuses(stable_key, provider_id, name, country_id, subdivision_id, city, address_line1, postcode, status, publication_status, evidence_id)
      values ('campus:studysearch:' || i.provider_id || ':' || regexp_replace(lower(x->>'name'), '[^a-z0-9]+', '-', 'g'), i.provider_id, left(x->>'name', 160), v_country, v_sub,
              left(nullif(x->>'city', ''), 120), left(nullif(x->>'street', ''), 200), left(nullif(x->>'postcode', ''), 20), 'active', 'published', i.evidence_id)
      on conflict (stable_key) do update set updated_at = now()
      returning id into v_cid;
    end if;
    v_admitted := v_admitted || (x || jsonb_build_object('campus_id', v_cid, 'pages', v_pages));
  end loop;
  update pipeline.field_enrich_items set state = case when jsonb_array_length(v_admitted) > 0 then 'filled' when jsonb_array_length(v_review) > 0 then 'review' else 'skipped' end,
         value = value || jsonb_build_object('admitted', v_admitted, 'to_review', v_review),
         reason = case when jsonb_array_length(v_review) > 0 then jsonb_array_length(v_review) || ' campus name(s) named on too few course pages: a person decides' else reason end, updated_at = now()
   where id = i.id;
  return jsonb_build_object('admitted', jsonb_array_length(v_admitted), 'review', jsonb_array_length(v_review));
end $function$
