-- CF-247 (Decision 215, 2 Oct 2026): pages kept by the coverage sweep are gzipped (.html.gz, recorded as text/html);
-- the link indexer read them as plain text and recorded "no links" for 11,676 of them. The indexer now reads them
-- decompressed (edge function evidence-link-index, deployed with this change). Those pages are queued again (state
-- 'error' older than six hours is re-read; nothing is deleted), and each run takes 200 pages (was 60) so the backlog
-- (about 25,000 pages) clears in about a day.

update pipeline.evidence_link_index_state st
   set status = 'error', error = 're-index (Decision 215): gzipped page was not read', indexed_at = now() - interval '7 hours'
  from pipeline.evidence_artifacts e
 where e.id = st.evidence_id and st.status = 'no_links' and e.storage_path ~ '\.gz$';

select cron.schedule('evidence-link-index', '9-59/10 * * * *', $$select pipeline.svc_pilot_submit_nonce('evidence-link-index','{"limit":200}'::jsonb)$$);
