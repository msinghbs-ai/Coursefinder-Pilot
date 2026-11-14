-- CF-247 R7 (admin docs/audits/studysearch-ingestion-validation-report.md §5.3 R7, §7 recommendations 4 and 8): the page's own status is kept
-- with the stored copy. Worker coverage-sweep v0.94.0 routes every Firecrawl call through the one client in firecrawl.ts (logged to
-- pipeline.firecrawl_calls; a page Firecrawl rendered with a 4xx/5xx status is never accepted as a read) and passes the page's own status
-- (the direct read's HTTP status, or Firecrawl's data.metadata.statusCode) to the record functions it already calls. This change writes that
-- status into pipeline.evidence_artifacts.metadata as page_status (absent when the status is not known), for the Pre-AI Admission Gate's
-- ArtifactManifest:
--   * public.svc_coverage_read_record (course pages)          <- p_http_status
--   * public.svc_provider_description_record (About pages)    <- results[].fetch.http
--   * public.svc_provider_facts_read_record (provider facts)  <- p_http
-- Only new evidence rows carry it; existing rows are not rewritten. Nothing else in these functions changes (no read status, schedule, identity
-- or evidence-reuse rule). Entry-requirement evidence (public.svc_entry_matrix_fetch_record) belongs to the AER workstream (AER v1 frozen,
-- Decision 276) and is left to that workstream; scholarship evidence (public.svc_scholarship_register_evidence) likewise.
-- G2: no operational value is added. G3: no consumer API object is read or changed.
-- Replaces: public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb), public.svc_provider_description_record(jsonb),
--   public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb) (same names and signatures; md5-guarded edits of the live text).
-- Retires: nothing in the database. The worker's inline Firecrawl call sites in coverage-sweep/index.ts are replaced by the client in the same change.

set local lock_timeout = '3s';

create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_old text, p_new text) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  v_c := (length(v_def) - length(replace(v_def, p_old, ''))) / length(p_old);
  if v_c <> 1 then raise exception '%: the edit must apply exactly once (found %)', p_sig, v_c; end if;
  execute replace(v_def, p_old, p_new);
end $f$;

select pg_temp.edit_once('public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb)', 'ebbdc4e45af01c473fd5b681d2237011',
  $o$'fetched_via',p_fetched_via,'gzip',true)$o$,
  $n$'fetched_via',p_fetched_via,'gzip',true) || case when p_http_status is not null then jsonb_build_object('page_status', p_http_status) else '{}'::jsonb end$n$);

select pg_temp.edit_once('public.svc_provider_description_record(jsonb)', '9ac9af4fcf2cb5e31d9cb185179dfc6a',
  $o$'provider_description_read_id', r.id, 'read_via', v_via));$o$,
  $n$'provider_description_read_id', r.id, 'read_via', v_via) || case when jsonb_typeof(x->'fetch'->'http') = 'number' then jsonb_build_object('page_status', (x->'fetch'->>'http')::int) else '{}'::jsonb end);$n$);

select pg_temp.edit_once('public.svc_provider_facts_read_record(uuid,text,integer,text,text,text,jsonb,jsonb)', '88e3d803ad58d31c82311d1e9764ed8e',
  $o$'provider_fact_source_id', f.id));$o$,
  $n$'provider_fact_source_id', f.id) || case when p_http is not null then jsonb_build_object('page_status', p_http) else '{}'::jsonb end);$n$);

comment on function public.svc_coverage_read_record(uuid,text,integer,text,text,text,text,jsonb) is 'Records one course-page read by worker coverage-sweep. A stored copy is registered as evidence with its identity basis, fetch route, text hash and (CF-247 R7, 14 Nov 2026) the page''s own status as metadata.page_status.';
