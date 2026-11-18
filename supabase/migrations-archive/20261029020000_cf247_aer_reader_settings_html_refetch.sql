-- CF-247 AER programme (Platform Admin decision 29 Oct 2026 09:57, "Continue the full AER programme", item 1: parked reader settings and
-- HTML refetch approved; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W12).
-- 1. Slices of one page are read several at once: entry.matrix_slice_concurrency (new setting, 6; worker v0.51.0 already honours it,
--    bounded 1-12) and entry.matrix_slice_chars 8,000 (was 20,000). Victoria University and Manukau replies were cut by the call time-out
--    while a 20,000-character slice streamed, and Wollongong ran out of its time budget reading slices one after another. Smaller slices
--    read six at a time fit the call and the budget; the answer limit, quote, scale, identity and completeness gates are unchanged.
-- 2. Read again (Catalogue › Entry requirements › Sources, reads and holds; Platform Admin) moves into security.aer_reread_v1 so the
--    approved programme batch and the screen use one mechanism. A web page whose stored copy is Firecrawl markdown (its tables cannot be
--    quoted row by row) is fetched again instead of re-read from that copy: its proposed rows and pending Layer 4 item are superseded with
--    the reason, the source returns to found, and the fetch keeps the page's own HTML (worker v0.50.2; entry_matrix_use_stored_v1 takes no
--    markdown copy). The markdown copy stays as evidence. Every other refusal (scope, AI stopped, waiting, held as unreadable) is unchanged.
-- Replaces: public.svc_entry_matrix_next and public.admin_aer (same names, md5-guarded edits); admin_aer's re-read body moves to
--           security.aer_reread_v1 (new, owner only)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.matrix_slice_concurrency', 'Entry matrices: slices read at once',
  'A large page is read in slices; this many slices of one page are read at the same time and joined in page order. 1 reads them one after another.', 'number',
  to_jsonb(6), 1, 12, 'slices', 905, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai',
  'CF-247 AER programme 29 Oct 2026 (Platform Admin decision 09:57): long tables (Victoria University, Manukau, Wollongong, Western Sydney) ran past the call time-out or time budget one slice after another')
on conflict (toolset_key, key) do nothing;

update pipeline.platform_toolset_settings set value = to_jsonb(8000), updated_at = now(),
       reason = 'CF-247 AER programme 29 Oct 2026 (Platform Admin decision 09:57): 8,000-character slices read six at a time fit the call time-out; 20,000-character slices were cut while streaming'
 where toolset_key = 'pipeline' and key = 'entry.matrix_slice_chars';

create or replace function pg_temp.edit_n(p_sig text, p_md5 text, p_edits text[][], p_times int[]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int; v_c int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    v_c := (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]);
    if v_c <> p_times[i] then raise exception '%: edit % must apply exactly % times (found %)', p_sig, i, p_times[i], v_c; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_n('public.svc_entry_matrix_next(integer)', 'dc1bab7a54fb4d4c0651e6be2fefe289', array[
  array[$o$           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,$o$,
        $n$           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,
           'slice_concurrency', security.pipeline_num_v1('entry.matrix_slice_concurrency', 1)::int,$n$]], array[1]);

-- one Read again mechanism (W12) for the screen and for the Platform Admin's approved programme batches
create or replace function security.aer_reread_v1(p_source_id uuid, p_reason text, p_actor uuid default null) returns jsonb
language plpgsql security definer set search_path to '' as $$
declare v_src pipeline.entry_matrix_sources%rowtype; v_run pipeline.entry_matrix_runs%rowtype; v_mime text; v_rows int := 0; v_items int := 0; v_n int;
        v_reason text := btrim(coalesce(p_reason, ''));
