CREATE OR REPLACE FUNCTION security.aer_schedule_held_v1(p_limit integer)
 RETURNS TABLE(item_id uuid, course_id uuid, provider_id uuid, country text, eligible boolean, outcome text)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_scan int := security.pipeline_num_v1('aer.schedule_held_scan', 40)::int;
        v_retry interval := make_interval(days => security.pipeline_num_v1('aer.schedule_held_retry_days', 14)::int);
        v_tries int := security.pipeline_num_v1('aer.schedule_held_max_tries', 2)::int;
        r record; g jsonb; v_chk jsonb; v_n int := 0;
begin
  if coalesce(p_limit, 0) <= 0 then return; end if;
  for r in select i.id, i.entity_id, c.provider_id pid, e.country cc, pg.url
             from pipeline.layer4_review_items i
             join catalogue.courses c on c.id = i.entity_id
             join security.aer_eligible_v1() e on e.provider_id = c.provider_id
             left join pipeline.coverage_course_pages pg on pg.course_id = i.entity_id
             left join pipeline.aer_schedule_checks k on k.item_id = i.id
            where i.field_code = 'course_entry_first_read' and i.status = 'pending'
              and (security.aer_schedule_country_v1(e.country)->>'on')::boolean
              and not exists (select 1 from pipeline.aer_read_supersessions s where s.old_item_id = i.id and (s.state = 'requested' or s.requested_at > now() - v_retry))
              and (select count(*) from pipeline.aer_read_supersessions s where s.old_item_id = i.id) < v_tries
            order by k.checked_at nulls first, i.created_at, i.id
            limit v_scan loop
    item_id := r.id; course_id := r.entity_id; provider_id := r.pid; country := r.cc; eligible := false;
    g := security.course_entry_gate_v1(r.id);
    if g is null or coalesce((g->>'complete')::boolean, false) then outcome := 'complete';
    elsif jsonb_array_length(coalesce(g->'shared_page', '[]'::jsonb)) > 0 then outcome := 'shared page: for a person';
    elsif coalesce((g->>'rows_cut')::int, 0) > 0 then outcome := 'cut at the row limit: for a person';
    elsif jsonb_array_length(coalesce(g->'drops_uncovered', '[]'::jsonb)) = 0 then outcome := 'held only for rows a person leaves out';
    else
      v_chk := security.course_entry_correction_check_v1(r.id, r.entity_id, r.url);
      if coalesce((v_chk->>'ok')::boolean, false) then
        if v_n < p_limit then eligible := true; outcome := 'held: read again (D-R2)'; v_n := v_n + 1; else outcome := 'held: next run'; end if;
      else outcome := left('held, not correctable: ' || coalesce(v_chk->>'why', ''), 300); end if;
    end if;
    return next;
  end loop;
end $function$
