CREATE OR REPLACE FUNCTION public.svc_fee_ai_next(p_limit integer)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v jsonb := '[]'::jsonb; q record;
begin
  if coalesce(auth.role(), '') <> 'service_role' then raise exception 'service role required' using errcode = '42501'; end if;
  for q in
    update pipeline.fee_reader_queue x set state = 'leased', leased_until = now() + interval '4 minutes', attempts = attempts + 1  -- fixed: lease longer than one worker call
     where x.id in (select y.id from pipeline.fee_reader_queue y
                     where (y.state = 'queued' or (y.state = 'leased' and y.leased_until < now())) and y.attempts < 3  -- fixed: three tries
                       and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = y.provider_id)  -- 22 Oct 2026 (Platform Admin 11:42): unpublished providers wait; publishing them again brings them back
                     order by y.priority desc, y.created_at limit greatest(1, least(coalesce(p_limit, 3), security.pipeline_num_v1('fees.pages_per_run', 10)::int)) for update skip locked)
    returning x.*
  loop
    v := v || (
      select jsonb_build_object(
        'queue_id', q.id, 'source_id', coalesce(f.id, q.fact_source_id), 'url', coalesce(f.url, ce.source_url, cg.url), 'storage_path', coalesce(e.storage_path, ce.storage_path),
        -- CF-247 23 Oct 2026: a course's own page; the worker reads the stored page as text and the course list is that one course
        'course_page', q.course_id is not null,
        'provider', coalesce(p.display_name, p.canonical_name), 'country', k.iso_alpha2,
        'profile', (select to_jsonb(cp) - 'reason' - 'updated_by' - 'updated_at' from pipeline.fee_country_profiles cp where cp.country_code = k.iso_alpha2),
        'model', (select s.model_identifier from pipeline.central_ai_settings s where s.id = 1),
        'model_code', (select s.model_code from pipeline.central_ai_settings s where s.id = 1),
        'page_chars', security.pipeline_num_v1('fees.page_chars', 40000)::int,
        'notes', case when q.course_id is null then (select r.notes from pipeline.fee_reader_recipes r where r.provider_id = q.provider_id) end,
        'findings', coalesce((select jsonb_agg(jsonb_build_object('kind', z.kind, 'detail', z.detail, 'times', z.times) order by z.last_seen desc)
                                from (select * from pipeline.fee_reader_findings x where x.provider_id = q.provider_id and x.resolved_at is null
                                      order by x.last_seen desc limit security.pipeline_num_v1('fees.findings_in_prompt', 10)::int) z), '[]'::jsonb),
        'courses', coalesce((select jsonb_agg(jsonb_build_object('id', c.id, 'title', c.canonical_title, 'level', sl.code) order by c.canonical_title)
                               from catalogue.courses c left join ref.study_levels sl on sl.id = c.study_level_id
                              where c.provider_id = q.provider_id and c.lifecycle_status = 'active' and (q.course_id is null or c.id = q.course_id)), '[]'::jsonb))
        from catalogue.providers p join ref.countries k on k.id = p.country_id
        left join pipeline.provider_fact_sources f on f.id = q.fact_source_id and q.course_id is null
        left join pipeline.evidence_artifacts e on e.id = f.evidence_id
        left join pipeline.coverage_course_pages cg on cg.course_id = q.course_id
        left join pipeline.evidence_artifacts ce on ce.id = q.evidence_id
       where p.id = q.provider_id and (q.course_id is not null or f.id is not null));
  end loop;
  return v;
end $function$
