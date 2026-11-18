-- CF-247 F-AER.04 AER source management in the existing workspace (Platform Admin decision D3, 11 Nov 2026, SS-017 / Operating Model v1.12: "attach a URL or PDF;
-- classify it (country table, international qualification, national qualification, undergraduate, postgraduate, course-specific); validate ownership; reuse a stored source;
-- trigger the governed read and review; show outcomes, version, last verification and next retry ... Check the actual deployed navigation and components before implementing.
-- Do not introduce an additional dashboard, unrelated settings panel or duplicate source registry").
-- Guards: G1 (no job added: the existing entry-matrix-read fetches, reads and queues), G2 (no new operational value: the PDF size cap is the existing entry.pdf_max_bytes),
--   G3 (no consumer API object read or changed), Decision 260 (housekeeping), "a passing qualification never switches anything on by itself".
-- Deployed navigation checked (main at b9886666, 11 Nov 2026): Catalogue › Entry requirements has the tab "Sources, reads and holds" (src/AerWorkspace.jsx SourcesView,
--   admin_aer 'sources_list'), opened from a provider with ?provider=; the one source registry is pipeline.entry_matrix_sources (unique provider + address). A source enters it
--   only by the AER search or public.admin_entry_matrix_seed (Platform Admin, no classification, no ownership check, no upload); the discovery outcomes
--   (public.admin_aer_discovery) are on no screen. The fetch step stores each copy in bucket evidence at layer2/<country>/entry-matrix/<provider>/<source>/<sha256>.<kind>.gz
--   and security.entry_matrix_enqueue_v1 queues one read per source and stored copy (no read again of an unchanged copy).
-- What:
--   1. pipeline.aer_source_attachments NEW (beside the registry, not a second one): who attached which source, how (address or uploaded PDF), its classes, the ownership check,
--      whether an existing source or stored copy was reused, and for an upload its file hash and storage path when complete.
--   2. security.aer_source_check_v1 NEW: refuses an address not on the provider's own website host (or a subdomain of it), a directory site, a provider with no website, an address
--      that is another provider's source, an unknown or missing class; reports the existing source or stored copy it reuses, the existing reader that reads it (web page tables,
--      rendered page or PDF tables: no reader is created), whether reading is switched on, and whether machine admission is possible.
--   3. public.admin_aer_source NEW (screen read and actions): 'check' (Pipeline Operator and above), 'attach' an address and 'upload_begin' a PDF (Platform Admin, with a reason),
--      'meta' for the sources on the screen (classes, how attached, version, last verified, next retry). Attach adds the source (found_via manual) for the existing fetch and read,
--      or reuses the existing one: an unchanged copy already read is not read again; a failed or withdrawn one is asked again (status found, tries reset).
--   4. public.svc_aer_source_upload_record NEW (service role; called by edge function aer-source-upload after it stores the file where the fetch step stores PDFs): records the
--      stored copy through public.svc_entry_matrix_fetch_record (evidence registered, source read) and queues its one read.
--   5. security.aer_matrix_machine_check_v1 (md5-guarded edit): a copy a person uploaded is not proven to be what the official address serves, so its read is never admitted by
--      the machine class (rule uploaded_copy, decided in Layer 4).
-- Live definitions this change edits (pg_proc.prosrc md5, read 11 Nov 2026 21:05 AEDT), before -> after:
--   security.aer_matrix_machine_check_v1(uuid) 8b25b3dcb246a08561dd0ebd48f0ff37 -> 26e7a3f959a5bc7c2c29fc9031c594c2  (after 20261112110700, the quote proof)
-- Replaces: security.aer_matrix_machine_check_v1 (same name; md5-guarded text edit, resulting md5 checked); taken back by supabase/held/aer_source_management_forward_recovery.sql
-- Retires: nothing (public.admin_entry_matrix_seed stays for bulk lists; the screen uses admin_aer_source).
-- Reversal without code: none needed; attaching is a deliberate action and every read still goes to Layer 4.

