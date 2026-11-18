-- CF-247 (23 Oct 2026, first hour of the AI reader for every attribute). From 11:25 every enrich_ai worker call failed with
-- "svc_enrich_ai_record: canceling statement due to statement timeout" (8 s for a worker call): each English or intakes value admitted
-- refreshed that course's search document on its own, inside the call that records 30 readings. The per-value refresh is removed;
-- instead one search refresh request is left open (job search-refresh-requested takes it within 10 minutes). Leased items left by
-- the failed calls go back to the AI queue.
-- Replaces: nothing (security.enrich_apply_v1 edited in place, md5-guarded)
-- Retires: nothing
create or replace function pg_temp.edit_once(p_sig text, p_md5 text, p_edits text[][]) returns void language plpgsql as $f$
declare v_def text := pg_get_functiondef(p_sig::regprocedure); i int;
begin
  if md5(v_def) <> p_md5 then raise exception 'live % differs from the definition this change edits (md5 %)', p_sig, md5(v_def); end if;
  for i in 1 .. array_length(p_edits, 1) loop
    if (length(v_def) - length(replace(v_def, p_edits[i][1], ''))) / length(p_edits[i][1]) <> 1 then raise exception '%: edit % must apply exactly once', p_sig, i; end if;
    v_def := replace(v_def, p_edits[i][1], p_edits[i][2]);
  end loop;
  execute v_def;
end $f$;

select pg_temp.edit_once('security.enrich_apply_v1(bigint)', 'b68fe542cd877eec1589e6a496690704', array[
  array[$o$      perform search.refresh_course_enrichment_scoped_v1(array[i.course_id], true);
$o$, $n$      -- 23 Oct 2026 11:25: no per-value search refresh (it ran past the worker call's time limit); one open request instead
      insert into search.refresh_requests(requested_by) select 'AI reader (English, intakes)'
       where not exists (select 1 from search.refresh_requests q where q.processed_at is null and q.requested_by = 'AI reader (English, intakes)');
$n$]]);

update pipeline.field_enrich_items set state = 'ai', leased_until = null, updated_at = now()
 where state = 'leased' and leased_until < now() and attempts < 3 and field in ('english', 'intakes', 'campus', 'campus_region', 'duration', 'delivery', 'international', 'level', 'field_of_study');

select 'enrich apply without per-value refresh' ok;
