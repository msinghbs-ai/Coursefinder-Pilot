-- CF-CHG-20260910-093
-- Exact-scope dispatch accounting must include recent governed terminal negatives.
-- They are part of the Preview-bound scope but are intentionally not queueable Layer 2 work.
-- Preserve fail-closed exact accounting: executable targets + fresh terminal negatives must
-- equal the requested Preview scope.

do $migration$
declare
  v_reg regprocedure := 'security.scheduler_workflow_run_now_v2_browser_bridge(uuid,text,text,text,uuid,text,text)'::regprocedure;
  v_def text;
  v_old text := $old$coalesce((e->>'target_count')::integer,-1)<>coalesce((e->>'requested_count')::integer,-2)$old$;
  v_new text := $new$coalesce((e->>'target_count')::integer,-1) + coalesce((e->>'fresh_terminal_negative_count')::integer,0) <> coalesce((e->>'requested_count')::integer,-2)$new$;
begin
  select pg_get_functiondef(v_reg) into v_def;
  if position(v_old in v_def)=0 then
    raise exception 'CF-093 terminal-negative exact-scope accounting patch target not found';
  end if;
  v_def:=replace(v_def,v_old,v_new);
  execute v_def;
end
$migration$;
