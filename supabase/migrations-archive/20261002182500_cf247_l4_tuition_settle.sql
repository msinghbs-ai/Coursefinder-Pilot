-- CF-247 (Decision 224, 2 Oct 2026). Platform Admin, 15:35, with an RMIT review and RMIT's page (International view:
-- "AU$16,250 (2027 total indicative)"): "Review all other stuck in layer 4, tuition fees ... review for international
-- students rather getting confused on default page that open domestic students."
-- Found: of about 970 waiting tuition reviews, most asked a person about a figure that is not the international annual
-- tuition: a domestic-view price, a VET Student Loan cap (the RMIT review: A$12,858), a bursary or scholarship, health
-- cover, a salary, a deposit limit, a whole-course total or a per-session fee. The AI check had been right to refuse them.
-- Reader v0.5.6 reads each page's international view and leaves those figures out. This settles the reviews against it:
--   1. an older waiting tuition review for a course that has a newer one is superseded by the newer one;
--   2. when the page, re-read by v0.5.6 or later, gives an international fee different from the one asked about, the
--      review is superseded with both amounts kept, and the page's international fee goes to the AI check again;
--   3. when that page shows no international fee of any kind, the review is superseded with that reason;
--   4. when the page gives the same amount, or shows international fees that are not a yearly fee (a per-session fee and
--      a course total, as at the University of Wollongong), the review stays for a person.
-- A review a person opened in the last 30 minutes is left alone. Nothing in the catalogue changes; reviews are kept.
-- It runs now and every 10 minutes while re-extraction reaches the remaining pages (job layer4-tuition-settle).
create or replace function security.layer4_tuition_settle_v1()
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare n_dup int := 0; n_diff int := 0; n_none int := 0;
begin
  with d as (
    select r.id, row_number() over (partition by r.entity_id order by r.created_at desc) rn
      from pipeline.layer4_review_items r
     where r.status = 'pending' and r.field_code = 'provider_current_tuition_validation'
       and coalesce(r.claimed_at, '-infinity') < now() - interval '30 minutes')
  update pipeline.layer4_review_items r set status = 'superseded', decided_at = now(),
         layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
           'reason', 'A newer review for the same course is waiting.', 'at', now(), 'ref', 'Decision 224'))
    from d where d.id = r.id and d.rn > 1;
  get diagnostics n_dup = row_count;

  with s as (
    select r.id, r.entity_id, (r.layer2_state->'candidate_context'->'provider_current_tuition'->>'amount')::numeric asked,
           (security.coverage_tuition_target_v1(g.candidates->'fee')->>'amount')::numeric tgt,
           g.candidates->'fee'->'candidates' @> '[{"international": true}]'::jsonb intl_any
      from pipeline.layer4_review_items r
      join pipeline.coverage_course_pages g on g.course_id = r.entity_id and g.read_status = 'read'
     where r.status = 'pending' and r.field_code = 'provider_current_tuition_validation'
       and coalesce(r.claimed_at, '-infinity') < now() - interval '30 minutes'
       and g.candidates->>'extractor' >= 'coverage-sweep-v0.5.6'
       and r.layer2_state->'candidate_context'->'provider_current_tuition'->>'amount' is not null),
  u as (
    update pipeline.layer4_review_items r set status = 'superseded', decided_at = now(),
           layer3_state = coalesce(r.layer3_state, '{}'::jsonb) || jsonb_build_object('superseded', jsonb_build_object(
             'reason', case when s.tgt is null
                         then 'The amount asked about is not an international annual tuition fee, and the page''s international view shows none.'
                         else 'The amount asked about is not the page''s international annual tuition fee; the international fee on the page went to the AI check.' end,
             'asked_amount', s.asked, 'page_international_fee', s.tgt, 'at', now(), 'ref', 'Decision 224'))
      from s where s.id = r.id and s.tgt is distinct from s.asked and (s.tgt is not null or not s.intl_any)
    returning r.entity_id, s.tgt)
  , h as (
    update pipeline.coverage_course_pages g set l3_handoff_at = null, l3_work_item_id = null
      from u where u.entity_id = g.course_id and u.tgt is not null
    returning g.course_id)
  select count(*) filter (where tgt is not null), count(*) filter (where tgt is null) into n_diff, n_none from u;

  return jsonb_build_object('duplicates', n_dup, 'resent_with_international_fee', n_diff, 'no_international_fee', n_none, 'at', now());
end $f$;
revoke all on function security.layer4_tuition_settle_v1() from public, anon, authenticated;

select security.layer4_tuition_settle_v1();
select cron.schedule('layer4-tuition-settle', '3-59/10 * * * *', $c$select security.layer4_tuition_settle_v1()$c$);
insert into pipeline.automation_catalogue(jobname, area, sort, label, description, control_rank, batch_editable) values
  ('layer4-tuition-settle', 'Admission', 60, 'Settle tuition reviews against the international view',
   'Closes a waiting tuition review when the course page, re-read, shows that the amount asked about is not the international annual fee (sending the page''s international fee to the AI check), or a newer review for the course is waiting. Reviews whose amount is the page''s international fee stay for a person.', 5, false)
on conflict (jobname) do nothing;
