-- CF-247 F-CDESC: a held course description whose only remaining fault is its size is shortened by whole sentences.
-- Platform Admin 13 Nov 2026 12:16 (S2-CF decision, section 1): "Approve deterministic sentence-level shortening of the approximately 190 length-only or
-- sentence-count-only held descriptions, using the existing subset recovery", on conditions: complete, independent, supported sentences are kept; not simply the
-- first N; no cut inside a sentence; no filler; dangling references removed; every existing check applies to the final text; the machine admission policy and the
-- evidence thresholds are not changed; stored answers are reused with no AI call; the original and final text, the reason and the machine decision are recorded.
-- What: security.cdesc_subset_plan_v1  3c263a1984a33a133a331883cc6f8eae -> 2fd1a050b0e70c0ae9298a0d7419b075
--   New step 1c, only for a reading whose only fault is its size (no sentence failed a test). While the reading is over
--   enrich.course_description_max_sentences or _max_chars, one choice is set aside per pass. A choice is a kept sentence (never the first) together with the
--   sentences after it that refer back to it (new security.cdesc_refers_back_v1: an opener that points back, or "these", "those", "such", "this" about something
--   other than the course; they go with it). A choice that a later kept sentence may refer to from inside it (security.cdesc_refers_within_v1) is not taken. The choice that by itself brings the reading within the limits is taken before one that does not;
--   then the one that loses least course-specific substance (new security.cdesc_sentence_substance_v1: the distinct words of four or more letters of a sentence
--   that are also in its own quote); the later sentence on a tie. A choice that would remove a sentence about a qualification, registration, recognition, pathway,
--   placement or entry condition is never taken: when only such choices are left the reading stays held (over_length_needs_decision). So does a reading that
--   cannot fit, and a reading with a failing sentence and a size problem (outside the approval).
-- Known limit of the rule (QA of this change): "substance" counts supported words and cannot judge meaning; the protected sentence kinds are a word list.
--   Both err towards keeping a reading held.
--   The remainder goes through the same full check (security.course_description_check_v1), the wording policy and the machine rule as before: none of them is edited.
--   The record of a recovery already holds the original sentences and text, the sentences set aside with their cause (now also over_limit), the kept ones and the
--   machine decision (pipeline.course_description_machine_admissions.checks -> subset_of_reading).
-- Data mark: the subset attempt noted as over_length_needs_decision is cleared on held and waiting readings, so they are looked at again.
-- Guards: G2 (no operational value: the limits are the existing settings; the word length is the rule of security.pdesc_support_v1, marked fixed), G3, housekeeping s42.
-- Replaces: security.cdesc_subset_plan_v1(uuid,uuid,jsonb) (same name and signature, by named edits, md5-guarded).
-- Retires: nothing.
-- Reversal: supabase/held/cdesc_shorten_forward_recovery.sql (reverse edits; the new function stays until removed by paste file).

create or replace function pg_temp.edit_all(p_sig text, p_before text, p_after text, p_olds text[], p_news text[]) returns text language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_src text := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure); v_c int; i int;
begin
  -- fixed: the guard is the md5 of the function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
  if md5(v_src) = p_after then return p_sig || ': already applied'; end if;
  if md5(v_src) <> p_before then raise exception 'live % differs from the definition this change replaces (body md5 %)', p_sig, md5(v_src); end if;
  -- fixed: line endings are normalised, so the edit applies the same however the text arrives
  v_def := replace(v_def, chr(13), '');
  for i in 1 .. array_length(p_olds, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_olds[i], ''))) / length(p_olds[i]);
    if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', p_sig, i, v_c; end if;
    v_def := replace(v_def, p_olds[i], p_news[i]);
  end loop;
  execute v_def;
  v_src := (select p.prosrc from pg_proc p where p.oid = p_sig::regprocedure);
  if md5(v_src) <> p_after then raise exception '% after the edit has body md5 %, expected %', p_sig, md5(v_src), p_after; end if;
  return p_sig || ': applied';
end $f$;

create or replace function security.cdesc_sentence_substance_v1(p_text text, p_quote text) returns integer language sql immutable set search_path = '' as $ss$
  -- fixed: words of four or more letters compared on their first five, the rule of security.pdesc_support_v1 (a count of supported words, not a share)
  select count(*)::int from (select distinct left(w, 5) w from regexp_split_to_table(lower(coalesce(p_text, '')), '[^a-z0-9]+') w where length(w) >= 4) s
   where s.w in (select left(q, 5) from regexp_split_to_table(lower(coalesce(p_quote, '')), '[^a-z0-9]+') q where length(q) >= 4)
