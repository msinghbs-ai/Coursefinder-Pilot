CREATE OR REPLACE FUNCTION security.enrich_fields_v1()
 RETURNS TABLE(field text, label text, level text, sources text[], sort integer)
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select * from (values
    ('campus', 'Campus (with the campus list)', 'course', array['adapter', 'ai_stored'], 1),
    ('duration', 'Duration', 'course', array['adapter', 'ai_stored'], 2),
    ('level', 'Study level', 'course', array['adapter', 'ai_title'], 3),
    ('delivery', 'Delivery mode', 'course', array['adapter', 'ai_stored'], 4),
    ('field_of_study', 'Field of study', 'course', array['ai_title'], 5),
    ('international', 'Open to international students', 'course', array['institution_rule', 'adapter', 'ai_stored'], 6),
    ('provider_address', 'Provider street address', 'provider', array['ai_stored', 'scraper'], 7),
    -- 23 Oct 2026 (Platform Admin 10:25): English, intakes and campus regions too
    ('english', 'English requirement (IELTS)', 'course', array['ai_stored'], 8),
    ('intakes', 'Intakes (start months)', 'course', array['ai_stored'], 9),
    ('campus_region', 'Campus region (state)', 'provider', array['ai_city'], 10)) v(field, label, level, sources, sort)
$function$
