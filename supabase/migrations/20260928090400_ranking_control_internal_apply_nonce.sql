-- CF-247 / R5: allow the database to start ranking-publisher-control with a one-time nonce, so validated
-- ranking imports can be applied under the CourseFinder Automation identity (the function itself only
-- accepts 'apply' of an already validated import on this path). Checksum-guarded.
do $patch$
declare v_def text; v_md5 text;
begin
  v_def:=pg_get_functiondef('pipeline.svc_pilot_submit_nonce(text,jsonb)'::regprocedure);
  if v_def like '%''ranking-publisher-control''%' then return; end if;
  v_md5:=md5(v_def);
  if v_md5<>'bdb7080658601afe6ea8b0137941ca6b' then raise exception 'svc_pilot_submit_nonce changed (md5 %); aborting', v_md5; end if;
  if (select count(*) from regexp_matches(v_def,'''evidence-storage-dedupe'',','g'))<>1 then raise exception 'allow-list anchor not found exactly once'; end if;
  execute replace(v_def,'''evidence-storage-dedupe'',','''evidence-storage-dedupe'',''ranking-publisher-control'',');
end $patch$;
