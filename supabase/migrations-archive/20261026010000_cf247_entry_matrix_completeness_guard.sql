-- CF-247 AER v1.1, source-anchored completeness guard (Platform Admin 26 Oct 2026 23:16: "Build and release the source-anchored completeness
-- guard … A reviewer must not be able to approve a run that fails it"). Record: admin docs/platform/aer-v1.1-build-log.md.
-- Why: after #708 a China read gave 13 of the 22 minimums its page publishes (the whole Gao Kao column left out), nothing was dropped, and
-- the read was proposed for review as if complete. Worker v0.48.3 builds a manifest of every minimum the stored page's band tables publish
-- and compares the whole read with it (entryCompleteness). The database enforces the verdict, so no path proposes or admits a partial read:
-- 1 Setting entry.completeness_providers (list): providers under the guard. Seeded with RMIT (the band-ladder provider); UTS and WSU are not
--   band-table pages and stay as they are (Platform Admin 23:16: "UTS is outside this defect").
-- 2 security.entry_completeness_required_v1(provider): whether the provider is under the guard.
-- 3 svc_entry_matrix_next (md5-guarded): each item says whether its provider is under the guard, so the worker holds an unreadable page
--   before any AI read.
-- 4 svc_entry_matrix_record (md5-guarded): for a provider under the guard, a result without a "complete" verdict proposes nothing and is
--   handled as a held read; every held or failed read that carries a result is kept in previous_results (never discarded); a page whose
--   tables cannot be read ("held_unparsed") is not read again (state failed); an incomplete read is retried within the existing
--   entry.matrix_attempts. Successful results keep the verdict, prompt version and page basis.
-- 5 entry_matrix_review_apply_v1 (md5-guarded): approval (and the changed-page auto-admit, which calls it) refuses a run under the guard whose
--   read has no "complete" verdict, and any run whose verdict is incomplete or unparsed.
-- Replaces: nothing (three functions edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched. No new status values.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.completeness_providers', 'Entry matrices: completeness guard', 'Providers whose entry-matrix reads must match every minimum their band tables publish before rows are proposed or admitted (provider ids). A read that is not complete is held whole and retried within Entry matrices: attempts.', 'list',
  '["8e1adb6c-e069-43db-9584-bd054255e702"]'::jsonb,
  null, null, 'providers', 903, 'Entry requirements', 'security.entry_completeness_required_v1',
  'CF-247 AER v1.1, Platform Admin 26 Oct 2026 23:16: source-anchored completeness guard for the band-ladder provider (RMIT)')
on conflict (toolset_key, key) do nothing;

create or replace function security.entry_completeness_required_v1(p_provider uuid) returns boolean
language sql stable security definer set search_path to '' as $$
  select coalesce(security.toolset_setting('pipeline', 'entry.completeness_providers'), '[]'::jsonb) ? p_provider::text
$$;
comment on function security.entry_completeness_required_v1(uuid) is 'CF-247 AER v1.1: whether a provider''s entry-matrix reads must pass the source-anchored completeness guard (setting entry.completeness_providers).';

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

select pg_temp.edit_n('public.svc_entry_matrix_next(integer)', '4b5a59dae7a62f5d770761a4d05e047c', array[
  array[$o$'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int)), '[]'::jsonb) into v$o$,
        $n$'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int,
           'completeness_required', security.entry_completeness_required_v1(u.provider_id))), '[]'::jsonb) into v$n$]], array[1]);

select pg_temp.edit_n('public.svc_entry_matrix_record(uuid,jsonb,numeric,text)', 'd80183c6903a48eb1e9c08fbc8a1e706', array[
  array[$o$  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;
$o$,
        $n$  if r.id is null then return jsonb_build_object('ok', false, 'error', 'unknown run'); end if;
  -- completeness guard (26 Oct 2026): under entry.completeness_providers only a read the worker found complete proposes rows
  if p_error is null and security.entry_completeness_required_v1(r.provider_id) and coalesce(p_result->'completeness'->>'status', 'missing') <> 'complete' then
    p_error := 'held_incomplete: no complete verdict (' || coalesce(p_result->'completeness'->>'status', 'missing') || ')';
  end if;
$n$],
  array[$o$    update pipeline.entry_matrix_runs set
           state = case when p_error = 'time budget' then 'queued' when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'queued' end,$o$,
        $n$    update pipeline.entry_matrix_runs set
           -- a held read is kept whole in the run history; an unreadable page is not read again, an incomplete read is retried within entry.matrix_attempts
           previous_results = case when p_result is null then previous_results
                                   else previous_results || jsonb_build_array(jsonb_build_object('held', p_error like 'held_%', 'reason', left(p_error, 400),
                                          'attempt', attempts, 'model', model_code, 'at', now(), 'result', p_result)) end,
           state = case when p_error like 'held_unparsed%' then 'failed' when p_error = 'time budget' then 'queued' when attempts >= security.pipeline_num_v1('entry.matrix_attempts', 3) then 'failed' else 'queued' end,$n$],
  array[$o$         result = jsonb_build_object('dropped', v_dropped, 'edition', p_result->'edition', 'worker', p_result->'worker'),$o$,
        $n$         result = jsonb_build_object('dropped', v_dropped, 'edition', p_result->'edition', 'worker', p_result->'worker',
                                     'prompt_version', p_result->'prompt_version', 'page_basis', p_result->'page_basis', 'completeness', p_result->'completeness'),$n$]],
  array[1, 1, 1]);

select pg_temp.edit_n('security.entry_matrix_review_apply_v1(uuid,text,jsonb,text,uuid)', '76cce959081557411a5db494a85b6817', array[
  array[$o$      raise exception 'entry matrix run %: proposed rows share an identity; nothing admitted', r.id using errcode = '23505';
    end if;$o$,
        $n$      raise exception 'entry matrix run %: proposed rows share an identity; nothing admitted', r.id using errcode = '23505';
    end if;
    -- completeness guard (26 Oct 2026): a read that has not passed it is never admitted
    if coalesce(r.result->'completeness'->>'status', 'missing') in ('incomplete', 'unparsed')
       or (security.entry_completeness_required_v1(r.provider_id) and coalesce(r.result->'completeness'->>'status', 'missing') <> 'complete') then
      raise exception 'entry matrix run %: the read has not passed the completeness guard (%); nothing admitted', r.id,
        coalesce(r.result->'completeness'->>'status', 'no verdict') using errcode = '23514';
    end if;$n$]], array[1]);
