CREATE OR REPLACE FUNCTION security.layer4_boost_study_load_inbox_detail_v1(p_ref text)
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select jsonb_build_object(
    'sections', jsonb_build_array(
      jsonb_build_object('key', 'page', 'title', 'Course page', 'body', jsonb_build_object('Course', c.display_title, 'Page', r.source_url, 'Stored copy (evidence)', r.evidence_id)),
      jsonb_build_object('key', 'reading', 'title', 'What the model read',
        'body', jsonb_build_object('Study load', coalesce(replace(r.answer->>'study_load', '_', '-'), 'not stated'), 'Quoted from the page', coalesce(r.answer->>'quote', '(no quote)'))),
      jsonb_build_object('key', 'refused', 'title', 'Why the page check refused it', 'body', r.problems),
      jsonb_build_object('key', 'rule', 'title', 'The rule',
        'body', 'Report the study load the page states for international students when it states one (for example "International student visa holders can only study full-time"); otherwise the study load it states for the course. Never from delivery mode or duration alone. A decision fills the course only while its study load is empty.')),
    'actions', jsonb_build_array(jsonb_build_object('key', 'accept_full_time', 'allowed', true), jsonb_build_object('key', 'accept_part_time', 'allowed', true),
                                 jsonb_build_object('key', 'accept_both', 'allowed', true), jsonb_build_object('key', 'not_stated', 'allowed', true),
                                 jsonb_build_object('key', 'dismiss', 'allowed', true)))
    from pipeline.boost_study_load_reviews r join catalogue.courses c on c.id = r.course_id
   where r.id::text = p_ref and r.status = 'open'
$function$
