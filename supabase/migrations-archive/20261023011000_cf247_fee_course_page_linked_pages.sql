-- CF-247 (23 Oct 2026, first runs of v2.15.324). 5 course pages read by the AI fee reader failed to record: when the AI named other
-- fee pages linked from a course page, they were added with linked_from set to the course page's queue key (the page copy's evidence
-- id, not a fee page), which the foreign key to pipeline.provider_fact_sources refused, so the whole reading was lost. A fee page
-- found from a course page is now added with no linked_from; the 5 course pages are read again.
-- Replaces: nothing (public.svc_fee_ai_record edited in place, md5-guarded)
-- Retires: nothing
do $do$
declare v_def text := pg_get_functiondef('public.svc_fee_ai_record(uuid,jsonb,numeric,text)'::regprocedure);
  v_old text := $o$'linked from a fee page (AI fee reader)', 6, 'search', 'found', q.fact_source_id$o$;
  v_new text := $n$case when q.course_id is null then 'linked from a fee page (AI fee reader)' else 'linked from a course page (AI fee reader)' end, 6, 'search', 'found', case when q.course_id is null then q.fact_source_id end$n$;
begin
  if md5(v_def) <> '9efc86519854a15dbdd8a9707ac0462c' then raise exception 'public.svc_fee_ai_record is not the expected version (md5 %)', md5(v_def); end if;
  if (length(v_def) - length(replace(v_def, v_old, ''))) / length(v_old) <> 1 then raise exception 'fee record: expected one linked page insert'; end if;
  execute replace(v_def, v_old, v_new);
end $do$;

update pipeline.fee_reader_queue set state = 'queued', attempts = 0, error = null, leased_until = null
 where course_id is not null and error like '%provider_fact_sources_linked_from_fkey%' and state in ('failed', 'queued');

select 'course page readings with linked fee pages recorded' ok;
