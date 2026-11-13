-- CF-247 F-CDESC: a held course description whose only remaining fault is its size is shortened by whole sentences.
-- Platform Admin 13 Nov 2026 12:16 (S2-CF decision, section 1): "Approve deterministic sentence-level shortening of the approximately 190 length-only or
-- sentence-count-only held descriptions, using the existing subset recovery", on conditions: complete, independent, supported sentences are kept; not simply the
-- first N; no cut inside a sentence; no filler; dangling references removed; every existing check applies to the final text; the machine admission policy and the
-- evidence thresholds are not changed; stored answers are reused with no AI call; the original and final text, the reason and the machine decision are recorded.
-- What: security.cdesc_subset_plan_v1  3c263a1984a33a133a331883cc6f8eae -> 3d6fc72b6736b7c58a0eaf85e93dc460
--   New step 1c. After the failing sentences are set aside, while the reading is over enrich.course_description_max_sentences or _max_chars, the kept sentence with
--   the least course-specific substance is set aside (new security.cdesc_sentence_substance_v1: the distinct words of four or more letters of the sentence that are
--   also in its own quote; the later sentence on a tie), never the first kept sentence, and a sentence that then opens by pointing back to it goes with it
--   (security.cdesc_points_back_v1). If one sentence is left and the reading is still too long, nothing more is set aside and it stays held (over_length_needs_decision).
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

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '3c263a1984a33a133a331883cc6f8eae', '3d6fc72b6736b7c58a0eaf85e93dc460',
  array[$o0$v_page text; v_title text; v_prov text;
begin$o0$,
        $o1$  -- 2. every sentence that passes is kept, in its original order. Nothing is cut for length or sentence count: a reading whose only fault is its size stays held (the Platform Admin decides that separately)
$o1$],
  array[$n0$v_page text; v_title text; v_prov text; v_cnt int; v_tot int; v_victim int;
begin$n0$,
        $n1$  -- 1c. (Platform Admin 13 Nov 2026 12:16, conditional approval) a reading still over the sentence or character limit is shortened by whole sentences, never inside one.
  --     The kept sentence with the least course-specific substance (security.cdesc_sentence_substance_v1: the fewest distinct words that are also in its own quote) is set aside,
  --     the later one on a tie, and never the first kept sentence (it says what the course is). A sentence that then points back to it goes with it, as in 1b.
  --     Repeated until the reading fits. If it cannot fit (one sentence left and still too long) nothing more is set aside and the reading stays held below.
  loop
    select count(*), coalesce(sum(length(btrim(coalesce(v_s->(k - 1)->>'text', '')))), 0) + greatest(count(*) - 1, 0) into v_cnt, v_tot from generate_series(1, n) k where v_fault[k] is null;
    exit when v_cnt <= 1 or (v_cnt <= v_max and v_tot <= v_maxc);
    v_victim := null;
    select k into v_victim from generate_series(1, n) k
     where v_fault[k] is null and k > (select min(k2) from generate_series(1, n) k2 where v_fault[k2] is null)
     order by security.cdesc_sentence_substance_v1(v_s->(k - 1)->>'text', v_s->(k - 1)->>'quote'), k desc limit 1;
    exit when v_victim is null;
    v_fault[v_victim] := 'over_limit';
    for i in v_victim + 1 .. n loop
      exit when v_fault[i] is not null or not security.cdesc_points_back_v1(v_s->(i - 1)->>'text');
      v_fault[i] := 'depends_on_dropped_sentence';
    end loop;
  end loop;
  -- 2. every sentence that passes and was not set aside for size is kept, in its original order. No sentence is ever cut inside: a reading that cannot be brought within the limits by whole sentences stays held
$n1$]);

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
end $post$;
