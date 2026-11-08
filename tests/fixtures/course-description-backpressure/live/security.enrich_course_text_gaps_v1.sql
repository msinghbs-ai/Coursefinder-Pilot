CREATE OR REPLACE FUNCTION security.enrich_course_text_gaps_v1(p_fields text[])
 RETURNS TABLE(provider_id uuid, course_id uuid, field text, pri integer)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_cap int := security.pipeline_num_v1('enrich.course_text_items_per_day', 500)::int; v_days int := security.pipeline_num_v1('gaps.recheck_days', 60)::int;
        f text; v_room int;
begin
  foreach f in array array['description', 'deadline'] loop
    continue when not (f = any (coalesce(p_fields, '{}'::text[])));
    select v_cap - count(*) into v_room from pipeline.field_enrich_items e join pipeline.admin_jobs j on j.id = e.job_id
     where e.field = f and e.created_at > now() - interval '1 day' and coalesce((j.args->>'standing')::boolean, false);  -- fixed: the cap is a day's
    continue when coalesce(v_room, 0) <= 0;
    return query
      with miss as (
        select c.id cid, c.provider_id pid from catalogue.courses c
         where c.lifecycle_status = 'active'
           and case f when 'description' then nullif(btrim(c.description), '') is null else security.enrich_deadline_missing_v1(c.id) end
           -- read from the stored page only: the slice's rule (bound, or ambiguous with an identity proof, read)
           and exists (select 1 from pipeline.coverage_course_pages g where g.course_id = c.id and g.evidence_id is not null and g.status in ('bound', 'ambiguous')
                         and g.read_status = 'read' and g.identity_basis is not null)),
      last as (
        select distinct on (e.course_id) e.course_id cid, e.state, e.updated_at, e.reason
          from pipeline.field_enrich_items e where e.field = f and e.course_id in (select m.cid from miss m) order by e.course_id, e.id desc)
      select m.pid, m.cid, f, case when l.state is null then 1
                                    when exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at) then 0 else 2 end
        from miss m left join last l on l.cid = m.cid
       where not exists (select 1 from pipeline.manual_locks k where k.entity = 'course' and k.entity_id = m.cid and k.field in (f, 'all'))
         and coalesce(l.state, '') not in ('queued', 'waiting', 'ai', 'leased', 'review')
         and (l.state is null or l.state = 'filled' or l.reason = 'provider unpublished' or l.updated_at < now() - make_interval(days => v_days)
              or exists (select 1 from pipeline.coverage_course_pages g where g.course_id = m.cid and g.read_at > l.updated_at))
         and not security.enrich_item_held_v1(m.cid, f)
         and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = m.pid)
       order by 4, m.cid
       limit v_room;
  end loop;
end $function$;
