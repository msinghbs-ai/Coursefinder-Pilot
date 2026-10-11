CREATE OR REPLACE FUNCTION security.scholarship_nationality_read_v1()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'pg_catalog', 'scholarship', 'pipeline', 'security', 'ref', 'catalogue'
AS $function$
declare v_read int := 0; v_changed int := 0; v_with int := 0;
begin
  with t as (
    select s.id, k.iso_alpha2 study_country,
           coalesce(s.name,'') || ' ' || coalesce(s.description,'') || ' ' || coalesce((select string_agg(c.human_text, ' ') from scholarship.criteria c where c.scholarship_id = s.id), '') txt
      from scholarship.scholarships s left join catalogue.providers p on p.id = s.provider_id left join ref.countries k on k.id = p.country_id
     where s.lifecycle_status = 'active'
       and not exists (select 1 from scholarship.nationality_readings a where a.scholarship_id = s.id and a.reader_version = 'scholarship-nationality-v1' and a.read_at >= s.updated_at
                         and a.read_at >= coalesce((select max(c.created_at) from scholarship.criteria c where c.scholarship_id = s.id), '-infinity'::timestamptz))
     order by (select a.read_at from scholarship.nationality_readings a where a.scholarship_id = s.id) nulls first, s.id
     limit 150),
  m as (
    select t.id, x.code,
           coalesce(substring(t.txt from ('(?i)\m(?:citizens?|nationals?|passport holders?|permanent residents?|residents?|students?|applicants?|candidates?|scholars?) (?:of|from) (?:the )?(?:' || x.names || ')\M')),
                    substring(t.txt from ('(?i)\m(?:' || coalesce(nullif(x.demonyms, ''), 'ZZZZ') || ') (?:citizens?|nationals?|passport holders?|students?|applicants?|candidates?)\M')),
                    substring(t.txt from ('(?i)\m(?:' || x.names || ') (?:citizens?|nationals?|passport holders?)\M'))) phrase
      from t, ref.nationality_terms x
     where x.code <> coalesce(t.study_country, 'AU') and not (x.code = 'AU' and coalesce(t.study_country, 'AU') in ('AU', 'NZ')) and not (x.code = 'NZ' and t.study_country = 'AU')),
  r as (
    select t.id, coalesce((select array_agg(m.code order by m.code) from m where m.id = t.id and m.phrase is not null), '{}'::text[]) codes,
           coalesce((select jsonb_object_agg(m.code, m.phrase) from m where m.id = t.id and m.phrase is not null), '{}'::jsonb) phrases
      from t),
  up as (
    insert into scholarship.nationality_readings(scholarship_id, codes, phrases, reader_version, read_at)
    select r.id, r.codes, r.phrases, 'scholarship-nationality-v1', now() from r
    on conflict (scholarship_id) do update set codes = excluded.codes, phrases = excluded.phrases, reader_version = excluded.reader_version, read_at = now()
    returning scholarship_id, codes)
  select count(*), count(*) filter (where cardinality(codes) > 0) into v_read, v_with from up;
  update scholarship.scholarships s set nationalities = a.codes, updated_at = now() from scholarship.nationality_readings a where a.scholarship_id = s.id and s.lifecycle_status = 'active' and s.nationalities is distinct from a.codes and not security.scholarship_from_record_register(s.id) and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'nationalities');
  get diagnostics v_changed = row_count;
  if v_changed > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('scholarships', 'nationality_read', 'Nationality read from each scholarship''s wording', jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed, 'decision', 'Decision 246'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  end if;
  return jsonb_build_object('read', v_read, 'with_nationality', v_with, 'changed', v_changed);
end $function$
