-- CF-247 F-SCH redesign: detail-fill audit (12 Nov 2026 20:05 AEDT; 1,276 scholarships read with sch-extract-v3, US$1.06). A 10-record sample of
-- filled descriptions matched the stored evidence; a 10-record sample of nationality criteria had one whose passage is a telephone code menu
-- ("China (中国) +86"). Of the 162 nationality criteria, 8 have a passage with no nationality wording: a phone menu, a testimonial ("I am Rahman,
-- an Indonesian awardee"), a parent's alumni status, the country of a school exam (Gaokao), enrolment at an institution in a country, and lists with
-- no heading. Separately, 3 published scholarships carry a placeholder award of under $50 (UWA $0.10 and $0.15, a $11 research scholarship) that a
-- description would repeat.
-- The fill now writes a nationality only from a passage that says citizenship, nationality, residence, origin or students from a country (and not a
-- testimonial or alumni line), and writes no description for a record whose fixed award is under the floor below. The 8 criteria are superseded
-- (kept) and their scholarships re-read by the nationality reader; the descriptions the fill wrote for the 3 placeholder-amount records are returned
-- to what they were.
-- Replaces: nothing (the fill's checks are extended). Retires: nothing.

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('security.scholarship_detail_apply_v1(bigint)', '259d6ec98211c8ca2152aae8bc0105fc', array[
  array[$o$  if coalesce((c->'summary'->>'ok')::boolean, false) and length(coalesce(s.description, '')) < 80$o$,
        $n$  -- 20261113066000: no description for a placeholder award (a fixed amount under the floor; fixed: a scholarship of less than 50 in any currency is a page placeholder)
  if coalesce((c->'summary'->>'ok')::boolean, false) and length(coalesce(s.description, '')) < 80
     and not (s.award_value_type = 'fixed_amount' and s.award_amount < 50)$n$],
  array[$o$  if coalesce((c->'nationality'->>'proven')::boolean, false)$o$,
        $n$  -- 20261113066000: only a passage that states citizenship, nationality, residence, origin or students from a country (not a testimonial or alumni line)
  if coalesce((c->'nationality'->>'proven')::boolean, false)
     and coalesce(d->'nationality'->>'quote', '') ~* '(citizen|nationals?\M|nationality|passport|residen|descent|origin|born in|(students?|applicants?|candidates?|people|those) (from|of)\M|eligible countr|following countr)'
     and coalesce(d->'nationality'->>'quote', '') !~* '(\mI am\M|\mI''m\M|awardee|alumn)'$n$]
], array[1, 1]);

do $r$
declare v_ids uuid[]; v_n int; v_d int := 0; x record;
begin
  -- the 8 nationality criteria without nationality wording: superseded (kept); their scholarships are read again by the nationality reader
  with c as (update scholarship.criteria set status = 'superseded'
              where criterion_type = 'nationality' and value_json->>'by' = 'sch-extract-v3' and status = 'active'
                and (human_text !~* '(citizen|nationals?\M|nationality|passport|residen|descent|origin|born in|(students?|applicants?|candidates?|people|those) (from|of)\M|eligible countr|following countr)'
                     or human_text ~* '(\mI am\M|\mI''m\M|awardee|alumn)')
             returning scholarship_id)
  select array_agg(distinct scholarship_id) into v_ids from c;
  v_n := coalesce(cardinality(v_ids), 0);
  if v_n > 0 then update scholarship.scholarships set updated_at = now() where id = any (v_ids); end if;
  -- the fill's descriptions for placeholder-amount records go back to what they were (a description entered by hand is never touched)
  for x in select distinct on (sc.scholarship_id) sc.scholarship_id, sc.before_value
             from pipeline.scholarship_sweep_changes sc join scholarship.scholarships s on s.id = sc.scholarship_id
            where sc.field = 'description' and sc.after_value->>'by' = 'sch-extract-v3'
              and s.award_value_type = 'fixed_amount' and s.award_amount < 50 and s.description = sc.after_value->>'text'
              and not exists (select 1 from pipeline.manual_locks k where k.entity = 'scholarship' and k.entity_id = s.id and k.field = 'description')
            order by sc.scholarship_id, sc.id desc loop
    update scholarship.scholarships set description = x.before_value #>> '{}', updated_at = now() where id = x.scholarship_id;
    insert into pipeline.scholarship_sweep_changes(scholarship_id, field, before_value, after_value)
    values (x.scholarship_id, 'description', null, jsonb_build_object('by', '20261113066000', 'returned_to', x.before_value, 'why', 'placeholder award under the floor'));
    v_d := v_d + 1;
  end loop;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('scholarships', 'sch_detail_guards', 'Scholarship detail fill: nationality wording and placeholder-amount guards',
          jsonb_build_object('nationality_superseded_for', v_n, 'descriptions_returned', v_d, 'migration', '20261113066000'), '63ba56cb-48d4-4169-98c2-7c4d1f72925b');
  raise notice 'nationality criteria superseded for % scholarships; % descriptions returned', v_n, v_d;
end $r$;
