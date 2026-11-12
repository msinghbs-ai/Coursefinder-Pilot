-- HELD forward recovery for migration 20261113280000_cf247_cdesc_recovery_throughput.sql. Not applied by deploy.
-- Puts security.cdesc_subset_plan_v1 and security.cdesc_subset_recover_v1 back to the bodies that migration edited (reverse edits, md5-guarded)
-- and the job course-description-machine back to every ten minutes. The index, security.cdesc_points_back_v1 and the data marks stay
-- (harmless; the function and index are removed by paste file if wanted). Run twice: the second run reports "already applied".
-- Replaces: the two bodies named above. Retires: nothing.

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

select pg_temp.edit_all('security.cdesc_subset_plan_v1(uuid,uuid,jsonb)', 'ae9aa0765db9a4f2ede501041a774204', '1350a9c8f46331a5469cabbd60acf660',
  array[$o0$if security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then$o0$,
        $o1$  -- 1b. a passing sentence that opens by pointing back to the sentence before it, which is set aside, is set aside with it (it would be published as a fragment of it).
  --     In order, so a chain is followed. Only sentences are removed: what is kept is unchanged and goes through the same full check below
  for i in 2 .. n loop
    if v_fault[i] is null and v_fault[i - 1] is not null and security.cdesc_points_back_v1(v_s->(i - 1)->>'text') then v_fault[i] := 'depends_on_dropped_sentence'; end if;
  end loop;
  -- 2. every sentence that passes is kept, in its original order.$o1$,
        $o2$    f := security.cdesc_sentence_fault_v1(security.cdesc_known_strip_v1(s->>'text', v_title, v_prov), s->>'quote',$o2$,
        $o3$  -- 1. the sentences that fail a per-sentence test or the machine wording policy. The course's own title and provider are left out of a sentence's tests, exactly as the check does
  --    (security.course_description_check_with_v1), so a sentence the check would refuse is set aside here and not carried into the remainder
  select c.canonical_title, coalesce(p.display_name, p.canonical_name) into v_title, v_prov from catalogue.courses c left join catalogue.providers p on p.id = c.provider_id where c.id = p_course;
$o3$,
        $o4$v_chk jsonb; v_orig text; v_page text; v_title text; v_prov text;
begin$o4$],
  array[$n0$if btrim(coalesce(v_s->(i - 1)->>'text', '')) ~* '^\s*(((this|these|that|those|it|its|they|their|them|he|she|his|her|such|both|also|however|therefore|thus|moreover|furthermore|additionally|in addition|as a result|another|alternatively|further|and|which|here|each|but|or|so|yet|then|instead|otherwise|similarly|likewise|meanwhile|for example|for instance|in particular|the (program|programme|course|degree|qualification|major))\M)|["''“‘(\[«])' then$n0$,
        $n1$  -- 2. every sentence that passes is kept, in its original order.$n1$,
        $n2$    f := security.cdesc_sentence_fault_v1(s->>'text', s->>'quote',$n2$,
        $n3$  -- 1. the sentences that fail a per-sentence test or the machine wording policy
$n3$,
        $n4$v_chk jsonb; v_orig text; v_page text;
begin$n4$]);
select pg_temp.edit_all('security.cdesc_subset_recover_v1()', '1652bacc1954b2a9d51ef28d6b411f35', '5f73026bc5ed0350107a97a0953f7588',
  array[$o0$v_dl := least(v_t0 + make_interval(secs => 45), statement_timestamp() + make_interval(secs => 60));$o0$,
        $o1$-- fixed: the whole subset step ends 45 s after it began or 60 s after the job began, whichever comes first (13 Nov 2026: the job now runs every two minutes and a recovered reading is admitted inside this step, so the step has the larger share; the settle after it still stops 85 s into the job, inside the 120 s statement time-out)$o1$,
        $o2$(sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence|copied_sentence|generic_phrase):'$o2$],
  array[$n0$v_dl := least(v_t0 + make_interval(secs => 20), statement_timestamp() + make_interval(secs => 45));$n0$,
        $n1$-- fixed: the whole subset step ends 20 s after it began or 45 s after the job began, whichever comes first, so the replay, the settle and the follow-up that come after it keep their share of the 120 s statement time-out of the job (live runs average 31 s, the longest was 74 s)$n1$,
        $n2$(sentence_count|length|unsupported_claim|quote_not_on_page|unsupported_sentence|unsupported_marketing|incomplete_sentence):'$n2$]);

do $sched$
declare v_id bigint;
begin
  if to_regnamespace('cron') is not null then
    select jobid into v_id from cron.job where jobname = 'course-description-machine';
    if v_id is not null then
      if exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'cron' and p.proname = 'alter_job') then
        perform cron.alter_job(v_id, schedule := '4,14,24,34,44,54 * * * *');
      else
        update cron.job set schedule = '4,14,24,34,44,54 * * * *' where jobid = v_id;
      end if;
    end if;
  end if;
  update pipeline.automation_catalogue
     set description = replace(description, 'Every 2 minutes (not from :35 to :43 or from :45 to :49)', 'Every 10 minutes (not at :35 to :42 or :47 to :48)')
   where jobname = 'course-description-machine';
end $sched$;
