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
    ('provider_address', 'Provider street address', 'provider', array['ai_stored', 'scraper'], 7)) v(field, label, level, sources, sort)
$function$
