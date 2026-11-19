CREATE OR REPLACE FUNCTION security.layer4_boost_study_load_kind_v1()
 RETURNS jsonb
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select '{"label": "Boost study load", "order": 37, "choices": [
     {"key": "accept_full_time", "label": "Full-time", "rank": 4, "returns": "The course''s study load becomes Full-time (source manual, evidence the stored page), only if it is still empty"},
     {"key": "accept_part_time", "label": "Part-time", "rank": 4, "returns": "The course''s study load becomes Part-time (source manual, evidence the stored page), only if it is still empty"},
     {"key": "accept_both", "label": "Both full-time and part-time", "rank": 4, "returns": "The course''s study load becomes Both (source manual, evidence the stored page), only if it is still empty"},
     {"key": "not_stated", "label": "Not stated on the page", "rank": 4, "returns": "Recorded; the course keeps no study load and this page is not sent again"},
     {"key": "dismiss", "label": "Dismiss the reading", "rank": 4, "returns": "Recorded; nothing changes on the course and this page is not sent again"}]}'::jsonb
$function$
