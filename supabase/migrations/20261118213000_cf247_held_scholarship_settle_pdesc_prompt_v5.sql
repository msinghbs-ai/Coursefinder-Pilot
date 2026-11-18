-- CF-247 S2-BOOST-Providers (Platform Admin 18 Nov 2026 17:52: rule settlement of held scholarships on a clear AI re-check recommendation;
-- the held university descriptions re-read with the provider named in the first sentence). No table, column, function or job is added:
-- the one function changed is this lane's own rule function, by CREATE OR REPLACE.
-- What was read live (18:00 to 18:20 AEDT, SELECT only):
--   * 89 held scholarship pages: 78 have a re-check. 9 say "international, check and publish" and 6 "not for international students"; in all
--     15 the worker found the audience sentence (and, for the 9, the value sentence) on the stored page, and every page is on the provider's
--     own host. In 5 of the 15 the re-check and the first reading disagree about who may apply (3 of the 9, 2 of the 6), and one address is
--     a staging path. The existing decision security.scholarship_ai_review_apply_v1 admits or refuses a held page; an admitted scholarship
--     is published only by the hourly publish checks, as for a person's decision.
--   * 83 university descriptions wait in Layer 4, each with one reading in state proposed: 53 were written by the worker's built-in prompt
--     (v1, v2) and 30 by prompt versions 3 and 4. The sentences the wording check leaves out most often use accredited (34), excellence (17)
--     and innovative (10); a reading then keeps fewer than pdesc.min_sentences sentences or loses the sentence that names the provider.
-- 1 Rule l4-held-sch-settle-v1, inside security.scholarship_recheck_queue_rule_v1 (job scholarship-recheck-queue, hourly at minute 9), when
--   scholarship.held_settle_rule_on is 1, through the existing decision under the system automation account:
--     admit  - "international, check and publish", audience and value sentences both found on the page, the audience sentence says
--              international, the first reading also says international students may apply, the page is on the provider's own host over
--              https and its address has no word of scholarship.settle_refused_path_words;
--     refuse - "not for international students", the audience sentence found on the page, and the first reading does not say international
--              students may apply.
--   Everything else stays held for a person: audience not stated, value unclear, not settled, and every item whose two readings disagree.
-- 2 Provider description prompt version 5 (pipeline.provider_description_prompts; version 4 retired): two to three sentences, the first
--   beginning with the provider's full name and saying what kind of institution it is, and the words the automatic wording check refuses
--   most often left out. The validation, the machine gate, the word lists and the admission are not changed.
-- 3 The waiting university descriptions are sent back to the reader once: each pending Layer 4 item is closed as superseded (its reading
--   becomes superseded by the existing trigger; nothing is deleted) and a new read is queued for the provider. The reader reads the
--   provider's official page as it does any read, within its own limits, and the unchanged machine rule admits or holds the result.
-- G1: no new job. G2: the switch and the word list are settings. G3: no consumer API object is changed.
-- Replaces: security.scholarship_recheck_queue_rule_v1 (it queued the re-check and settled nothing)
-- Retires: nothing

