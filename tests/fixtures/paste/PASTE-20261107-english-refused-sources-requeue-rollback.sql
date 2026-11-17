-- Rollback of PASTE-20261107-english-refused-sources-requeue.sql: puts back to 'failed' only the rows that paste marked and that have not been read since.
begin;
update pipeline.provider_fact_sources f
   set status = 'failed', attempts = 3, updated_at = now(),
       parse_summary = (f.parse_summary - 'requeued_from' - 'requeued_at') || jsonb_build_object('error', f.parse_summary->>'requeued_from')
 where f.kind = 'english_policy' and f.status = 'found' and f.parse_summary ? 'requeued_from' and f.read_at is null;
commit;
