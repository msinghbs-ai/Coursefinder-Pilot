-- CF-247 F-CDESC (S2-CF directive, Platform Admin 13 Nov 2026 10:25: "restore productive processing immediately ... improve the prompt and reusable
-- validator contracts at their owning layer ... recover existing eligible readings automatically"): the course-description recovery and
-- admission steps are made to keep up, and readings that existing rules can already admit are no longer left waiting.
-- Measured live 13 Nov 2026 10:25-11:00 AEDT (read-only):
--   - security.course_description_machine_check_v1 takes 2.4 to 6.1 s for an item that reaches the text checks: 1.5 s of it compares the text with
--     every decided Layer 4 description by md5(security.cdesc_norm_v1(...)) with no index, 0.4 s twice more over the waiting ones. With 40 s of
--     settling and 12 s of subset recovery every 10 minutes the machine decided 85 items in two hours while 268 an hour arrived.
--   - a 1-in-12 sample of the readings held by a check that cdesc-source-grounded-v1 made (271 of about 3,250): security.cdesc_subset_plan_v1 already
--     returns an admissible remainder for 101 (37 %), oldest held since 11 Nov; 127 (47 %) fail only because a kept sentence points back to a
--     sentence set aside; 13 fail because the plan tests a sentence with the course's title in it while the check leaves the title out.
--   - security.cdesc_subset_recover_v1 never looks at a reading held as copied_sentence or generic_phrase (the two holds the 12 Nov prompt release added).
-- What:
--   1. Index pipeline.layer4_review_items (field_code, md5(security.cdesc_norm_v1(proposed_value->>'description'))): the three exact-text lookups
--      of the machine check use it. security.cdesc_norm_v1 is immutable; its body must not change while this index exists.
--   2. Job course-description-machine runs every two minutes (it ran every ten), still not from :35 to :43 or :45 to :49; catalogue row updated.
--   3. security.cdesc_subset_plan_v1  1350a9c8f46331a5469cabbd60acf660 -> ae9aa0765db9a4f2ede501041a774204
--      - a sentence is tested as the check tests it (course title and provider left out: security.cdesc_known_strip_v1), so plan and check agree;
--      - a passing sentence that opens by pointing back to a sentence set aside is set aside with it instead of failing the whole reading.
--      Only sentences are removed. What is kept is unchanged and still goes through the same full check, the wording policy and the machine rule.
--      Nothing is cut for length or sentence count (unchanged: that decision is the Platform Admin's).
--   4. security.cdesc_subset_recover_v1  5f73026bc5ed0350107a97a0953f7588 -> 1652bacc1954b2a9d51ef28d6b411f35
--      - readings held as copied_sentence or generic_phrase are looked at too (the copied or generic sentence is the one set aside);
--      - the step's time box is 45 s (it was 20 s), ending 60 s into the job (it was 45 s). Both are technical safety values (-- fixed).
--   5. New security.cdesc_points_back_v1(text): the one definition of "opens by pointing back" (the test the plan already had, moved unchanged).
--   6. Data marks, no reading changed: the subset attempt noted on held readings whose attempt ended as depends_on_dropped_sentence,
--      nothing_to_drop or remainder_unsupported_sentence is cleared, so the changed plan looks at them again (the policy stamp covers settings
--      only); and description reads recorded failed by the OpenRouter key-limit refusals after migration 20261113241000 ran are marked reread:.
-- Not changed: the check, the wording policy, the machine rule, every setting, identity and lock rules. No AI call is made by this change.
-- Guards: G1 (catalogue row), G2 (no operational value in code; time boxes marked fixed), G3 (no consumer API object), housekeeping s42.
-- Replaces: security.cdesc_subset_plan_v1(uuid,uuid,jsonb) and security.cdesc_subset_recover_v1() (same names and signatures, by named edits, md5-guarded).
-- Retires: nothing.
-- Reversal: supabase/held/cdesc_recovery_throughput_forward_recovery.sql (reverse edits and the ten-minute schedule; the index and the new function stay until removed by paste file).

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

create or replace function security.cdesc_points_back_v1(p_text text) returns boolean language sql immutable set search_path = '' as $pb$
  -- fixed: a structural test of the grammar (a sentence that opens with a pronoun, a connecting word, "the program" or a quote or bracket), not a tunable limit
  select btrim(coalesce(p_text, '')) ~* '^\s*(((this|these|that|those|it|its|they|their|them|he|she|his|her|such|both|also|however|therefore|thus|moreover|furthermore|additionally|in addition|as a result|another|alternatively|further|and|which|here|each|but|or|so|yet|then|instead|otherwise|similarly|likewise|meanwhile|for example|for instance|in particular|the (program|programme|course|degree|qualification|major))\M)|["''“‘(\[«])'
$pb$;
comment on function security.cdesc_points_back_v1(text) is
  'Course description subset recovery: true when a sentence opens by pointing back to the sentence before it (pronoun, connecting word, "the program", quote or bracket). The one definition used by security.cdesc_subset_plan_v1.';
revoke all on function security.cdesc_points_back_v1(text) from public, anon, authenticated;

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', '1350a9c8f46331a5469cabbd60acf660', 'ae9aa0765db9a4f2ede501041a774204',
  array[$o0$v_chk jsonb; v_orig text; v_page text;
begin$o0$,
        $o1$  -- 1. the sentences that fail a per-sentence test or the machine wording policy
$o1$,
        $o2$    f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote',$o2$,
        $o3$  -- 2. every sentence that passes is kept, in its original order.$o3$,
        $o4$if btrim(coalesce(v_s->(i - 1)->>'text', '')) ~* '^\s*(((this|these|that|those|it|its|they|their|them|he|she|his|her|such|both|also|however|therefore|thus|moreover|furthermore|additionally|in addition|as a result|another|alternatively|further|and|which|here|each|but|or|so|yet|then|instead|otherwise|similarly|likewise|meanwhile|for example|for instance|in particular|the (program|programme|course|degree|qualification|major))\M)|["''“‘(\[«])' then$o4$],
  array[$n0$v_chk jsonb; v_orig text; v_page text; v_title text; v_prov text;
begin$n0$,
        $n1$  -- 1. the sentences that fail a per-sentence test or the machine wording policy. The course's own title and provider are left out of a sentence's tests, exactly as the check does
  --    (security.course_description_check_with_v1), so a sentence the check would refuse is set aside here and not carried into the remainder
  select c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_title, v_prov from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;
$n1$,
        $n2$    f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote',$n2$,
        $n3$  -- 1b. a passing sentence that opens by pointing back to the sentence before it, which is set aside, is set aside with it (it would be published as a fragment of it).
  --     In order, so a chain is followed. Only sentences are removed: what is kept is unchanged and goes through the same full check below
  for i in 2 .. n loop
    if v_fault[i] is null and v_fault[i - 1] is not null and security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then v_fault[i] := 'depends_on_dropped_sentence'; end if;
  end loop;
  -- 2. every sentence that passes is kept, in its original order.$n3$,
        $n4$if security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then$n4$]);
select pg_temp.edit_all('security.cdesc_subset_recover_v1()', '5f73026bc5ed0350107a97a0953f7588', '1652bacc1954b2a9d51ef28d6b411f35',
  array[$o0$(sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence):'$o0$,
        $o1$-- fixed: the whole subset step ends 20 s after it began or 45 s after the job began, whichever comes first, so the replay, the settle and the follow-up that come after it keep their share of the 120 s statement time-out of the job (live runs average 31 s, the longest was 74 s)$o1$,
        $o2$v_dl := least(v_t0 + make_interval(secs => 20), statement_timestamp() + make_interval(secs => 45));$o2$],
  array[$n0$(sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence|copied_sentence|generic_phrase):'$n0$,
        $n1$-- fixed: the whole subset step ends 45 s after it began or 60 s after the job began, whichever comes first (13 Nov 2026: the job now runs every two minutes and a recovered reading is admitted inside this step, so the step has the larger share; the settle after it still stops 85 s into the job, inside the 120 s statement time-out)$n1$,
        $n2$v_dl := least(v_t0 + make_interval(secs => 45), statement_timestamp() + make_interval(secs => 60));$n2$]);

create index if not exists layer4_review_items_field_text_md5_idx
  on pipeline.layer4_review_items (field_code, md5(security.cdesc_norm_v1(proposed_value->>'description')));
comment on index pipeline.layer4_review_items_field_text_md5_idx is
  'Exact-text lookups of security.course_description_machine_check_v1 (same wording decided against, or waiting, for another course). Depends on the immutable security.cdesc_norm_v1.';

do $sched$
declare v_id bigint;
begin
  if to_regnamespace('cron') is not null then
    select jobid into v_id from cron.job where jobname = 'course-description-machine';
    if v_id is not null and (select schedule from cron.job where jobid = v_id) <> '0-34/2,44,50-58/2 * * * *' then
      if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'cron' and p.proname = 'alter_job') then
        perform cron.alter_job(v_id, schedule := '0-34/2,44,50-58/2 * * * *');
      else
        update cron.job set schedule = '0-34/2,44,50-58/2 * * * *' where jobid = v_id; -- a scratch database without pg_cron's functions
      end if;
    end if;
  end if;
  update pipeline.automation_catalogue
     set description = replace(description, 'Every 10 minutes (not at :35 to :42 or :47 to :48)', 'Every 2 minutes (not from :35 to :43 or from :45 to :49)')
   where jobname = 'course-description-machine';
