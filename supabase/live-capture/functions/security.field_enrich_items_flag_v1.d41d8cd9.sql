CREATE OR REPLACE FUNCTION security.field_enrich_items_flag_v1()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare f record;
begin
  if new.course_id is null or new.state is not distinct from old.state then return null; end if;
  if new.state = 'skipped' and coalesce(new.reason, '') ~* '(does not state|names no campus|quote is not on the page|site-wide line|no allowed source|not classified)' then
    perform security.flag_raise_v1('course', new.course_id::text, new.provider_id, new.field, 'enrich_no_value', 'Enrich fields: ' || new.reason, 'soft', 'enrich-fields', 'auto',
      jsonb_build_object('job_id', new.job_id, 'item_id', new.id, 'source', new.source, 'tried', new.tried, 'cost_usd', new.cost_usd, 'evidence_id', new.evidence_id),
      coalesce(new.evidence_id::text, new.storage_path), null);
  elsif new.state = 'filled' then
    for f in select id from pipeline.enrichment_flags where entity = 'course' and entity_key = new.course_id::text and field = new.field and reason_code = 'enrich_no_value' and state <> 'released' loop
      perform security.flag_release_v1(f.id, 'enrich-fields', 'auto', 'Value found by Enrich fields', jsonb_build_object('job_id', new.job_id, 'item_id', new.id), false);
    end loop;
  end if;
  return null;
end $function$