do $g$
declare r record;
begin
  for r in select * from (values ('security.aer_matrix_machine_check_v1(uuid)'), ('public.svc_entry_matrix_fetch_record(uuid,text,text,integer,text,text,text,text)'),
                                 ('security.entry_matrix_enqueue_v1()'), ('security.site_host_v1(text)'), ('security.third_party_host_v1(text)'), ('security.pipeline_num_v1(text,numeric)'),
                                 ('security.current_role_rank()'), ('security.toolset_setting(text,text)')) v(sig) loop
    if to_regprocedure(r.sig) is null then raise exception 'required % is missing', r.sig; end if;
  end loop;
  if to_regclass('pipeline.entry_matrix_sources') is null or to_regclass('pipeline.entry_matrix_runs') is null or to_regclass('pipeline.evidence_artifacts') is null
     or to_regclass('pipeline.admin_control_events') is null then raise exception 'a table this change reads is missing'; end if;
end $g$;

-- 1. attachments ---------------------------------------------------------------------------------------------------------------------------------
create table if not exists pipeline.aer_source_attachments (
  id bigserial primary key,
  source_id uuid not null references pipeline.entry_matrix_sources(id),
  provider_id uuid not null references catalogue.providers(id),
  how text not null check (how in ('url', 'pdf_upload')),
  classes text[] not null check (cardinality(classes) > 0 and classes <@ array['country_table', 'international_qualification', 'national_qualification', 'undergraduate', 'postgraduate', 'course_specific']),
  reason text not null,
  ownership jsonb not null default '{}'::jsonb,
  reused text,
  content_hash text,
  storage_path text,
  attached_by uuid,
  at timestamptz not null default now(),
  completed_at timestamptz
);
create index if not exists aer_source_attachments_source_idx on pipeline.aer_source_attachments (source_id, at desc);
comment on table pipeline.aer_source_attachments is 'CF-247 F-AER.04 D3: entry-requirements sources a person attached on Catalogue › Entry requirements › Sources (address or uploaded PDF), with classes, ownership check and reuse. Annotates pipeline.entry_matrix_sources (the one source registry). Written by public.admin_aer_source and public.svc_aer_source_upload_record.';

-- 2. the check -----------------------------------------------------------------------------------------------------------------------------------
create or replace function security.aer_source_check_v1(p_provider uuid, p_url text, p_classes text[], p_how text default 'url', p_sha text default null, p_bytes bigint default null)
returns jsonb language plpgsql stable security definer set search_path = '' as $f$
declare v_url text := trim(coalesce(p_url, '')); p record; s record; v_ph text; v_sh text; v_ev uuid; v_bad text[]; v_pdf boolean; v_render boolean; v_on boolean; v_max numeric;
        c_classes constant text[] := array['country_table', 'international_qualification', 'national_qualification', 'undergraduate', 'postgraduate', 'course_specific'];  -- fixed: the classes of Platform Admin decision D3
