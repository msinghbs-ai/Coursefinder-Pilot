CREATE OR REPLACE FUNCTION security.cdesc_refers_within_v1(p_text text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  -- fixed: a structural test of the grammar: the sentence says "these", "those", "such" (not "such as") or "this" (not "this course", "this program" and the
  -- like, which mean the course itself) anywhere in it. What it refers to may be any earlier sentence, not only the one before
  select coalesce(p_text, '') ~* '\m(these|those)\M|\msuch\s+(?!\s|as\M)|\mthis\s+(?!\s|(course|program|programme|qualification|degree|diploma|certificate|award|major|specialisation|specialization|master|bachelor|unit|subject)\M)'
$function$
