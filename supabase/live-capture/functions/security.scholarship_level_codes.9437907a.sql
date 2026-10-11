CREATE OR REPLACE FUNCTION security.scholarship_level_codes(p_levels jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  select coalesce(array_agg(distinct c),'{}') from jsonb_array_elements_text(coalesce(p_levels,'[]')) l
  cross join lateral unnest(case l
    when 'undergraduate' then array['bachelor','bachelor_honours','associate_degree']
    when 'postgraduate_coursework' then array['masters_coursework','masters_extended','masters','graduate_certificate','graduate_diploma']
    when 'research' then array['masters_research','doctorate']
    when 'pathway' then array['diploma','advanced_diploma','certificate_iv','non_aqf_award']
    else array[]::text[] end) c
$function$
