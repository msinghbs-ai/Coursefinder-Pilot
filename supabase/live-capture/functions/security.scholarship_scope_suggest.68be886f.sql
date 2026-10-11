CREATE OR REPLACE FUNCTION security.scholarship_scope_suggest(p_scholarship_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare v_name text; v_title text; v_levels jsonb := '[]'::jsonb; v_fields jsonb := '[]'::jsonb; v_why text[] := '{}';
begin
  select s.name into v_name from scholarship.scholarships s where s.id = p_scholarship_id;
  if v_name is null then return null; end if;
  if v_name ~* '\y(travel|conference|accommodation|hardship|emergency|relocation|prize|placement|exchange|study abroad|mobility|internship)\y' then
    return jsonb_build_object('decision', 'none', 'filter', '{}'::jsonb, 'why', 'The name suggests support that is not tied to a course''s tuition (for example travel or hardship).');
  end if;
  v_title := nullif(btrim(regexp_replace(substring(v_name from '(?:Bachelor|Master|Graduate Certificate|Graduate Diploma|Diploma|Doctor) of [A-Z][A-Za-z&'' -]+'),
                   '(\s+(Scholarship|Scholarships|Award|Awards|Prize|Bursary|Grant|Pioneers|Excellence|Top-Up|Fund))+\s*$', '', 'i')), '');
  if v_title is not null then
    return jsonb_build_object('decision', 'filter', 'filter', jsonb_build_object('title', v_title), 'why', 'The name mentions one course: ' || v_title || '.');
  end if;
  if v_name ~* '\y(research|phd|doctoral|hdr|higher degree)\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Doctorate / PhD','Masters Degree (Research)')); v_why := array_append(v_why, 'research degrees');
  elsif v_name ~* '\yundergraduate\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Bachelor','Bachelor Honours Degree','Diploma','Advanced Diploma','Associate Degree')); v_why := array_append(v_why, 'undergraduate courses');
  elsif v_name ~* '\y(postgraduate|masters|master''s)\y' then
    v_levels := (select jsonb_agg(id) from ref.study_levels where name in ('Masters Degree (Coursework)','Masters Degree (Extended)','Graduate Certificate','Graduate Diploma','Masters')); v_why := array_append(v_why, 'postgraduate coursework');
  end if;
  v_fields := (select jsonb_agg(id) from ref.fields_of_study where path ~ '^asced/[0-9]{2}$' and (
                  (path = 'asced/02' and v_name ~* '\y(IT|information technology|computing|computer|data science|cyber)\y')
               or (path = 'asced/03' and v_name ~* '\yengineering\y')
               or (path = 'asced/04' and v_name ~* '\y(architecture|built environment|building)\y')
               or (path = 'asced/06' and v_name ~* '\y(health|medicine|medical|nursing|pharmacy|dentistry|physiotherapy)\y')
               or (path = 'asced/07' and v_name ~* '\y(education|teaching)\y')
               or (path = 'asced/08' and v_name ~* '\y(business|commerce|accounting|finance|MBA|management|economics)\y')
               or (path = 'asced/09' and v_name ~* '\y(law|arts|humanities|social science|psychology)\y')
               or (path = 'asced/10' and v_name ~* '\y(creative|music|design|fine art|media)\y')
               or (path = 'asced/01' and v_name ~* '\yscience\y' and v_name !~* '\y(computer|data|social) science\y')));
  if v_fields is not null then v_why := array_append(v_why, 'the field named in the title'); end if;
  if jsonb_array_length(coalesce(v_levels, '[]'::jsonb)) > 0 or v_fields is not null then
    return jsonb_build_object('decision', 'filter', 'filter', jsonb_strip_nulls(jsonb_build_object('levels', v_levels, 'fields', v_fields)),
                              'why', 'The name points to ' || array_to_string(v_why, ' and ') || '.');
  end if;
  return jsonb_build_object('decision', 'all', 'filter', '{}'::jsonb, 'why', 'The name does not narrow it down; check the scholarship page before accepting all.');
end $function$
