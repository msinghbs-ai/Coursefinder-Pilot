-- CF-247 SP-1.1 (26 Oct 2026, 04:00 checkpoint). SP-1 capped new first runs per hourly run (bind.no_page_first_runs_per_run, 10)
-- but not the number waiting: the job opened 10 a run while none was decided, 50 pending by 04:00 and rising toward about 177
-- (one per provider and kind). That is the Layer 4 flood the design promised to avoid. A new first run now opens only while fewer than
-- bind.no_page_pending_max (60) first runs are waiting for a person; universities still come first.
-- Replaces: nothing (security.no_page_propose_v1 edited in place, md5-guarded)
-- Retires: nothing
-- Nothing dropped or deleted. The consumer API is not touched.

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

insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by, reason) values
 ('pipeline', 'bind.no_page_pending_max', 'No page published: first runs waiting at most', 'A new Layer 4 first run (no page or conjoint) opens only while fewer than this many are waiting for a person.', 'number', '60'::jsonb, 5, 500, 'first runs', 798, 'Course page search', 'security.no_page_propose_v1', 'CF-247 SP-1.1, 26 Oct 2026 04:00 checkpoint')
on conflict (toolset_key, key) do nothing;

select pg_temp.edit_n('security.no_page_propose_v1()', '0b68723d5dd0fe1872c201ca4003969a', array[
  array[$o$    if (v_first + v_conj) >= security.pipeline_num_v1('bind.no_page_first_runs_per_run', 10)$o$,
        $n$    if ((v_first + v_conj) >= security.pipeline_num_v1('bind.no_page_first_runs_per_run', 10)
        or (select count(*) from pipeline.layer4_review_items li where li.status = 'pending' and li.field_code in ('no_page_first_run', 'conjoint_rule_first_run'))
           >= security.pipeline_num_v1('bind.no_page_pending_max', 60))  -- SP-1.1: never more than this many waiting for a person$n$]], array[1]);
