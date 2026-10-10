-- CF-247 complete coverage, ongoing: change check for the provider documents that are read as a whole (the
-- international fee schedules and the UQ English tables). Monthly all year, weekly from October to December (when
-- next-year fee schedules are published). The worker fetches each registered document and records its SHA-256; when it
-- differs from the last check (or from the file applied as evidence), the document is marked 'changed' for review.
-- Nothing is applied automatically - a changed document is re-run as a dry run and applied by a person (Decision 162).
create table if not exists pipeline.provider_document_checks(
  doc_key text not null, url text not null, sha256 text, http_status int, checked_at timestamptz not null default now(),
  changed boolean not null default false, applied_sha256 text, note text, primary key(doc_key, checked_at));
alter table pipeline.provider_document_checks enable row level security;
revoke all on pipeline.provider_document_checks from public, anon, authenticated;

create or replace function public.svc_provider_document_check_record(p_doc_key text, p_url text, p_sha256 text, p_http_status int, p_note text)
returns jsonb language plpgsql security definer set search_path to 'pg_catalog','pipeline' as $f$
declare v_prev text; v_applied text; v_changed boolean;
begin
  if current_user<>'postgres' and coalesce(auth.role(),'')<>'service_role' then raise exception 'service_role required'; end if;
  select sha256 into v_prev from pipeline.provider_document_checks where doc_key=p_doc_key and sha256 is not null order by checked_at desc limit 1;
  select e.content_hash into v_applied from pipeline.evidence_artifacts e where e.source_url=p_url order by e.captured_at desc nulls last limit 1;
  v_changed:=p_sha256 is not null and ((v_prev is not null and v_prev<>p_sha256) or (v_prev is null and v_applied is not null and v_applied<>p_sha256));
  insert into pipeline.provider_document_checks(doc_key,url,sha256,http_status,changed,applied_sha256,note)
  values (p_doc_key,p_url,p_sha256,p_http_status,v_changed,v_applied,left(p_note,300));
  return jsonb_build_object('changed',v_changed,'previous',v_prev,'applied',v_applied);
end $f$;
revoke all on function public.svc_provider_document_check_record(text,text,text,int,text) from public, anon, authenticated;
grant execute on function public.svc_provider_document_check_record(text,text,text,int,text) to service_role;

select cron.schedule('provider-document-check-monthly','23 21 1 * *',$$select pipeline.svc_pilot_submit_nonce('fee-schedule-etl','{"mode":"check_documents"}'::jsonb)$$);
select cron.schedule('provider-document-check-weekly-q4','23 21 * 10-12 1',$$select pipeline.svc_pilot_submit_nonce('fee-schedule-etl','{"mode":"check_documents"}'::jsonb)$$);
