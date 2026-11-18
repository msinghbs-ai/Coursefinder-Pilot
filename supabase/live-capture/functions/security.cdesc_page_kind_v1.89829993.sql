CREATE OR REPLACE FUNCTION security.cdesc_page_kind_v1(p_url text, p_title text, p_basis text)
 RETURNS text
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare v_path text; v_segs text[]; v_n int; v_tok text[]; v_ta text[]; v_st text[]; v_good boolean[]; v_i int; v_clean text; v_dis int;
        -- fixed: the names a university gives its institution-level pages and its course tabs (structure of the web, not an operating value)
        v_inst constant text := '^(about-us|aboutus|about-(?!(this|the|your|our)-(course|program|programme|degree|qualification|unit|study)s?(-|$))[a-z0-9-]+|[a-z0-9-]+-about-us|who-we-are|why-(study|choose|come|join|learn)-(with|at|in)-[a-z0-9-]+|why-us|our-(story|history|values|university|college|institute|mission|vision|people|campus|campuses)(-[a-z0-9-]+)?|facts-(and|n|&)-figures|facts-figures|at-a-glance|(university|college|institute)-(overview|profile|facts)[a-z0-9-]*)$';
        v_amb constant text := '^(about|overview|about-(this|the|your)-(course|program|programme|degree|qualification))$';
        -- fixed: award words and joining words never identify a subject; a word of fewer than four letters never does either (of, in, and, the ...)
        v_award constant text[] := array['bachelor', 'master', 'masters', 'doctor', 'diploma', 'certificate', 'graduate', 'postgraduate', 'honours', 'associate'];
        v_stop constant text[] := array['bachelor', 'master', 'masters', 'doctor', 'diploma', 'certificate', 'graduate', 'postgraduate', 'honours', 'associate', 'degree', 'advanced', 'with', 'level', 'course', 'program', 'programme'];
        -- fixed: a segment that names a faculty, school or department (a part of the university) is not a course
        v_fac constant text[] := array['faculty', 'faculties', 'school', 'schools', 'department', 'departments', 'dept', 'college', 'colleges', 'institute', 'centre', 'center', 'division', 'campus', 'university'];
begin
  if nullif(btrim(coalesce(p_url, '')), '') is null then return 'no_bound_page'; end if;
  v_path := lower(regexp_replace(split_part(split_part(btrim(p_url), '#', 1), '?', 1), '^[a-z][a-z0-9+.-]*://[^/]*', ''));
  v_segs := array(select regexp_replace(x, '\.(html?|shtml|aspx?|php|jsp|cfm)$', '') from regexp_split_to_table(v_path, '/') with ordinality t(x, o) where x <> '' order by o);
  v_n := coalesce(array_length(v_segs, 1), 0);
  while v_n > 1 and v_segs[v_n] in ('index', 'default', 'home') loop v_segs := v_segs[1 : v_n - 1]; v_n := v_n - 1; end loop;
  if v_n = 0 then return 'no_course_in_address'; end if;
  if exists (select 1 from unnest(v_segs) x where x ~ v_inst) then return 'university_about_page'; end if;
  -- a bare about / overview anywhere but at the end is a parent section of the university
  for v_i in 1 .. v_n - 1 loop
    if v_segs[v_i] ~ v_amb then return 'university_about_page'; end if;
  end loop;
  if v_segs[v_n] !~ v_amb and p_basis is distinct from 'host_page' then return null; end if;
  -- the course title: its distinctive subject words and its award words
  v_clean := regexp_replace(regexp_replace(lower(coalesce(p_title, '')), 'level\s*\d+', ' ', 'g'), '[^a-z0-9]+', ' ', 'g');
  v_tok := array(select distinct w from regexp_split_to_table(v_clean, ' ') w where length(w) >= 4 and not (w = any (v_stop))); -- fixed: a word of fewer than four letters never identifies a subject
  v_ta := array(select distinct w from regexp_split_to_table(v_clean, ' ') w where w = any (v_award));
  v_dis := coalesce(array_length(v_tok, 1), 0);
  v_good := array_fill(false, array[v_n]);
  for v_i in 1 .. v_n loop
    continue when v_segs[v_i] ~ v_amb;
    v_st := array(select w from regexp_split_to_table(v_segs[v_i], '[-_]+') w where w <> '');
    -- the segment names the course: all the distinctive title words (word-set containment), an award word of the title if it has one, and no faculty / school / department word the title does not carry
    v_good[v_i] := v_dis > 0 and v_tok <@ v_st and (cardinality(v_ta) = 0 or v_ta && v_st)
                   and not exists (select 1 from unnest(v_st) w where w = any (v_fac) and not (w = any (v_tok)));
  end loop;
  if v_segs[v_n] ~ v_amb then
    if v_n >= 2 and v_good[v_n - 1] then return null; end if;
    return 'university_about_page';
  end if;
  if true = any (v_good) then return null; end if;
  return 'host_page_no_course_evidence';
end $function$