begin
  if coalesce(p_how, '') not in ('url', 'pdf_upload') then return jsonb_build_object('ok', false, 'rule', 'how_unknown', 'reason', 'Attach an address or upload a PDF.'); end if;
  select x.id, coalesce(x.display_name, x.canonical_name) name, x.website into p from catalogue.providers x where x.id = p_provider;
  if p.id is null then return jsonb_build_object('ok', false, 'rule', 'provider_not_found', 'reason', 'Choose a provider.'); end if;
  if v_url !~* '^https?://[^/\s]+' then return jsonb_build_object('ok', false, 'rule', 'url_invalid', 'reason', 'Give the full address where the provider publishes it (https://...).'); end if;
  if p_classes is null or cardinality(p_classes) = 0 then return jsonb_build_object('ok', false, 'rule', 'class_required', 'reason', 'Choose at least one class.'); end if;
  v_bad := array(select unnest(p_classes) except select unnest(c_classes));
  if cardinality(v_bad) > 0 then return jsonb_build_object('ok', false, 'rule', 'class_unknown', 'reason', 'Unknown class: ' || array_to_string(v_bad, ', ')); end if;
  v_ph := security.site_host_v1(p.website); v_sh := security.site_host_v1(v_url);
  if v_ph is null then return jsonb_build_object('ok', false, 'rule', 'provider_no_website', 'reason', 'The provider has no website on record: record it on the provider first, so ownership can be checked.'); end if;
  if security.third_party_host_v1(v_url) then return jsonb_build_object('ok', false, 'rule', 'directory_site', 'reason', format('%s is a directory or third-party site, not the provider''s own.', v_sh)); end if;
  if v_sh is null or not (v_sh = v_ph or v_sh like '%.' || v_ph) then
    return jsonb_build_object('ok', false, 'rule', 'not_official_host', 'reason', format('The address is on %s, not on the provider''s own website %s (or a subdomain of it).', coalesce(v_sh, '?'), v_ph)); end if;
  select x.id, x.provider_id, x.status, x.read_at, x.content_hash, x.evidence_id, x.attempts into s from pipeline.entry_matrix_sources x where x.url = v_url order by (x.provider_id = p_provider) desc limit 1;
  if s.id is not null and s.provider_id <> p_provider then return jsonb_build_object('ok', false, 'rule', 'source_of_another_provider', 'reason', 'This address is another provider''s entry source.'); end if;
  if p_how = 'pdf_upload' then
    if coalesce(p_sha, '') !~ '^[0-9a-f]{64}$' then return jsonb_build_object('ok', false, 'rule', 'file_required', 'reason', 'Choose the PDF file.'); end if;
    v_max := security.pipeline_num_v1('entry.pdf_max_bytes', 20000000);
    if p_bytes is not null and p_bytes > v_max then return jsonb_build_object('ok', false, 'rule', 'file_too_large', 'reason', format('The file is %s MB; the most the reader takes is %s MB (entry.pdf_max_bytes).', round(p_bytes / 1048576.0, 1), round(v_max / 1048576.0, 1))); end if;
    select e.id into v_ev from pipeline.evidence_artifacts e where e.content_hash = p_sha and e.source_url = v_url limit 1;
  end if;
  v_pdf := p_how = 'pdf_upload' or v_url ~* '\.pdf($|[?#])';
  v_render := not v_pdf and coalesce(security.toolset_setting('pipeline', 'entry.render_hosts'), '[]'::jsonb) ? lower(substring(v_url from '^https?://(?:www\.)?([^/:?#]+)'));
  v_on := security.pipeline_num_v1('entry.matrix_enabled', 0) >= 1 and (not v_pdf or security.pipeline_num_v1('entry.pdf_enabled', 0) >= 1);
  return jsonb_build_object('ok', true, 'provider', p.name, 'host', v_sh, 'official_host', v_ph, 'ownership', 'official_host',
    'reuse', case when v_ev is not null then 'stored_copy' when s.id is not null then 'source' end, 'source_id', s.id, 'source_status', s.status, 'last_read', s.read_at,
    'reader', case when v_pdf then 'Entry matrix reader: PDF tables (ruled cells)' when v_render then 'Entry matrix reader: rendered page' else 'Entry matrix reader: web page tables' end,
    'reader_exists', true, 'reading_on', v_on,
    'machine_admission', case when p_how = 'pdf_upload' then 'Never: an uploaded copy is decided by a person in Layer 4.' else 'Possible only when every condition of decision D1 holds; otherwise a person decides in Layer 4.' end,
    'next_action', case when not v_on then 'Reading is switched off (entry.matrix_enabled or entry.pdf_enabled): the source waits.'
                        when v_ev is not null then 'This file is already stored for this address: its read is not repeated.'
                        when s.id is not null and s.status = 'read' and p_how = 'url' then 'Already a source and read: the current copy is not read again (use Read again to fetch a new copy).'
                        when s.id is not null and s.status in ('failed', 'inactive') and p_how = 'url' then 'Already a source that stopped: attaching asks the fetch again.'
                        when s.id is not null and s.status = 'robots_disallowed' and p_how = 'url' then 'The site does not allow this address to be fetched: upload the PDF instead.'
                        when p_how = 'pdf_upload' then 'The file is stored as this source''s copy and read once; its rows go to Layer 4.'
                        else 'Added to the sources: fetched and read by the next entry-matrix-read run; its rows go to Layer 4.' end);
end $f$;
comment on function security.aer_source_check_v1(uuid, text, text[], text, text, bigint) is 'CF-247 F-AER.04 D3: checks an entry-requirements source a person attaches: ownership (provider''s own website host), classes, reuse of an existing source or stored copy, the existing reader, whether reading is on.';

