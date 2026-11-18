CREATE OR REPLACE FUNCTION security.aer_matrix_machine_exclusions_v1(p_run uuid)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  -- the proposed rows of one read that fail a row rule of the machine check, each with its rule (the same rules, in the same order)
  with cfg as materialized (select security.pipeline_num_v1('aer.matrix_machine_min_confidence', 0.9) conf, security.pipeline_num_v1('aer.machine_min_quote_chars', 8)::int qmin,
                                   security.pipeline_num_v1('aer.course_link_on', 1) >= 1 link_on),
  run as materialized (select r.id, r.source_id from pipeline.entry_matrix_runs r where r.id = p_run),
  m as materialized (select m.* from catalogue.provider_entry_matrix m join run on m.run_id = run.id where m.status = 'proposed'),
  q as materialized (select q.* from catalogue.provider_qualification_requirements q join run on q.run_id = run.id where q.status = 'proposed'),
  why as (
    select m.id, case when coalesce(m.confidence, 0) < cfg.conf then 'low_confidence' when length(btrim(coalesce(m.quote, ''))) < cfg.qmin then 'short_quote'
                      when m.study_level_id is null then 'level_unmapped'
                      when not ((m.min_value is not null and coalesce(m.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(m.min_grade, '')), '') is not null) then 'no_minimum'
                      when not security.aer_quote_has_value_v1(m.quote, m.min_grade, m.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and m.course_label is not null and m.course_id is null then 'course_unlinked'
                      when exists (select 1 from m m2 where m2.row_hash = m.row_hash and m2.id <> m.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_entry_matrix a, run where a.row_hash = m.row_hash and a.status = 'active' and a.id <> m.id
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end w
      from m, cfg
    union all
    select q.id, case when q.applicability = 'unresolved' then 'applicability_unresolved' when coalesce(q.confidence, 0) < cfg.conf then 'low_confidence'
                      when length(btrim(coalesce(q.quote, ''))) < cfg.qmin then 'short_quote' when q.study_level_id is null then 'level_unmapped'
                      when not ((q.min_value is not null and coalesce(q.grade_scale, 'none') <> 'none') or nullif(btrim(coalesce(q.min_grade, '')), '') is not null) then 'no_minimum'
                      when not security.aer_quote_has_value_v1(q.quote, q.min_grade, q.min_value) then 'minimum_not_in_quote'
                      when cfg.link_on and q.course_label is not null and q.course_id is null then 'course_unlinked'
                      when exists (select 1 from q q2 where q2.qualification_code = q.qualification_code and q2.level_label is not distinct from q.level_label
                                      and q2.course_label is not distinct from q.course_label and q2.id <> q.id) then 'duplicate_identity'
                      when exists (select 1 from catalogue.provider_qualification_requirements a, run where a.provider_id = q.provider_id and a.qualification_code = q.qualification_code
                                      and a.level_label is not distinct from q.level_label and a.course_label is not distinct from q.course_label and a.status = 'active'
                                      and a.source_id is distinct from run.source_id) then 'conflicting_active' end
      from q, cfg)
  select jsonb_build_object('ids', coalesce(jsonb_agg(why.id order by why.id) filter (where why.w is not null), '[]'::jsonb),
                            'by_rule', coalesce((select jsonb_object_agg(z.w, z.n) from (select w, count(*) n from why where w is not null group by w) z), '{}'::jsonb))
    from why
$function$
