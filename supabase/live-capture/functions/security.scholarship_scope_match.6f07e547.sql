CREATE OR REPLACE FUNCTION security.scholarship_scope_match(p_course_id uuid, p_decision text, p_filter jsonb)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select case p_decision when 'all' then true when 'none' then false else
    exists (select 1 from catalogue.courses c
             where c.id = p_course_id
               and (   c.id::text in (select jsonb_array_elements_text(coalesce(p_filter->'courses', '[]'::jsonb)))
                    or (    (jsonb_array_length(coalesce(p_filter->'levels', '[]'::jsonb)) > 0 or jsonb_array_length(coalesce(p_filter->'fields', '[]'::jsonb)) > 0
                             or nullif(btrim(coalesce(p_filter->>'title', '')), '') is not null)
                        and (jsonb_array_length(coalesce(p_filter->'levels', '[]'::jsonb)) = 0
                             or c.study_level_id::text in (select jsonb_array_elements_text(p_filter->'levels')))
                        and (jsonb_array_length(coalesce(p_filter->'fields', '[]'::jsonb)) = 0
                             or security.broad_field_id(c.primary_field_id)::text in (select jsonb_array_elements_text(p_filter->'fields')))
                        and (nullif(btrim(coalesce(p_filter->>'title', '')), '') is null
                             or exists (select 1 from regexp_split_to_table(p_filter->>'title', '\s*,\s*') w
                                         where btrim(w) <> '' and coalesce(c.display_title, c.canonical_title) ilike '%' || btrim(w) || '%')))))
  end
$function$
