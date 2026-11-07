-- Paste file (Platform Admin decision needed; spends Firecrawl credits). CF-247, 7 Nov 2026, branch cf247-english-refusal-not-a-try.
-- Puts back the English requirement pages that were closed only because a read was refused (error "budget", "credits_refused", "credits_reserve" or "target_list_refused";
-- never a page that was read and gave no content). Run AFTER migration 20261107060000 is applied. Rollback: PASTE-20261107-english-refused-sources-requeue-rollback.sql.
-- Cost: one Firecrawl scrape (about 1 credit) per page read, inside the existing daily share for provider_facts_scrape; the reader takes batch.provider_facts_read (20) a run.
-- Target-list refusals stay refused by the target list unless the provider is on it; they are included only when :include_target_list is true.
-- Only providers that still have no approved or proposed English rule, are not hidden, and have active courses.
-- Nothing is deleted. Each row is marked in parse_summary (requeued_from, requeued_at) so the rollback can find exactly these rows.
begin;
with pick as (
  select f.id, f.parse_summary->>'error' err
    from pipeline.provider_fact_sources f
   where f.kind = 'english_policy' and f.status = 'failed'
     and security.provider_fact_refusal_v1(f.parse_summary->>'error')
     and (f.parse_summary->>'error' <> 'target_list_refused' or false)  -- change false to true to include target-list refusals
     and not exists (select 1 from pipeline.provider_policy_proposals pp where pp.provider_id = f.provider_id and pp.kind = 'english_policy' and pp.status in ('approved', 'proposed'))
     and not exists (select 1 from security.provider_hidden_v1 h where h.provider_id = f.provider_id)
     and exists (select 1 from catalogue.courses c where c.provider_id = f.provider_id and c.lifecycle_status = 'active'))
update pipeline.provider_fact_sources f
   set status = 'found', attempts = 0, updated_at = now(),
       parse_summary = f.parse_summary || jsonb_build_object('requeued_from', pick.err, 'requeued_at', now())
  from pick where f.id = pick.id;
commit;
