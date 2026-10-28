-- CF-247 AER programme (Platform Admin consolidated mandate, 28 Oct 2026 23:22, item 1: "operators can inspect provider and course data,
-- evidence, statuses, runs, holds and resolution results through bounded UI reads"). The provider's Academic entry requirements section
-- showed only rows; a source read with no row, held before any AI read (a PDF whose tables could not be proven), refused, or still
-- waiting was not visible. public.admin_entry_requirements('provider_matrix') now also returns the provider's sources (at most 50) with
-- each one's latest read: state, rows, rows not kept, hold or error, cost, page basis and its Layer 4 item. Read only; nothing is edited or
-- admitted here (admission stays in Layer 4). The same section in the Provider drawer shows them. No new screen.
-- Replaces: public.admin_entry_requirements (same name, md5-guarded edit)
-- Retires: nothing
-- Nothing dropped, deleted or renamed. The consumer API is not touched (Decision 266). No new job, table or status.

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

select pg_temp.edit_n('public.admin_entry_requirements(text,jsonb)', '961150b37ec7c752b10bffbd18c39ed0', array[
  array[$o$'levels', (select coalesce(jsonb_agg(distinct m.level_label), '[]'::jsonb) from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.level_label is not null),$o$,
        $n$'levels', (select coalesce(jsonb_agg(distinct m.level_label), '[]'::jsonb) from catalogue.provider_entry_matrix m where m.provider_id = v_pid and m.level_label is not null),
      -- AER programme (29 Oct 2026): the provider's sources and each one's latest read, holds included (at most 50; fixed: a page of sources)
      'sources_total', (select count(*) from pipeline.entry_matrix_sources s where s.provider_id = v_pid),
      'sources', (select coalesce(jsonb_agg(z.x order by z.o, z.u), '[]'::jsonb) from (
        select case s.status when 'read' then 1 when 'found' then 2 when 'reading' then 2 else 3 end o, s.url u,
               jsonb_build_object('id', s.id, 'url', s.url, 'title', s.title, 'status', s.status, 'read_via', s.read_via, 'http', s.http_status,
                 'error', s.error, 'attempts', s.attempts, 'read_at', s.read_at,
                 'run', (select jsonb_build_object('state', r.state, 'rows', r.rows_admitted, 'not_kept', r.rows_dropped, 'error', r.error, 'cost_usd', r.cost_usd,
                                 'done_at', r.done_at, 'basis', r.result->>'page_basis',
                                 'review_status', (select li.status from pipeline.layer4_review_items li where li.id = r.review_item_id))
                           from pipeline.entry_matrix_runs r where r.source_id = s.id order by r.updated_at desc limit 1)) x
          from pipeline.entry_matrix_sources s where s.provider_id = v_pid order by 1, 2 limit 50) z),$n$]], array[1]);