$ss$;
comment on function security.cdesc_sentence_substance_v1(text, text) is
  'Course description shortening: how many distinct words of a sentence (four or more letters, compared on their first five) are also in its own quote. Used only to choose which whole sentence is set aside when a reading is over its size limits.';
revoke all on function security.cdesc_sentence_substance_v1(text, text) from public, anon, authenticated;

create or replace function security.cdesc_refers_within_v1(p_text text) returns boolean language sql immutable set search_path = '' as $rw$
  -- fixed: a structural test of the grammar: the sentence says "these", "those", "such" (not "such as") or "this" (not "this course", "this program" and the
  -- like, which mean the course itself) anywhere in it. What it refers to may be any earlier sentence, not only the one before
  select coalesce(p_text, '') ~* '\m(these|those)\M|\msuch\s+(?!\s|as\M)|\mthis\s+(?!\s|(course|program|programme|qualification|degree|diploma|certificate|award|major|specialisation|specialization|master|bachelor|unit|subject)\M)'
$rw$;
comment on function security.cdesc_refers_within_v1(text) is
  'Course description shortening: true when a sentence says these, those, such or this about something other than the course, anywhere in it. Used only to decide which sentences may be set aside when a size-only reading is shortened.';
revoke all on function security.cdesc_refers_within_v1(text) from public, anon, authenticated;

create or replace function security.cdesc_refers_back_v1(p_text text) returns boolean language sql immutable set search_path = '' as $rb$
  -- fixed: a structural test of the grammar: the sentence opens by pointing back (security.cdesc_points_back_v1) or refers to something earlier inside it
  select security.cdesc_points_back_v1(p_text) or security.cdesc_refers_within_v1(p_text)
$rb$;
comment on function security.cdesc_refers_back_v1(text) is
  'Course description shortening: true when a sentence refers back to an earlier one (it opens by pointing back, or says these, those, such or this about something other than the course). Used only to decide which sentences go together when a size-only reading is shortened.';
