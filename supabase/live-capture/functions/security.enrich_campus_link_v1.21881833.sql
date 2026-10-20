CREATE OR REPLACE FUNCTION security.enrich_campus_link_v1(p_job uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_ids jsonb; v_linked int := 0;
begin
  for r in select c.id, c.quote, l.state list_state, coalesce(l.value->'admitted', '[]'::jsonb) admitted
             from pipeline.field_enrich_items c
             join pipeline.field_enrich_items l on l.job_id = c.job_id and l.provider_id = c.provider_id and l.field = 'campus_list'
            where c.job_id = p_job and c.field = 'campus' and c.course_id is not null and c.state = 'waiting' and c.quote is not null
              and l.state in ('filled', 'review', 'skipped', 'failed') loop
    select coalesce(jsonb_agg(jsonb_build_object('campus_id', a->>'campus_id', 'name', a->>'name')), '[]'::jsonb) into v_ids
      from jsonb_array_elements(r.admitted) a
     where exists (select 1 from jsonb_array_elements_text(coalesce(a->'raw', '[]'::jsonb)) rw where lower(r.quote) like '%' || lower(rw) || '%');
    if jsonb_array_length(v_ids) > 0 then
      update pipeline.field_enrich_items set value = jsonb_build_object('campuses', v_ids), updated_at = now() where id = r.id;
      if security.enrich_apply_v1(r.id) = 'filled' then v_linked := v_linked + 1; end if;
    elsif r.list_state = 'filled' then
      update pipeline.field_enrich_items set state = 'review', reason = 'the campus named on the page is not in the admitted list', updated_at = now() where id = r.id;
    else
      update pipeline.field_enrich_items set state = 'skipped', reason = 'no campus list was admitted for the university', updated_at = now() where id = r.id;
    end if;
  end loop;
  return v_linked;
end $function$