-- 3. screen read and actions ---------------------------------------------------------------------------------------------------------------------
create or replace function public.admin_aer_source(p_args jsonb default '{}'::jsonb)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare v_rank int := coalesce(security.current_role_rank(), 0); v_act text := coalesce(nullif(p_args->>'action', ''), 'check');
        v_pid uuid := nullif(p_args->>'provider_id', '')::uuid; v_url text := trim(coalesce(p_args->>'url', '')); v_how text := coalesce(nullif(p_args->>'how', ''), 'url');
        v_cls text[] := array(select jsonb_array_elements_text(case when jsonb_typeof(p_args->'classes') = 'array' then p_args->'classes' else '[]'::jsonb end));
        v_reason text := trim(coalesce(p_args->>'reason', '')); v_sha text := lower(nullif(p_args->>'sha256', '')); v_bytes bigint := nullif(p_args->>'bytes', '')::bigint;
        v_chk jsonb; v_sid uuid; v_att bigint; v_reused text; v_country text; v_outcome text; s record; v_ids uuid[];
begin
  if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;
  if v_act = 'meta' then
    v_ids := array(select x::uuid from jsonb_array_elements_text(case when jsonb_typeof(p_args->'source_ids') = 'array' then p_args->'source_ids' else '[]'::jsonb end) x limit 200);  -- fixed: one screen page
    return coalesce((select jsonb_object_agg(m.id, jsonb_build_object(
      'classes', (select a.classes from pipeline.aer_source_attachments a where a.source_id = m.id order by a.at desc limit 1),
      'attached', (select jsonb_build_object('how', a.how, 'at', a.at, 'complete', a.how = 'url' or a.completed_at is not null, 'reused', a.reused)
                     from pipeline.aer_source_attachments a where a.source_id = m.id order by a.at desc limit 1),
      'found_via', m.found_via,
      'version', (select count(distinct r.content_hash) from pipeline.entry_matrix_runs r where r.source_id = m.id),
      'last_verified', m.read_at,
      'next_retry', case when m.status = 'found' then 'Next entry-matrix-read run (every 5 minutes)'
                         when m.status = 'reading' then 'Being fetched now'
                         when m.status = 'failed' then 'No tries left (entry.matrix_attempts): attach it again, or upload the PDF'
                         when m.status = 'robots_disallowed' then 'The site does not allow fetching: upload the PDF'
                         when m.status = 'pdf_step_b' then 'Waits while PDF reading is off (entry.pdf_enabled)'
                         when m.status = 'inactive' then 'Withdrawn: attach it again to ask the fetch again' end))
      from pipeline.entry_matrix_sources m where m.id = any(v_ids)), '{}'::jsonb);
  end if;
  if v_act = 'check' then
    if v_rank < 4 then raise exception 'Pipeline Operator or above required' using errcode = '42501'; end if;  -- fixed: the rank of the AER discovery read
    return security.aer_source_check_v1(v_pid, v_url, v_cls, v_how, v_sha, v_bytes) || jsonb_build_object('can_attach', v_rank >= 6);
  end if;
  if v_act not in ('attach', 'upload_begin') then raise exception 'unknown action %', v_act using errcode = '22023'; end if;
  if v_rank < 6 then raise exception 'Platform Admin required to attach a source' using errcode = '42501'; end if;  -- fixed: the rank of Read again and of the source seed
  if length(v_reason) < 5 then raise exception 'reason required' using errcode = '22023'; end if;
  if (v_act = 'attach') <> (v_how = 'url') then raise exception 'attach takes an address; upload_begin takes a PDF' using errcode = '22023'; end if;
  v_chk := security.aer_source_check_v1(v_pid, v_url, v_cls, v_how, v_sha, v_bytes);
  if not coalesce((v_chk->>'ok')::boolean, false) then return v_chk || jsonb_build_object('attached', false); end if;
  v_sid := nullif(v_chk->>'source_id', '')::uuid;
  if v_sid is null then
    insert into pipeline.entry_matrix_sources(provider_id, url, title, rank, found_via, status)
    values (v_pid, v_url, left(nullif(trim(p_args->>'title'), ''), 200), 1, 'manual', case when v_how = 'pdf_upload' then 'inactive' else 'found' end)
    returning id into v_sid;
    v_reused := null; v_outcome := case when v_how = 'pdf_upload' then 'Source added; the file is stored next.' else 'Source added: the next entry-matrix-read run fetches and reads it; its rows go to Layer 4.' end;
  else
    select * into s from pipeline.entry_matrix_sources x where x.id = v_sid for update;
    v_reused := v_chk->>'reuse';
    if v_how = 'url' and s.status in ('failed', 'inactive') then
      update pipeline.entry_matrix_sources set status = 'found', attempts = 0, error = null, updated_at = now() where id = v_sid;
      v_outcome := 'Existing source asked again: the next entry-matrix-read run fetches and reads it.';
    else
      v_outcome := v_chk->>'next_action';
    end if;
  end if;
  insert into pipeline.aer_source_attachments(source_id, provider_id, how, classes, reason, ownership, reused, content_hash, attached_by, completed_at)
  values (v_sid, v_pid, v_how, v_cls, v_reason, jsonb_build_object('rule', v_chk->>'ownership', 'host', v_chk->>'host', 'official_host', v_chk->>'official_host'),
          v_reused, case when v_how = 'pdf_upload' then v_sha end, auth.uid(), case when v_how = 'url' or v_reused = 'stored_copy' then now() end)
  returning id into v_att;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'source_' || v_act, 'pipeline.entry_matrix_sources',
          jsonb_build_object('source_id', v_sid, 'attachment_id', v_att, 'provider_id', v_pid, 'url', v_url, 'how', v_how, 'classes', to_jsonb(v_cls), 'reused', v_reused, 'reason', v_reason), auth.uid());
  if v_act = 'upload_begin' and coalesce(v_reused, '') <> 'stored_copy' then
    select k.iso_alpha2 into v_country from catalogue.providers p join ref.countries k on k.id = p.country_id where p.id = v_pid;
    return v_chk || jsonb_build_object('attached', true, 'source_id', v_sid, 'attachment_id', v_att, 'upload', true,
      'storage_path', format('layer2/%s/entry-matrix/%s/%s/%s.pdf.gz', coalesce(v_country, 'XX'), v_pid, v_sid, v_sha), 'outcome', v_outcome);
  end if;
  return v_chk || jsonb_build_object('attached', true, 'source_id', v_sid, 'attachment_id', v_att, 'upload', false, 'outcome', v_outcome);