end $sched$;

do $marks$
declare v_a int; v_b int;
begin
  update pipeline.field_enrich_items e set value = e.value - 'subset_attempt'
   where e.field = 'description' and e.state = 'skipped' and e.reason like 'held:%'
     and e.value->'subset_attempt'->>'result' in ('depends_on_dropped_sentence', 'nothing_to_drop', 'remainder_unsupported_sentence');
  get diagnostics v_a = row_count;
  update pipeline.field_enrich_items e
     set state = 'skipped', reason = left('reread: the AI service refused the call (key limit), the course was not read: ' || e.reason, 300), updated_at = now()
   where e.field = 'description' and e.state = 'failed' and e.reason like 'HTTP 403:%Key limit exceeded%'
     and exists (select 1 from catalogue.courses c where c.id = e.course_id and c.lifecycle_status = 'active' and nullif(btrim(c.description), '') is null);
  get diagnostics v_b = row_count;
  -- fixed: stop bounds well above what was measured (about 2,000 attempts to clear; 97 refused reads), so a surprise is not applied
  if v_a > 8000 or v_b > 1000 then raise exception 'marks would touch % attempts and % refused reads, far more than measured: stopped, nothing applied', v_a, v_b; end if;
  raise notice 'subset attempts cleared: %, refused reads marked reread: %', v_a, v_b;
end $marks$;

do $post$
begin
  if not security.cdesc_points_back_v1('It prepares students for work.') or security.cdesc_points_back_v1('Students learn accounting.') then raise exception 'post-check: points back'; end if;
  if to_regnamespace('cron') is not null and exists (select 1 from cron.job where jobname = 'course-description-machine' and schedule <> '0-34/2,44,50-58/2 * * * *') then raise exception 'post-check: schedule'; end if;
  if to_regclass('pipeline.layer4_review_items_field_text_md5_idx') is null then raise exception 'post-check: index'; end if;
end $post$;
