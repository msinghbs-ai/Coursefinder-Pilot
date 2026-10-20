CREATE OR REPLACE FUNCTION security.field_enrich_items_gate_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.course_id is null then return new; end if;
  if exists (select 1 from pipeline.enrichment_flags f
              where f.entity = 'course' and f.entity_key = new.course_id::text and f.field in (new.field, '')
                and ((f.state = 'raised' and f.reason_code in ('enrich_no_value', 'manual_hold'))
                     or (f.state = 'counting' and f.reason_code = 'enrich_no_value'
                         and not exists (select 1 from pipeline.coverage_course_pages g where g.course_id = new.course_id and g.evidence_id is not null
                                           and g.evidence_id::text is distinct from f.input_mark and g.read_at > f.flagged_at)))) then
    return null;  -- held, or tried once on the same input: not queued
  end if;
  return new;
end $function$