end $f$;
revoke all on function public.admin_aer_source(jsonb) from public, anon;
grant execute on function public.admin_aer_source(jsonb) to authenticated;
comment on function public.admin_aer_source(jsonb) is 'CF-247 F-AER.04 D3: Catalogue › Entry requirements › Sources: check (rank 4), attach an address or begin a PDF upload (Platform Admin, reason), and meta for listed sources (classes, version, last verified, next retry). Never part of the consumer API.';

-- 4. the upload record ---------------------------------------------------------------------------------------------------------------------------
create or replace function public.svc_aer_source_upload_record(p_attachment bigint, p_path text, p_sha text)
returns jsonb language plpgsql security definer set search_path = '' as $f$
declare a pipeline.aer_source_attachments%rowtype; v_res jsonb; v_q int;
begin
  if current_user <> 'postgres' and coalesce(auth.role(), '') <> 'service_role' then raise exception 'service_role required'; end if;
  select * into a from pipeline.aer_source_attachments where id = p_attachment for update;
  if a.id is null or a.how <> 'pdf_upload' then raise exception 'upload attachment not found'; end if;
  if a.completed_at is not null then return jsonb_build_object('ok', true, 'already', true); end if;
  if a.content_hash is distinct from lower(p_sha) or p_path !~ ('/entry-matrix/' || a.provider_id || '/' || a.source_id || '/' || a.content_hash || '\.pdf\.gz$') then
    raise exception 'the stored file does not match the upload that was checked'; end if;
  v_res := public.svc_entry_matrix_fetch_record(a.source_id, 'read', null, null, p_path, a.content_hash, 'application/pdf', null);
  update pipeline.aer_source_attachments set storage_path = p_path, completed_at = now() where id = a.id;
  v_q := security.entry_matrix_enqueue_v1();
  return jsonb_build_object('ok', true, 'source_id', a.source_id, 'evidence_id', v_res->>'evidence_id', 'reads_queued', v_q,
                            'outcome', 'Stored as the source''s copy; the next entry-matrix-read run reads it and its rows go to Layer 4 for a person.');
