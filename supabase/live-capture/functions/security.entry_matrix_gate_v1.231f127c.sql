CREATE OR REPLACE FUNCTION security.entry_matrix_gate_v1(p_run uuid, p_exclude uuid[] DEFAULT '{}'::uuid[])
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r pipeline.entry_matrix_runs%rowtype; s pipeline.entry_matrix_sources%rowtype; v_ex uuid[] := coalesce(p_exclude, '{}'::uuid[]);
        v_why text[] := '{}'; v_fix boolean := true; v_rows int; v_wait int; v_lost jsonb; v_cov int; v_missing jsonb; v_flag jsonb; v_dup jsonb; v_qc int;
        v_n int := security.pipeline_num_v1('entry.gate_cover_chars', 40)::int; v_m int := security.pipeline_num_v1('entry.gate_cover_min_chars', 12)::int;
        v_ignore jsonb := coalesce(security.toolset_setting('pipeline', 'entry.matrix_gate_ignore_reasons'), '[]'::jsonb);
        v_rank text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_rank_words'), '[]'::jsonb)) w where btrim(w) <> '');
        v_score text := (select string_agg('(' || w || ')', '|') from jsonb_array_elements_text(coalesce(security.toolset_setting('pipeline', 'entry.matrix_score_words'), '[]'::jsonb)) w where btrim(w) <> '');