begin
  if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)' using errcode = '22023'; end if;
  select * into v_src from pipeline.entry_matrix_sources where id = p_source_id for update;
  if v_src.id is null then raise exception 'source not found'; end if;
  if not security.entry_matrix_enabled_v1(v_src.provider_id) then raise exception 'this provider is outside the reading scope (entry.providers)' using errcode = '22023'; end if;
  if not security.ai_use_allowed_v1('entry_matrix') then raise exception 'AI reading is stopped (AI limits); nothing was asked' using errcode = '22023'; end if;
  select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id order by created_at desc limit 1;
  if v_run.id is null then raise exception 'this source has not been read yet; it is read by the scheduled job' using errcode = '22023'; end if;
  if v_run.state in ('queued', 'leased') then raise exception 'a read of this source is already waiting or running' using errcode = '22023'; end if;
  if v_src.status in ('found', 'reading') then raise exception 'this page is waiting to be fetched again; its read follows' using errcode = '22023'; end if;
  if v_run.state = 'failed' and v_run.error like 'held_unparsed%' then
    raise exception 'this source is held as unreadable (%); only a reader change under change control reads it again', left(v_run.error, 120) using errcode = '22023'; end if;

  select e.mime_type into v_mime from pipeline.evidence_artifacts e where e.id = v_src.evidence_id;
  if v_mime = 'text/markdown' and v_src.url !~* '\.pdf($|[?#])' then
    -- 29 Oct 2026: a markdown copy cannot be quoted row by row; the page is fetched again and kept as its own HTML (worker v0.50.2)
    if v_src.status = 'robots_disallowed' then raise exception 'this page is disallowed by the site''s robots.txt; it is not fetched again' using errcode = '22023'; end if;
    update catalogue.provider_entry_matrix m set status = 'superseded', status_reason = 'read again as HTML: ' || v_reason, updated_at = now()
     where m.status = 'proposed' and m.run_id in (select r.id from pipeline.entry_matrix_runs r where r.source_id = v_src.id);
    get diagnostics v_rows = row_count;
    update pipeline.layer4_review_items li set status = 'superseded'
     where li.status = 'pending' and li.id in (select r.review_item_id from pipeline.entry_matrix_runs r where r.source_id = v_src.id);
    get diagnostics v_items = row_count;
    -- read_at cleared: a source never read since passes the central refresh interval only (svc_fc_spend, #722), as for the 29 Oct refetch (#730)
    update pipeline.entry_matrix_sources set status = 'found', attempts = 0, error = null, read_at = null, updated_at = now() where id = v_src.id;
    insert into pipeline.admin_control_events(area, action, target, detail, actor)
    values ('entry_matrix', 'refetch_html', 'pipeline.entry_matrix_sources',
            jsonb_build_object('source', v_src.id, 'markdown_evidence', v_src.evidence_id, 'rows_superseded', v_rows, 'items_superseded', v_items, 'reason', v_reason), p_actor);
    return jsonb_build_object('ok', true, 'refetch', true, 'rows_superseded', v_rows, 'items_superseded', v_items);
  end if;

  if v_run.state = 'done' then
    return public.admin_entry_matrix_reread(array[v_src.id], v_reason);
  end if;
  update pipeline.entry_matrix_runs set previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', v_run.error like 'held_%',
           'reason', 'read again from the workspace: ' || v_reason, 'error', left(coalesce(v_run.error, ''), 300), 'attempt', attempts, 'model', model_code, 'at', now(), 'result', result)),
         state = 'queued', attempts = 0, leased_until = null, error = null, updated_at = now()
   where id = v_run.id;
  insert into pipeline.admin_control_events(area, action, target, detail, actor)
  values ('entry_matrix', 'reread_failed', 'pipeline.entry_matrix_runs', jsonb_build_object('source', v_src.id, 'run', v_run.id, 'reason', v_reason), p_actor);
  return jsonb_build_object('ok', true, 'runs', 1);
end $$;
revoke all on function security.aer_reread_v1(uuid, text, uuid) from public, anon, authenticated;
comment on function security.aer_reread_v1(uuid, text, uuid) is 'CF-247 AER W12: one source read again (or fetched again as HTML when its stored copy is markdown); called by public.admin_aer after the Platform Admin check, and by approved programme migrations. Owner only.';

select pg_temp.edit_n('public.admin_aer(text,jsonb)', 'd582b0c2c4ecf70cac9a3615a6899f7a', array[
  array[$o$  if p_action = 'reread' then
    -- W12: one source, bounded, through the existing mechanisms; never past a terminal evidence hold
    select * into v_src from pipeline.entry_matrix_sources where id = (a->>'source_id')::uuid;
    if v_src.id is null then raise exception 'source not found'; end if;
    if not security.entry_matrix_enabled_v1(v_src.provider_id) then raise exception 'this provider is outside the reading scope (entry.providers)' using errcode = '22023'; end if;
    if not security.ai_use_allowed_v1('entry_matrix') then raise exception 'AI reading is stopped (AI limits); nothing was asked' using errcode = '22023'; end if;
    select * into v_run from pipeline.entry_matrix_runs where source_id = v_src.id order by created_at desc limit 1;
    if v_run.id is null then raise exception 'this source has not been read yet; it is read by the scheduled job' using errcode = '22023'; end if;
    if v_run.state in ('queued', 'leased') then raise exception 'a read of this source is already waiting or running' using errcode = '22023'; end if;
    if v_run.state = 'failed' and v_run.error like 'held_unparsed%' then
      raise exception 'this source is held as unreadable (%); only a reader change under change control reads it again', left(v_run.error, 120) using errcode = '22023'; end if;
    if v_run.state = 'done' then
      v_out := public.admin_entry_matrix_reread(array[v_src.id], v_reason);
    else
      update pipeline.entry_matrix_runs set previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', v_run.error like 'held_%',
               'reason', 'read again from the workspace: ' || v_reason, 'error', left(coalesce(v_run.error, ''), 300), 'attempt', attempts, 'model', model_code, 'at', now(), 'result', result)),
             state = 'queued', attempts = 0, leased_until = null, error = null, updated_at = now()
       where id = v_run.id;
      insert into pipeline.admin_control_events(area, action, target, detail, actor)
      values ('entry_matrix', 'reread_failed', 'pipeline.entry_matrix_runs', jsonb_build_object('source', v_src.id, 'run', v_run.id, 'reason', v_reason), auth.uid());
      v_out := jsonb_build_object('ok', true, 'runs', 1);
    end if;
    return v_out;
  end if;
$o$,
        $n$  if p_action = 'reread' then
    -- W12: one source, bounded, through the one mechanism (security.aer_reread_v1, 29 Oct 2026); never past a terminal evidence hold
    return security.aer_reread_v1((a->>'source_id')::uuid, v_reason, auth.uid());
  end if;
$n$]], array[1]);

insert into pipeline.component_register(kind, name, layer, purpose, status, replaces, introduced_in) values
 ('function', 'security.aer_reread_v1', 'Pipeline', 'AER W12: one Read again mechanism (re-read, re-queue a failed read, or fetch a markdown-stored page again as HTML)', 'active', '{}', '20261029020000')
on conflict do nothing;