end $f$;
revoke all on function public.svc_aer_source_upload_record(bigint, text, text) from public, anon, authenticated;
grant execute on function public.svc_aer_source_upload_record(bigint, text, text) to service_role;
comment on function public.svc_aer_source_upload_record(bigint, text, text) is 'CF-247 F-AER.04 D3: records a PDF a person uploaded (edge function aer-source-upload) as the entry source''s stored copy and queues its one read. Service role only.';
revoke all on function security.aer_source_check_v1(uuid, text, text[], text, text, bigint) from public, anon, authenticated;

-- 5. the guarded edit ----------------------------------------------------------------------------------------------------------------------------
do $m$
declare r record; v_def text; v_src text; v_c int; k int; v_sig regprocedure;
begin
  for r in select * from (values
    ('security.aer_matrix_machine_check_v1(uuid)', '8b25b3dcb246a08561dd0ebd48f0ff37', '26e7a3f959a5bc7c2c29fc9031c594c2',
     array[$o$  if r.content_hash is distinct from f.content_hash then$o$],
     array[$n$  -- 12 Nov 2026 (D3): a copy a person uploaded is not proven to be what the official address serves; it stays with a person
  if f.read_via is null and exists (select 1 from pipeline.aer_source_attachments a where a.source_id = f.id and a.how = 'pdf_upload' and a.content_hash = f.content_hash) then
    return jsonb_build_object('ok', false, 'rule', 'uploaded_copy', 'reason', 'The stored copy was uploaded by a person, not fetched from the official address.', 'next_action', decline, 'checks', v_checks); end if;
  if r.content_hash is distinct from f.content_hash then$n$])
  ) v(sig, md5_before, md5_after, olds, news) loop
    v_sig := to_regprocedure(r.sig);
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    -- fixed: the guard is the md5 of the live function body (pg_proc.prosrc), the same text on PostgreSQL 16 and 17
    if md5(v_src) = r.md5_after then raise notice '%: already applied', r.sig; continue; end if;
    if md5(v_src) <> r.md5_before then raise exception 'live % differs from the definition this change edits (body md5 %)', r.sig, md5(v_src); end if;
    v_def := replace(pg_get_functiondef(v_sig), chr(13), '');
    for k in 1 .. array_length(r.olds, 1) loop
      v_c := (length(v_def) - length(replace(v_def, r.olds[k], ''))) / length(r.olds[k]);
      if v_c <> 1 then raise exception '%: edit % must apply exactly once (found %)', r.sig, k, v_c; end if;
      v_def := replace(v_def, r.olds[k], r.news[k]);
    end loop;
    execute v_def;
    v_src := (select p.prosrc from pg_proc p where p.oid = v_sig);
    if md5(v_src) <> r.md5_after then raise exception '% after the edit has body md5 %, expected %', r.sig, md5(v_src), r.md5_after; end if;
    raise notice '%: applied', r.sig;
  end loop;
end $m$;

-- register, post-check ---------------------------------------------------------------------------------------------------------------------------
insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('table', 'pipeline.aer_source_attachments', 'Layer 2', 'Entry-requirements sources a person attached (address or uploaded PDF): classes, ownership check, reuse', 'active', '{}', '20261112113700'),
 ('function', 'public.admin_aer_source', 'Platform', 'Entry requirements › Sources: check, attach an address, begin a PDF upload, source meta', 'active', '{}', '20261112113700'),
 ('function', 'public.svc_aer_source_upload_record', 'Layer 2', 'Records an uploaded entry-requirements PDF as the source''s stored copy and queues its read', 'active', '{}', '20261112113700'),
 ('edge_function', 'aer-source-upload', 'Layer 2', 'Stores a PDF a Platform Admin attaches as an entry-requirements source (checked by admin_aer_source) where the fetch step stores PDFs', 'active', '{}', '20261112113700')
on conflict do nothing;

do $post$ begin
  if position('uploaded_copy' in (select p.prosrc from pg_proc p where p.oid = 'security.aer_matrix_machine_check_v1(uuid)'::regprocedure)) = 0 then raise exception 'post-check: an uploaded copy could be machine-admitted'; end if;
  if has_function_privilege('authenticated', 'public.svc_aer_source_upload_record(bigint,text,text)', 'execute') then raise exception 'post-check: the upload record is open to signed-in users'; end if;
end $post$;
