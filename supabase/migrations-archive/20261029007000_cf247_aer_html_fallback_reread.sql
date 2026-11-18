-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22; acceptance names every open gate with its exact reason):
-- after worker v0.50.2 answers live (merged separately: the 28 Oct deploy-order lesson), two bounded re-reads.
--
-- 1. HTML Firecrawl-fallback route. Entry pages refused to a direct read were kept as Firecrawl markdown, whose tables the reader cannot
--    quote row by row (AUT 0 rows; Otago, Melbourne IB and Griffith 0 rows). Worker v0.50.2 keeps the page's own HTML instead. An entry
--    source no longer takes a stored markdown copy, and the sources stored as markdown whose reads wait on no person are fetched again
--    (expected 5, bounded at 6). Griffith is a rendered-route host, so it is fetched rendered (Step C). Sources whose rows wait in Layer 4
--    are left to the Platform Admin's decision.
-- 2. Reads that ended "the model returned no answer" (Victoria University and Western Sydney PDFs, Manukau) get their tries back once,
--    so worker v0.50.2 records why (expected 3, bounded at 5). The earlier reading is kept in each run's history.
-- Replaces: security.entry_matrix_use_stored_v1 (same name, md5-guarded edit)
-- Retires: nothing (the markdown copies stay as evidence)
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table, setting or status.

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

select pg_temp.edit_n('security.entry_matrix_use_stored_v1()', '1d00979372ff27a93725485ac31819ca', array[
  array[$o$                              and (s.url !~* '\.pdf($|[?#])' or a.mime_type = 'application/pdf')$o$,
        $n$                              and (s.url !~* '\.pdf($|[?#])' or a.mime_type = 'application/pdf')
                              -- 29 Oct 2026: an entry source takes no markdown copy (its tables cannot be read row by row)
                              and a.mime_type is distinct from 'text/markdown'$n$]], array[1]);

do $$ declare v_n int; begin
  -- read_at cleared: a source never read since this change passes the central refresh interval only (svc_fc_spend, 29 Oct 2026 #722)
  update pipeline.entry_matrix_sources s set status = 'found', attempts = 0, error = null, read_at = null, updated_at = now()
   where s.status = 'read' and security.entry_matrix_enabled_v1(s.provider_id)
     and exists (select 1 from pipeline.evidence_artifacts e where e.id = s.evidence_id and e.mime_type = 'text/markdown')
     and not exists (select 1 from pipeline.entry_matrix_runs r join pipeline.layer4_review_items li on li.id = r.review_item_id
                      where r.source_id = s.id and li.status in ('pending', 'approved'));
  get diagnostics v_n = row_count;
  if v_n > 6 then raise exception 'expected at most 6 markdown entry sources to fetch again, found %', v_n; end if;
end $$;

do $$ declare v_n int; begin
  update pipeline.entry_matrix_runs set previous_results = previous_results || jsonb_build_array(jsonb_build_object('held', false,
           'reason', 'read again after worker v0.50.2 (no-answer reason named): ' || left(coalesce(error, ''), 200),
           'attempt', attempts, 'model', model_code, 'at', now(), 'result', result)),
         state = 'queued', attempts = 0, leased_until = null, error = null, updated_at = now()
   where state = 'failed' and review_item_id is null
     and (error like 'the model returned no answer%' or error like 'stopped after % tries without a reply: the model returned no answer%');
  get diagnostics v_n = row_count;
  if v_n > 5 then raise exception 'expected at most 5 no-answer runs to read again, found %', v_n; end if;
end $$;
