do $p$
declare v text;
begin
  v:=pg_get_functiondef('public.svc_coverage_tuition_handoff_record(uuid,text,text,int)'::regprocedure);
  if position($o$'coverage-sweep-text-v1', 'coverage:'$o$ in v)=0 then raise exception 'anchor not found'; end if;
  v:=replace(v,$o$'coverage-sweep-text-v1', 'coverage:'$o$,$n$1, 'coverage:'$n$);
  v:=replace(v,$o$'decision','Decision 163 Option A'),$o$,$n$'decision','Decision 163 Option A','capture','coverage-sweep-text-v1'),$n$);
  execute v;
end $p$;
update pipeline.coverage_course_pages set l3_handoff_at=null where l3_handoff_at>now()-interval '30 minutes' and l3_work_item_id is null;
