CREATE OR REPLACE FUNCTION security.field_crosscheck_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_new int; v_closed int; v_tol numeric := security.pipeline_num_v1('crosscheck.duration_tolerance_pct', 10);
begin
  -- the latest adapter reading of each course page (the same reading Enrich fields uses), compared with the held value
  drop table if exists _cc;
  create temp table _cc on commit drop as
  select y.id, y.provider_id, y.field, y.held_value, y.page_value, 'adapter'::text source, left(y.txt, 300) quote, y.ev
    from (
      select x.id, x.provider_id, f.field, f.held_value, f.page_value, f.txt, x.ev, f.differs
        from (select c.id, c.provider_id, c.duration_value, c.duration_unit, c.study_level_id, c.delivery_mode,
                     (select g.evidence_id from pipeline.coverage_course_pages g where g.course_id = c.id) ev,
                     coalesce((select r.fields->'extra' from pipeline.uni_adapter_results r where r.course_id = c.id order by r.at desc limit 1), '{}'::jsonb)
                     || coalesce((select g.candidates->'adapter_extra' from pipeline.coverage_course_pages g
                                   where g.course_id = c.id and g.read_status = 'read' and g.identity_basis is not null), '{}'::jsonb) ex
                from catalogue.courses c where c.lifecycle_status = 'active') x
        cross join lateral (
          select 'duration' field, jsonb_build_object('value', x.duration_value, 'unit', x.duration_unit) held_value, d page_value, x.ex->>'duration' txt,
                 abs(w1 - w2) * 100 > v_tol * greatest(w1, w2) differs
            from (select security.enrich_parse_duration_v1(nullif(btrim(x.ex->>'duration'), '')) d) p,
                 lateral (select case x.duration_unit when 'years' then x.duration_value * 52 when 'months' then x.duration_value * 52 / 12 when 'weeks' then x.duration_value end w1,
                                 case p.d->>'unit' when 'years' then (p.d->>'value')::numeric * 52 when 'months' then (p.d->>'value')::numeric * 52 / 12 when 'weeks' then (p.d->>'value')::numeric end w2) w
           where p.d is not null and x.duration_value is not null and w.w1 > 0 and w.w2 > 0
             and coalesce(x.ex->>'duration', '') !~* '\d\s*(-|–|to|or)\s*\d'
          union all
          select 'level', jsonb_build_object('level_id', x.study_level_id, 'name', (select l.name from ref.study_levels l where l.id = x.study_level_id)),
                 jsonb_build_object('level_id', p.l, 'name', (select l.name from ref.study_levels l where l.id = p.l)), x.ex->>'study_level', p.l <> x.study_level_id
            from (select security.enrich_parse_level_v1(nullif(btrim(x.ex->>'study_level'), '')) l) p
           where p.l is not null and x.study_level_id is not null
          union all
          select 'delivery', jsonb_build_object('mode', x.delivery_mode), jsonb_build_object('mode', p.m), x.ex->>'mode', p.m <> x.delivery_mode
            from (select security.delivery_mode_read_v1(left(nullif(btrim(x.ex->>'mode'), ''), 300), x.provider_id) m) p
           where p.m is not null and nullif(btrim(x.delivery_mode), '') is not null) f
       where x.ex <> '{}'::jsonb) y
   where y.differs
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = y.id and l.field in (y.field, 'all'))
  ;
  insert into pipeline.field_crosscheck_findings(course_id, provider_id, field, held_value, page_value, source, quote, evidence_id)
  select c.id, c.provider_id, c.field, c.held_value, c.page_value, c.source, c.quote, c.ev from _cc c
  on conflict (course_id, field, page_value) do nothing;
  get diagnostics v_new = row_count;
  -- CF-247 21 Oct 2026 (delivery reader): an open finding that no longer differs (the held value or the page reading changed) closes itself
  update pipeline.field_crosscheck_findings f set state = 'resolved', decided_at = now(), note = 'no longer differs: the held value or the page reading changed'
   where f.state = 'open' and not exists (select 1 from _cc c where c.id = f.course_id and c.field = f.field and c.page_value = f.page_value);
  get diagnostics v_closed = row_count;
  return jsonb_build_object('new', v_new, 'resolved', v_closed, 'open', (select count(*) from pipeline.field_crosscheck_findings where state = 'open'));
end $function$
