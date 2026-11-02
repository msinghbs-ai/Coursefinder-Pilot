CREATE OR REPLACE FUNCTION security.manual_fact_guard()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r jsonb; v_field text;
begin
  if coalesce(current_setting('cf.manual_edit', true), '') = 'on' then
    if TG_OP = 'DELETE' then return OLD; end if; return NEW;
  end if;
  if TG_OP = 'DELETE' then r := to_jsonb(OLD); else r := to_jsonb(NEW); end if;
  v_field := case TG_TABLE_NAME
               when 'course_links' then case when r->>'link_type' = 'official_course' then 'official_url' else 'link:' || (r->>'link_type') end
               when 'course_intakes' then 'intakes'
               when 'course_english_requirements' then 'english'
               when 'course_fees' then case when r->>'fee_type' = 'provider_current_tuition' then 'tuition' end end;
  if v_field is not null and exists (select 1 from pipeline.manual_locks l where l.entity = 'course' and l.entity_id = (r->>'course_id')::uuid and l.field = v_field) then
    return null;
  end if;
  if TG_OP = 'DELETE' then return OLD; end if;
  return NEW;
end $function$