set local lock_timeout = '5s';

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, reason, section, used_by) values
 ('pipeline', 'scholarship.held_settle_rule_on', 'Held scholarships: settle on a clear re-check by rule',
  '1: every hour, rule l4-held-sch-settle-v1 admits a held scholarship page whose AI re-check and first reading both say international students may apply, with the audience and value sentences found on the provider''s own page, and refuses one whose re-check found a domestic-only sentence that the first reading does not contradict. Every other held page waits for a person. 0: only a person decides.',
  'number', '1'::jsonb, 0, 1, 'switch', 330, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:52 item 1', 'Scholarships', 'security.scholarship_recheck_queue_rule_v1, job scholarship-recheck-queue'),
 ('pipeline', 'scholarship.settle_refused_path_words', 'Held scholarships: page address words the rule never admits',
  'A held scholarship page whose address has one of these words as a part is never admitted by rule l4-held-sch-settle-v1; it waits for a person.',
  'list', '["staging", "test", "preview", "draft", "archive", "archived"]'::jsonb, null, null, 'words', 331, 'CF-247 S2-BOOST-Providers, Platform Admin 18 Nov 2026 17:52 item 1', 'Scholarships', 'security.scholarship_recheck_queue_rule_v1')
on conflict (toolset_key, key) do nothing;

-- 1 ---------------------------------------------------------------------------------------------------------- l4-held-sch-settle-v1
do $g$
begin
  if (select md5(p.prosrc) from pg_proc p where p.oid = 'security.scholarship_recheck_queue_rule_v1(integer)'::regprocedure) <> '613efb697381219f1ab49d194559080f'
     and (select position('l4-held-sch-settle-v1' in p.prosrc) from pg_proc p where p.oid = 'security.scholarship_recheck_queue_rule_v1(integer)'::regprocedure) = 0 then
    raise exception 'security.scholarship_recheck_queue_rule_v1 is not the text of 20261118203000; nothing applied';
  end if;
end $g$;

create or replace function security.scholarship_recheck_queue_rule_v1(p_limit integer)
returns jsonb language plpgsql security definer set search_path to '' as $function$
declare v_lim int := least(greatest(coalesce(p_limit, 0), 0), 1000);  -- fixed: upper bound of the setting's range
        v_sys uuid := 'c0ffee00-0000-4000-8000-000000000150';  -- fixed: the system automation account that records rule decisions (Decision 263)
        v_n int := 0; v_no_copy int; w record; v_res jsonb; v_admit int := 0; v_refuse int := 0; v_fail int := 0; v_held int := 0;
begin
  if v_lim = 0 then return jsonb_build_object('ok', false, 'reason', 'off'); end if;
  perform pg_advisory_xact_lock(hashtext('cf247:held_sch_recheck_rule'));  -- fixed: one run at a time
  -- rule l4-held-sch-recheck-v1: queue the AI re-check for held pages with a stored copy and no re-check
  if security.pipeline_num_v1('scholarship.held_recheck_rule_on', 0) >= 1 then
    with pick as (
      select r.id from pipeline.scholarship_ai_reviews r
       where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is not null
       order by r.created_at, r.id limit v_lim for update skip locked),
    upd as (
      update pipeline.scholarship_ai_reviews r
         set recheck = jsonb_build_object('state', 'queued', 'queued_at', now(), 'scope', 'rule l4-held-sch-recheck-v1')
        from pick where r.id = pick.id returning r.id)
    select count(*) into v_n from upd;
  end if;
  select count(*) into v_no_copy from pipeline.scholarship_ai_reviews r
   where r.status = 'pending' and r.recheck is null and nullif(btrim(coalesce(r.storage_path, '')), '') is null;
  -- rule l4-held-sch-settle-v1: settle a held page on a clear re-check that the first reading does not contradict
  if security.pipeline_num_v1('scholarship.held_settle_rule_on', 0) >= 1 then
    for w in
      select r.id, r.url, r.recheck, e.id extraction_id,
             case
               when r.recheck->>'recommendation' = 'international_check_and_publish'
                    and r.recheck->>'audience_proven' = 'true' and r.recheck->>'value_proven' = 'true'
                    and r.recheck->>'audience' in ('international', 'both') and e.answer->>'audience' in ('international', 'both')
                    and nullif(btrim(coalesce(r.recheck->>'audience_quote', '')), '') is not null and nullif(btrim(coalesce(r.recheck->>'value_quote', '')), '') is not null
                    and r.recheck->>'audience_quote' ~* '\minternational\M'
                    and r.url ~* '^https://' and security.provider_page_host_v1(r.provider_id, r.url) = 'own'
                    and not exists (select 1 from unnest(security.pipeline_list_v1('scholarship.settle_refused_path_words', '[]'::jsonb)) x
                                     where lower(r.url) ~ ('[/._-]' || regexp_replace(lower(x), '[^a-z0-9]', '', 'g') || '([/._?#-]|$)'))
                    and e.id is not null and r.scholarship_id is null
                    and not exists (select 1 from pipeline.scholarship_page_candidates c where c.id = r.candidate_id and c.admitted_scholarship_id is not null)
                 then 'admit'
               when r.recheck->>'recommendation' = 'not_for_international'
                    and r.recheck->>'audience_proven' = 'true' and r.recheck->>'audience' = 'domestic'
                    and nullif(btrim(coalesce(r.recheck->>'audience_quote', '')), '') is not null
                    and coalesce(e.answer->>'audience', '') not in ('international', 'both')
                 then 'refuse'
               else 'hold' end verdict
        from pipeline.scholarship_ai_reviews r
        left join lateral (select x.id, x.answer from pipeline.scholarship_ai_extractions x
                            where x.id = any (r.extraction_ids) and x.answer is not null
                            order by coalesce((x.answer->>'is_scholarship')::boolean, false) desc, x.at desc limit 1) e on true
       where r.status = 'pending' and r.recheck->>'state' = 'done'
         and r.recheck->>'recommendation' in ('international_check_and_publish', 'not_for_international')
       order by r.id limit v_lim
    loop
      if w.verdict = 'hold' then v_held := v_held + 1; continue; end if;
      begin
        v_res := security.scholarship_ai_review_apply_v1(w.id, w.verdict, w.extraction_id,
          left(format('[rule l4-held-sch-settle-v1] %s Audience sentence on the page: "%s"%s Approved by Platform Admin 18 Nov 2026 17:52',
            case w.verdict when 'admit' then 'The AI re-check and the first reading both say international students may apply, and the value is stated; the page is on the provider''s own host.'
                           else 'The AI re-check found the page is for domestic students only, and the first reading does not say international students may apply.' end,
            left(w.recheck->>'audience_quote', 300),
            case w.verdict when 'admit' then format(' Value sentence: "%s".', left(w.recheck->>'value_quote', 300)) else '.' end), 1500), v_sys);
        if w.verdict = 'admit' then
          -- the audit row of the decision says a rule decided, not a person
          update pipeline.scholarship_ai_extractions x
             set checks = coalesce(x.checks, '{}'::jsonb) || jsonb_build_object('by_person', false, 'by_rule', 'l4-held-sch-settle-v1')
           where x.id = (select (r.decision->>'extraction')::bigint from pipeline.scholarship_ai_reviews r where r.id = w.id) and x.run_kind = 'review';
          v_admit := v_admit + 1;
        else v_refuse := v_refuse + 1;
        end if;
      exception when others then v_fail := v_fail + 1;
      end;
    end loop;
  end if;
  if v_n > 0 or v_admit > 0 or v_refuse > 0 or v_fail > 0 then
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('layer4', 'rule_execute', case when v_admit + v_refuse + v_fail > 0 then 'l4-held-sch-settle-v1' else 'l4-held-sch-recheck-v1' end,
            jsonb_build_object('queued', v_n, 'held_without_stored_copy', v_no_copy, 'admitted', v_admit, 'refused', v_refuse, 'failed', v_fail, 'left_for_a_person', v_held), v_sys);
  end if;
  return jsonb_build_object('ok', true, 'queued', v_n, 'held_without_stored_copy', v_no_copy, 'admitted', v_admit, 'refused', v_refuse, 'failed', v_fail,
    'left_for_a_person', v_held, 'pending', (select count(*) from pipeline.scholarship_ai_reviews where status = 'pending'));
end $function$;
revoke all on function security.scholarship_recheck_queue_rule_v1(integer) from public, anon, authenticated;
comment on function security.scholarship_recheck_queue_rule_v1(integer) is 'CF-247 rules l4-held-sch-recheck-v1 and l4-held-sch-settle-v1 (Platform Admin 18 Nov 2026 17:03 and 17:52): queues the existing AI re-check for held scholarship pages with a stored copy, and settles a held page through the existing decision when the re-check is clear and the first reading does not contradict it; every other held page waits for a person.';

update pipeline.automation_catalogue
   set label = 'Held scholarships: queue the AI re-check and settle clear results by rule',
       description = 'Every hour at minute 9. When setting scholarship.held_recheck_rule_on is 1, rule l4-held-sch-recheck-v1 queues up to batch.scholarship_recheck_queue held scholarship pages that have a stored copy and no re-check; job scholarship-recheck reads them. When scholarship.held_settle_rule_on is 1, rule l4-held-sch-settle-v1 admits a held page whose re-check and first reading both say international students may apply (sentences found on the provider''s own page) and refuses one found to be for domestic students only; every other held page waits for a person. Settings > Pipeline settings > Scholarships.'
 where jobname = 'scholarship-recheck-queue';

-- 2 ---------------------------------------------------------------------------------------------------------------- prompt version 5
do $p$
declare v4 text; v5 text;
  l1 constant text := 'Write 3 to 4 sentences (about 60 to 110 words)';
  l2 constant text := 'Begin the first sentence with the provider''s full name as given.';
  l3 constant text := '- Do not mention fees, scholarships, visas or entry requirements.';
begin
  if exists (select 1 from pipeline.provider_description_prompts where version = 5) then raise notice 'prompt version 5 exists: not added again'; return; end if;
  select system_prompt into v4 from pipeline.provider_description_prompts where version = 4 and status = 'active';
  if v4 is null then raise exception 'prompt version 4 is not active (the Platform Admin saved another); version 5 not added and nothing applied'; end if;
  if position(l1 in v4) = 0 or position(l2 in v4) = 0 or position(l3 in v4) = 0 then raise exception 'prompt version 4 does not hold the lines version 5 rewrites'; end if;
  v5 := replace(v4, l1, 'Write 2 to 3 sentences (about 40 to 90 words)');
  v5 := replace(v5, l2, 'The first sentence must begin with the provider''s full name exactly as given and say what kind of institution it is; never begin it with "It", "The college", "The university", "The school" or a short form of the name.');
  v5 := replace(v5, l3, l3 || E'\n- Never use these words, and leave out a fact that cannot be said without one: accredited, accreditation, excellence, excellent, innovative, leading, vibrant, top, best, premier, renowned, exceptional, cutting-edge, guaranteed, funding, loan, bursary, tuition.');
  update pipeline.provider_description_prompts set status = 'retired' where version = 4;
  insert into pipeline.provider_description_prompts(version, system_prompt, status, reason, activated_at)
  values (5, v5, 'active', 'CF-247 S2-BOOST-Providers 20261118213000 (Platform Admin 18 Nov 2026 17:52): two to three sentences, the provider named at the start of the first, and the words the wording check refuses most often left out (83 held readings: accredited 34, excellence 17, innovative 10)', now());
end $p$;

-- 3 ------------------------------------------------------------------- the waiting descriptions go back to the reader once (pdesc-reread-p5)
create temp table cf_reread on commit drop as
  select i.id item_id, i.entity_id provider_id
    from pipeline.layer4_review_items i
    join catalogue.providers p on p.id = i.entity_id
   where i.status = 'pending' and i.entity_type = 'provider' and i.field_code = 'provider_description'
     and p.lifecycle_status = 'active'
     and security.pipeline_num_v1('pdesc.enabled', 0) >= 1 and security.pipeline_num_v1('pdesc.prompt_on', 0) >= 1
     and not exists (select 1 from pipeline.manual_locks l where l.entity = 'provider' and l.entity_id = p.id and l.field in ('description', 'p_description', 'all'))
     and exists (select 1 from pipeline.provider_description_reads r where r.review_item_id = i.id and r.state = 'proposed'
                    and r.prompt_version is distinct from 'provider-description-p5');

update pipeline.layer4_review_items i
   set status = 'superseded', decided_at = now(),
       layer2_state = coalesce(i.layer2_state, '{}'::jsonb) || jsonb_build_object('superseded_by', 'pdesc-reread-p5', 'superseded_at', now(),
                        'superseded_reason', 'Sent back to the reader with prompt version 5 (Platform Admin 18 Nov 2026 17:52); the reading and its sentences are kept')
  from cf_reread c where i.id = c.item_id and i.status = 'pending';

insert into pipeline.provider_description_reads(provider_id, state, next_try_at, reason, checks)
select distinct c.provider_id, 'queued', now(), 'Re-read with prompt version 5 (rule pdesc-reread-p5, Platform Admin 18 Nov 2026 17:52)',
       jsonb_build_object('reread', jsonb_build_object('rule', 'pdesc-reread-p5', 'review_item_id', c.item_id, 'at', now()))
  from cf_reread c
 where not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = c.provider_id and r.state in ('queued', 'reading', 'proposed'));

