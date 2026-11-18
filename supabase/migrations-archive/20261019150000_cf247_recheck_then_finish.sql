-- CF-247 (19 Oct 2026). Platform Admin 22:47, choice "AI re-check, then finish" (follow-up to 20261019130000).
-- 1 Then finish: when a university waiting at Admit scholarships has no held page left without a re-check, its onboarding is done (the
--   held pages stay in Layer 4 > AI could not decide with their recommendation for a person). Run by job scholarship-recheck.
-- 2 The 36 items re-checked by worker v0.33.0 as "not settled" are re-checked once more by v0.33.1, which reads a sentence that is on the
--   page but does not name international students as "international students not mentioned".
-- Replaces: security.scholarship_recheck_fire_v1() (finish step added)
-- Retires: nothing
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

CREATE OR REPLACE FUNCTION security.scholarship_recheck_fire_v1()
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  -- then finish: a university at Admit scholarships whose held pages all have a re-check is done
  update pipeline.provider_onboarding ob set status = 'done', finished_at = now(), job_id = null,
         result = ob.result || jsonb_build_object('scholarship_admit', jsonb_build_object('rechecked', (select count(*) from pipeline.scholarship_ai_reviews r where r.provider_id = ob.provider_id and r.status = 'pending' and r.recheck->>'state' = 'done'))),
         note = format('Onboarding complete after the AI re-check: %s held scholarship pages wait for a person with a recommendation (Layer 4 › AI could not decide).',
                       (select count(*) from pipeline.scholarship_ai_reviews r where r.provider_id = ob.provider_id and r.status = 'pending')),
         updated_at = now()
   where ob.status = 'scholarships' and ob.result->>'phase' = 'scholarship_admit'
     and exists (select 1 from pipeline.scholarship_ai_reviews r where r.provider_id = ob.provider_id and r.recheck is not null)
     and not exists (select 1 from pipeline.scholarship_ai_reviews r where r.provider_id = ob.provider_id and r.status = 'pending' and coalesce(r.recheck->>'state', 'none') <> 'done')
     and ob.id = (select o2.id from pipeline.provider_onboarding o2 where o2.provider_id = ob.provider_id order by o2.created_at desc limit 1);
  if not security.ai_use_allowed_v1('scholarship_ai') then return 0; end if;
  if not exists (select 1 from pipeline.scholarship_ai_reviews r where r.status = 'pending'
                  and (r.recheck->>'state' = 'queued' or (r.recheck->>'state' = 'leased' and (r.recheck->>'leased_until')::timestamptz < now()))) then return 0; end if;
  perform pipeline.svc_pilot_submit_nonce('coverage-sweep', jsonb_build_object('mode', 'scholarship_recheck', 'limit', security.pipeline_num_v1('batch.scholarship_recheck', 12)::int));
  return 1;
end $function$;
revoke execute on function security.scholarship_recheck_fire_v1() from public, anon, authenticated;

update pipeline.scholarship_ai_reviews set recheck = jsonb_build_object('state', 'queued', 'queued_at', now(), 'scope', recheck->>'scope', 'again', 'v0.33.1')
 where status = 'pending' and recheck->>'state' = 'done' and recheck->>'recommendation' = 'unsettled' and (recheck->>'at')::timestamptz < '2026-10-19 12:27:00+00';
