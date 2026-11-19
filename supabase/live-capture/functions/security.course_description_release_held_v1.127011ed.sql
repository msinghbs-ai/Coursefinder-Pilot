CREATE OR REPLACE FUNCTION security.course_description_release_held_v1(p_provider uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r record; v_n int := 0; v_k int;
begin
  if p_provider is null or not security.course_description_trusted_v1(p_provider) then return 0; end if;
  for r in select e.id, e.course_id, e.value->>'text' txt from pipeline.field_enrich_items e join pipeline.coverage_course_pages g on g.course_id = e.course_id
            where e.provider_id = p_provider and e.field = 'description' and e.state = 'skipped' and e.reason like 'held_first_admission:%'
              and nullif(btrim(e.value->>'text'), '') is not null and e.evidence_id is not distinct from g.evidence_id
            for update of e skip locked loop
    if exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = r.course_id and l.field in ('description', 'course_description', 'all')) then continue; end if;
    -- the checks are run again (another course may have taken the same words since)
    if not coalesce((security.course_description_check_v1(r.course_id, (select e.value from pipeline.field_enrich_items e where e.id = r.id))->>'ok')::boolean, false) then continue; end if;
    update catalogue.courses set description = r.txt, updated_at = now() where id = r.course_id and nullif(btrim(description), '') is null;
    get diagnostics v_k = row_count;
    update pipeline.field_enrich_items set state = case when v_k > 0 then 'filled' else 'skipped' end, reason = case when v_k > 0 then null else 'already filled' end,
           value = value || jsonb_build_object('admitted', 'held, admitted once the provider''s first descriptions were approved'), updated_at = now() where id = r.id;
    v_n := v_n + v_k;
  end loop;
  if v_n > 0 then
    insert into search.refresh_requests(requested_by) select 'AI reader (course description, deadline)'
     where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (course description, deadline)');
  end if;
  return v_n;
end $function$