insert into pipeline.admin_control_events(area, action, target, detail, actor)
select 'layer4', 'rule_execute', 'pdesc-reread-p5',
       jsonb_build_object('items_superseded', (select count(*) from cf_reread),
                          'reads_queued', (select count(*) from pipeline.provider_description_reads r where r.checks->'reread'->>'rule' = 'pdesc-reread-p5')),
       'c0ffee00-0000-4000-8000-000000000150'::uuid;

-- first run and checks ---------------------------------------------------------------------------------------------------------------
create temp table cf_run on commit drop as
  select security.scholarship_recheck_queue_rule_v1(security.pipeline_num_v1('batch.scholarship_recheck_queue', 120)::int) sch;

do $c$
declare s jsonb := (select sch from cf_run);
begin
  if exists (select 1 from pipeline.scholarship_ai_reviews r where r.note like '[rule l4-held-sch-settle-v1]%' and r.status = 'admitted'
                and not (r.recheck->>'recommendation' = 'international_check_and_publish' and r.recheck->>'audience_proven' = 'true' and r.recheck->>'value_proven' = 'true')) then
    raise exception 'post-check: the rule admitted a page without a clear re-check';
  end if;
  if exists (select 1 from pipeline.scholarship_ai_reviews r where r.note like '[rule l4-held-sch-settle-v1]%'
                and r.recheck->>'recommendation' not in ('international_check_and_publish', 'not_for_international')) then
    raise exception 'post-check: the rule settled a page whose re-check is not clear';
  end if;
  if exists (select 1 from pipeline.scholarship_ai_reviews r where r.note like '[rule l4-held-sch-settle-v1]%' and r.status = 'refused' and r.recheck->>'audience' <> 'domestic') then
    raise exception 'post-check: the rule refused a page the re-check did not find to be domestic only';
  end if;
  if (select count(*) from pipeline.provider_description_prompts where status = 'active') <> 1
     or (select position('Write 2 to 3 sentences' in system_prompt) from pipeline.provider_description_prompts where status = 'active') = 0 then
    raise exception 'post-check: prompt version 5 is not the one active prompt';
  end if;
  if exists (select 1 from cf_reread c join pipeline.layer4_review_items i on i.id = c.item_id where i.status <> 'superseded')
     or exists (select 1 from cf_reread c where not exists (select 1 from pipeline.provider_description_reads r where r.provider_id = c.provider_id and r.state in ('queued', 'reading'))) then
    raise exception 'post-check: a description sent back has no queued read or is still pending';
  end if;
  if exists (select 1 from cf_reread c join pipeline.provider_description_reads r on r.review_item_id = c.item_id where r.state = 'proposed') then
    raise exception 'post-check: a superseded item still has a proposed reading';
  end if;
  raise notice 'Rule l4-held-sch-settle-v1 first run: %', s;
  raise notice 'pdesc-reread-p5: % items sent back', (select count(*) from cf_reread);
end $c$;