begin
  select * into r from pipeline.entry_matrix_runs where id = p_run;
  if r.id is null then return null; end if;
  if security.pipeline_num_v1('entry.matrix_gate', 1) < 1 then
    return jsonb_build_object('rule', 'D-R3', 'complete', true, 'off', true, 'reasons', '[]'::jsonb);
  end if;
  select * into s from pipeline.entry_matrix_sources where id = r.source_id;
  -- the read is of the source's current stored copy and finished
  if r.state is distinct from 'done' then v_why := v_why || format('the read has not finished (%s)', coalesce(r.state, 'no state')); v_fix := false; end if;
  if s.id is null or r.content_hash is distinct from s.content_hash then
    v_why := v_why || 'the read is not of the source''s current stored copy: read the current copy before deciding'::text; v_fix := false;
  end if;
  -- the reader's own verdict, where it made one
  if coalesce(r.result->'completeness'->>'status', 'not_applicable') not in ('not_applicable', 'complete') then
    v_why := v_why || format('the reader''s completeness check did not pass (%s)', r.result->'completeness'->>'status'); v_fix := false;
  end if;
  -- rows changed since the read: every row the read proposed still waits (admitted or left out by the reviewer)
  select count(*) filter (where m.status = 'proposed'), count(*) filter (where m.status = 'proposed' and not (m.id = any (v_ex))) into v_wait, v_rows
    from catalogue.provider_entry_matrix m where m.run_id = r.id;
  if v_wait is distinct from coalesce(r.rows_admitted, 0) then
    v_why := v_why || format('%s row(s) wait but the read proposed %s: rows changed since the read', v_wait, coalesce(r.rows_admitted, 0)); v_fix := false;
  end if;
  -- dropped published rows that no admitted row covers (left out rows do not cover anything)
  with a as (select lower(regexp_replace(coalesce(m.quote, ''), '[^[:alnum:]]', '', 'g')) fq, m.country_code
               from catalogue.provider_entry_matrix m where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex))),
       d as (select x, lower(regexp_replace(coalesce(x->>'quote', ''), '[^[:alnum:]]', '', 'g')) fq
               from jsonb_array_elements(coalesce(r.result->'dropped', '[]'::jsonb)) x where not (v_ignore ? coalesce(x->>'reason', ''))),
       dc as (select d.x, exists (select 1 from a where length(d.fq) >= v_m and strpos(a.fq, left(d.fq, v_n)) > 0) cov from d)
  select coalesce(jsonb_agg(jsonb_build_object('reason', x->>'reason', 'country', x->>'country', 'quote', left(x->>'quote', 120))) filter (where not cov), '[]'::jsonb),
         count(*) filter (where cov),
         coalesce((select jsonb_agg(distinct dc2.x->>'country') from dc dc2 where not dc2.cov and coalesce(dc2.x->>'country', '') <> ''
                     and not exists (select 1 from a where a.country_code = upper(dc2.x->>'country'))), '[]'::jsonb)
    into v_lost, v_cov, v_missing from dc;
  if jsonb_array_length(v_lost) > 0 then
    v_why := v_why || format('the reader dropped %s published row(s) that no admitted row covers (%s)%s, so the read is incomplete: replace it with a corrected read, or reject it',
                             jsonb_array_length(v_lost),
                             (select string_agg(k || ' ' || c, ', ') from (select l->>'reason' k, count(*) c from jsonb_array_elements(v_lost) l group by 1 order by 1) z),
                             case when jsonb_array_length(v_missing) > 0 then '; left with no row at all: ' || (select string_agg(c, ', ' order by c) from jsonb_array_elements_text(v_missing) c) else '' end);
    v_fix := false;
  end if;
  -- row-level problems (each can be left out with Approve except)
  select coalesce(jsonb_agg(jsonb_build_object('id', m.id, 'why', w.why) order by m.id), '[]'::jsonb) into v_flag
    from catalogue.provider_entry_matrix m
    cross join lateral (select array(select (regexp_matches(coalesce(m.quote, ''), '[0-9]+(?:\.[0-9]+)?', 'g'))[1]) nums) n
    cross join lateral (select case
        when m.provider_id is distinct from r.provider_id or m.source_id is distinct from r.source_id or m.content_hash is distinct from r.content_hash
          then 'another provider, source or stored copy'
        -- F-AER.08 (12 Nov 2026, decision 1): every course minimum belongs to exactly one catalogue course
        when m.course_label is not null and m.course_id is null and security.pipeline_num_v1('aer.course_link_on', 1) >= 1
          then 'the course is not linked to a catalogue course (Layer 4 course links)'
        when btrim(coalesce(m.qualification_name, '')) = '' or (v_rank is not null and m.qualification_name ~* v_rank) or (v_score is not null and m.qualification_name ~* v_score)
          then 'qualification named by a column label'
        when m.grade_scale = 'rank' and v_score is not null and coalesce(m.quote, '') ~* v_score
          then 'the provider''s rank is stored as the qualification''s minimum'
        when v_rank is not null and v_score is not null and coalesce(m.min_grade, '') ~* v_rank and coalesce(m.quote, '') ~* v_score
          then 'the provider''s rank is stored as the qualification''s minimum'
        -- a ladder quote printing the rank and the score: the minimum is the score's own cell (the second number when the rank is printed first)
        when v_rank is not null and v_score is not null and m.min_value is not null and coalesce(m.quote, '') ~* v_rank and coalesce(m.quote, '') ~* v_score
             and cardinality(n.nums) = 2
             and m.min_value <> (case when strpos(lower(m.quote), lower(substring(m.quote from '(?i)(' || v_rank || ')')))
                                         < strpos(lower(m.quote), lower(substring(m.quote from '(?i)(' || v_score || ')'))) then n.nums[2] else n.nums[1] end)::numeric
          then 'the provider''s rank is stored as the qualification''s minimum'
        when coalesce(m.benchmark_band, '') <> '' and ((v_rank is not null and m.benchmark_band ~* v_rank) or (v_score is not null and m.benchmark_band ~* v_score))
          then 'the band holds label text, not a band'
        when m.min_value is not null and (coalesce(m.grade_scale, 'none') = 'none' or strpos(coalesce(m.quote, ''), trim_scale(m.min_value)::text) = 0)
          then 'the value has no scale or is not printed in its quote'
        when length(regexp_replace(coalesce(m.quote, ''), '[^[:alnum:]]', '', 'g')) < v_m / 2
          then 'the quote is too short to prove the row'
        end why) w
   where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex)) and w.why is not null;
  if jsonb_array_length(v_flag) > 0 then
    v_why := v_why || format('%s waiting row(s) cannot be admitted as read (%s): leave them out with Approve except, or replace the read with a corrected one',
                             jsonb_array_length(v_flag), (select string_agg(k || ' ' || c, '; ') from (select f->>'why' k, count(*) c from jsonb_array_elements(v_flag) f group by 1 order by 1) z));
  end if;
  -- F-AER.08 (12 Nov 2026): a qualification minimum printed for one course waits until that course is linked (it is never admitted as the provider's)
  if security.pipeline_num_v1('aer.course_link_on', 1) >= 1 then
    select count(*) into v_qc from catalogue.provider_qualification_requirements q where q.run_id = r.id and q.status = 'proposed' and q.course_label is not null and q.course_id is null and not (q.id = any (v_ex));
    if v_qc > 0 then
      v_why := v_why || format('%s qualification row(s) belong to a course not linked to a catalogue course: link the course in Layer 4 course links, then decide', v_qc); v_fix := false;
    end if;
  end if;
  select coalesce(jsonb_agg(g.ids), '[]'::jsonb) into v_dup
    from (select jsonb_agg(m.id order by m.id) ids from catalogue.provider_entry_matrix m
           where m.run_id = r.id and m.status = 'proposed' and not (m.id = any (v_ex)) group by m.row_hash having count(*) > 1) g;
  if jsonb_array_length(v_dup) > 0 then
    v_why := v_why || format('%s group(s) of waiting rows share one identity (%s rows): leave out all but one of each, or replace the read with a corrected one',
                             jsonb_array_length(v_dup), (select sum(jsonb_array_length(g)) from jsonb_array_elements(v_dup) g));
  end if;
  return jsonb_build_object('rule', 'D-R3', 'complete', cardinality(v_why) = 0, 'rows', v_rows, 'waiting', v_wait, 'read_rows', r.rows_admitted,
                            'dropped_lost', v_lost, 'dropped_covered', v_cov, 'countries_missing', v_missing, 'flagged', v_flag, 'same_identity', v_dup,
                            'except_fixable', v_fix, 'no_table', coalesce(r.result->>'outcome', '') = 'no_requirements_table',
                            'reasons', to_jsonb(v_why));
end $function$