revoke all on function security.cdesc_refers_back_v1(text) from public, anon, authenticated;

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '3c263a1984a33a133a331883cc6f8eae', '2fd1a050b0e70c0ae9298a0d7419b075',
  array[$o0$v_page text; v_title text; v_prov text;
begin$o0$,
        $o1$  -- 2. every sentence that passes is kept, in its original order. Nothing is cut for length or sentence count: a reading whose only fault is its size stays held (the Platform Admin decides that separately)
$o1$,
        $o2$'every sentence passes; the reading is over the set sentence or character limit and is held whole (a decision to cut is not taken here)'$o2$,
        $o3$'after the failing sentences are set aside the remainder is still over the set sentence or character limit; it is held whole (a decision to cut is not taken here)'$o3$],
  array[$n0$v_page text; v_title text; v_prov text; v_cnt int; v_tot int; v_first int; v_victim int; v_c int; v_bc int; v_p boolean; v_bp boolean; v_rc int; v_rl int; v_f boolean; v_bf boolean;
begin$n0$,
        $n1$  -- 1c. (Platform Admin 13 Nov 2026 12:16, conditional approval) a reading whose ONLY fault is its size (no sentence failed a test) and that is over the sentence or
  --     character limit is shortened by whole sentences, never inside one. Each pass looks at every kept sentence but the first (it says what the course is) together
  --     with the sentences after it that refer back to it (security.cdesc_refers_back_v1: they would dangle, so they go with it), and sets aside the choice that
  --     (a) by itself brings the reading within the limits, before one that does not, then (b) loses least course-specific substance
  --     (security.cdesc_sentence_substance_v1), the later sentence on a tie. A choice that would remove a sentence about a qualification, registration, recognition,
  --     pathway, placement or entry condition is never taken, nor one that a later kept sentence may refer to (security.cdesc_refers_within_v1): if only such
  --     choices are left, nothing more is set aside and the reading stays held below.
  --     Repeated until the reading fits. A reading that cannot fit stays held. A reading with a failing sentence AND a size problem is outside the approval:
  --     it is not shortened here and stays held (over_length_needs_decision).
  if not exists (select 1 from unnest(v_fault) x(f) where x.f is not null) then
    loop
      select count(*), coalesce(sum(length(btrim(coalesce(v_s->(k - 1)->>'text', '')))), 0) + greatest(count(*) - 1, 0), min(k) into v_cnt, v_tot, v_first from generate_series(1, n) k where v_fault[k] is null;
      exit when v_cnt <= 1 or (v_cnt <= v_max and v_tot <= v_maxc);
      v_victim := null;
      for k in reverse n .. v_first + 1 loop
        continue when v_fault[k] is not null;
        v_c := 0; v_p := false; v_rc := 0; v_rl := 0; i := k;
        loop
          v_c := v_c + security.cdesc_sentence_substance_v1(v_s->(i - 1)->>'text', v_s->(i - 1)->>'quote');
          v_rc := v_rc + 1; v_rl := v_rl + length(btrim(coalesce(v_s->(i - 1)->>'text', ''))) + 1;
          -- fixed: a structural test of what a sentence is about (a qualification, registration, recognition, pathway, placement or entry condition), not a tunable limit
          v_p := v_p or coalesce(v_s->(i - 1)->>'text', '') ~* '\m(regist|licen|qualif|recogni|endors|certif|accredit|pathway|eligib|pre-?requisit|placement|practicum|internship|admission|entry requirement|must (hold|have|be|complete))';
          i := i + 1;
          exit when i > n or v_fault[i] is not null or not security.cdesc_refers_back_v1(v_s->(i - 1)->>'text');
        end loop;
        -- a later sentence that stays and says "these", "those", "such" or "this" may refer to this choice: the choice is then not taken (as a protected one)
        v_p := v_p or exists (select 1 from generate_series(i, n) j where v_fault[j] is null and security.cdesc_refers_within_v1(v_s->(j - 1)->>'text'));
        -- does the reading still not fit once this choice is set aside
        v_f := not (v_cnt - v_rc <= v_max and v_tot - v_rl <= v_maxc);
        if v_victim is null or (v_p, v_f, v_c) < (v_bp, v_bf, v_bc) then v_victim := k; v_bp := v_p; v_bf := v_f; v_bc := v_c; end if;
      end loop;
      -- only protected choices are left: nothing more is set aside, the reading stays held
      exit when v_victim is null or v_bp;
      v_fault[v_victim] := 'over_limit';
      for i in v_victim + 1 .. n loop
        exit when v_fault[i] is not null or not security.cdesc_refers_back_v1(v_s->(i - 1)->>'text');
        v_fault[i] := 'depends_on_dropped_sentence';
      end loop;
    end loop;
  end if;
  -- 2. every sentence that passes and was not set aside for size is kept, in its original order. No sentence is ever cut inside: a reading that cannot be brought within the limits by whole sentences stays held
$n1$,
        $n2$'every sentence passes; the reading is over the set sentence or character limit and cannot be brought within it by setting whole sentences aside without losing a protected sentence; it is held whole'$n2$,
        $n3$'the reading is still over the set sentence or character limit (a reading with a failing sentence is not shortened; a size-only reading could not be brought within it by whole sentences); it is held whole'$n3$]);

-- the comment of the recovery said "never cutting for size": it now says what is done (comment only; the function is not edited)
comment on function security.cdesc_subset_recover_v1() is
  'Course descriptions: recovers a reading stuck on a few sentences by setting those sentences aside (a size-only reading is shortened by whole sentences under security.cdesc_subset_plan_v1 step 1c; no sentence is ever cut inside) and passing the rest to the same check and machine rule. Looks at readings held by the reader''s check (including copied_sentence and generic_phrase) and at waiting items the machine declined for wording. Time box 45 s, ending 60 s into the job.';

do $marks$
declare v_a int;
begin
  update pipeline.field_enrich_items e set value = e.value - 'subset_attempt'
   where e.field = 'description' and e.state in ('skipped', 'review') and e.value->'subset_attempt'->>'result' = 'over_length_needs_decision';
  get diagnostics v_a = row_count;
  -- fixed: a stop bound well above what was measured (2 attempts noted; about 240 readings are over their limits)
  if v_a > 3000 then raise exception 'the mark would touch % attempts, far more than measured: stopped, nothing applied', v_a; end if;
  raise notice 'subset attempts cleared: %', v_a;
end $marks$;

do $post$
begin
  if security.cdesc_sentence_substance_v1('Students study marine engines and hull design.', 'The course covers marine engines, hull design and safety.') <> 4 then raise exception 'post-check: substance'; end if;
  if security.cdesc_sentence_substance_v1(null, null) <> 0 then raise exception 'post-check: substance of nothing'; end if;
  if not security.cdesc_refers_back_v1('Students apply these skills in a final project.') or security.cdesc_refers_back_v1('Students in this program study topics such as anatomy.') then raise exception 'post-check: refers back'; end if;
  if security.cdesc_refers_within_v1('Students in this  course study topics such  as anatomy.') or not security.cdesc_refers_within_v1('It builds on this foundation.') then raise exception 'post-check: refers within'; end if;
end $post$;
