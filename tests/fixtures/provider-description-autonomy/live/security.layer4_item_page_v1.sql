CREATE OR REPLACE FUNCTION security.layer4_item_page_v1(p_field text, p_value jsonb, p_l2 jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
-- The page an item is about: the proposed address of a course link, the page a fee was read from.
  select nullif(btrim(coalesce(case jsonb_typeof(p_value) when 'string' then p_value #>> '{}' when 'object' then coalesce(p_value->>'course_url', p_value->>'url', p_value->>'page') end,
                               p_l2->>'page')), '')
$function$

