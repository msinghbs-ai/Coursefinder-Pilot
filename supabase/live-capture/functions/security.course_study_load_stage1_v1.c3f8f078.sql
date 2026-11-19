CREATE OR REPLACE FUNCTION security.course_study_load_stage1_v1(p_apply boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'public'
AS $function$
declare v_set int := 0; v_by jsonb;
begin
  if auth.uid() is not null and coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;
  create temp table if not exists _csl (course_id uuid, load text, evidence_id uuid) on commit drop;
  truncate _csl;
  insert into _csl
  select r.course_id,
         case when r.ft and r.pt then 'both' when r.ft then 'full_time' else 'part_time' end,
         r.evidence_id
    from (select f.course_id,
                 bool_or(lower(f.quote) ~ '\mfull[- ]?time\M' and lower(f.quote) !~ '\mfull[- ]?time[- ]equivalent') ft,
                 bool_or(lower(f.quote) ~ '\mpart[- ]?time\M' and lower(f.quote) !~ '\mpart[- ]?time (work|job|jobs|employment)\M') pt,
                 (array_agg(f.evidence_id order by f.updated_at desc nulls last, f.id desc)
                    filter (where (lower(f.quote) ~ '\mfull[- ]?time\M' or lower(f.quote) ~ '\mpart[- ]?time\M') and f.evidence_id is not null))[1] evidence_id
            from pipeline.field_enrich_items f
            join catalogue.courses c on c.id = f.course_id and c.lifecycle_status = 'active'
           where f.state = 'filled' and f.field in ('duration', 'intakes', 'delivery') and f.quote is not null
           group by f.course_id) r
   where r.ft or r.pt;
  select jsonb_object_agg(load, n) into v_by from (select load, count(*) n from _csl group by 1) z;
  if p_apply then
    update catalogue.courses c set study_load = s.load, study_load_source = 'provider_page', study_load_evidence_id = s.evidence_id
      from _csl s
     where c.id = s.course_id
       and coalesce(c.study_load_source, 'provider_page') = 'provider_page'
       and (c.study_load, c.study_load_source, c.study_load_evidence_id) is distinct from (s.load, 'provider_page', s.evidence_id);
    get diagnostics v_set = row_count;
    insert into pipeline.admin_control_events (area, action, target, detail, actor)
    values ('api_v3', 'course_study_load_stage1', 'catalogue.courses.study_load',
            jsonb_build_object('set', v_set, 'by_load', v_by, 'source', 'provider_page'), auth.uid());
  end if;
  return jsonb_build_object('applied', p_apply, 'set', v_set, 'by_load', v_by);
end;
$function$
