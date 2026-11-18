-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22; admin docs/platform/ENTRY-REQUIREMENTS-PROGRAMME-DECISION-2026-10-28.md).
-- Wave H's first reads (#721) showed two source-route faults that stop approved sources being read. Each fix keeps every gate as it is:
-- 1. Two large pages (UWA, UOW) were read in slices whose answers were cut off at the fixed 8,000-token limit ("Unterminated string in
--    JSON"), and were retried at the same size. The answer limit and the slice size become settings (G2): entry.matrix_max_tokens
--    (16,000) and entry.matrix_slice_chars (12,000 characters). svc_entry_matrix_next passes them; worker v0.49.2 uses them and names a
--    cut-off answer output_truncated.
-- 2. Pages the provider's site refuses to a direct read (AUT, Otago Polytechnic and others) fall back to Firecrawl within the existing
--    budget check, which refused them as not_due: the provider's central pages were read within central_refresh_days. Decision 265
--    already lets a page a person added and never read through that interval; svc_fc_spend now treats a seeded entry-requirements source
--    the same way (never read, status found or reading). Every other budget rule (day total, shares, reserve, directory sites) is unchanged.
-- 3. A budget refusal is not the page failing: svc_entry_matrix_fetch_record no longer counts credits_refused, credits_reserve or
--    no_firecrawl_key as one of the page's entry.matrix_attempts, and the Wave H sources it already counted are given those tries back.
-- Replaces: public.svc_entry_matrix_next, public.svc_entry_matrix_fetch_record, public.svc_fc_spend (same names, md5-guarded edits)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'entry.matrix_max_tokens', 'Entry matrices: answer length', 'The longest answer the entry-matrix reader may give for one slice of a page. A slice whose answer reaches it is held as output_truncated.', 'number',
  to_jsonb(16000), 4000, 32000, 'tokens', 904, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai',
  'CF-247 AER programme 29 Oct 2026: two Wave H pages cut off at the fixed 8,000-token limit'),
 ('pipeline', 'entry.matrix_slice_chars', 'Entry matrices: characters a slice', 'A large page is read in slices of at most this many characters (and Entry matrices: rows a slice), so each answer fits its length.', 'number',
  to_jsonb(12000), 4000, 24000, 'characters', 904, 'Entry requirements', 'public.svc_entry_matrix_next, worker entry_ai',
  'CF-247 AER programme 29 Oct 2026: slices of 24,000 characters gave answers longer than the answer limit')
on conflict (toolset_key, key) do nothing;

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

select pg_temp.edit_n('public.svc_entry_matrix_next(integer)', 'f992b7fc20bfce4d27c0e7bbee4256a3', array[
  array[$o$           'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int,$o$,
        $n$           'max_rows', security.pipeline_num_v1('entry.matrix_max_rows_per_page', 400)::int,
           'max_tokens', security.pipeline_num_v1('entry.matrix_max_tokens', 8000)::int,
           'slice_chars', security.pipeline_num_v1('entry.matrix_slice_chars', 24000)::int,$n$]], array[1]);

select pg_temp.edit_n('public.svc_entry_matrix_fetch_record(uuid,text,text,integer,text,text,text,text)', '90a5ff928f1213e5f8ec4a58e5194066', array[
  array[$o$  update pipeline.entry_matrix_sources set
         status = case when p_status = 'robots_disallowed' then 'robots_disallowed'$o$,
        $n$  -- 29 Oct 2026: a Firecrawl budget refusal is not the page failing; it waits for the next read without using one of its tries
  update pipeline.entry_matrix_sources set
         attempts = case when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then greatest(attempts - 1, 0) else attempts end,
         status = case when p_status = 'robots_disallowed' then 'robots_disallowed'
                       when p_error in ('credits_refused', 'credits_reserve', 'no_firecrawl_key') then 'found'$n$]], array[1]);

select pg_temp.edit_n('public.svc_fc_spend(numeric,text,uuid,text)', '98aaa595c7eae2199ceac2decbfee474', array[
  array[$o$                             and fs.status in ('found', 'reading') and fs.read_at is null) then  -- 21 Oct 2026: any page never read (fee reader)$o$,
        $n$                             and fs.status in ('found', 'reading') and fs.read_at is null)  -- 21 Oct 2026: any page never read (fee reader)
          -- 29 Oct 2026 (AER programme): nor is a seeded entry-requirements page never read
          and not exists (select 1 from pipeline.entry_matrix_sources es where es.provider_id = p_provider_id and es.url = p_url
                             and es.status in ('found', 'reading') and es.read_at is null) then$n$]], array[1]);

-- the tries Wave H's refused reads used, given back (the sources stay found; nothing else changes)
do $$ declare v_n int; begin
  update pipeline.entry_matrix_sources set attempts = 0, updated_at = now()
   where found_via = 'manual' and status = 'found' and error in ('credits_refused', 'credits_reserve') and read_at is null;
  get diagnostics v_n = row_count;
  if v_n > 20 then raise exception 'expected at most 20 refused Wave H sources, found %', v_n; end if;
end $$;
