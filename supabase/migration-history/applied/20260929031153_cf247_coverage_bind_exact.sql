-- CF-247 coverage binding: an exact word-for-word match between the course title and a page (score 1.0) that is
-- unique on both sides is bound even when a near page scores within 0.1 (pilot: "Master of Sport Management" 1.0
-- against 0.857 was left ambiguous). The page is still identity-checked when read. Checksum-guarded.
do $patch$
declare v_def text; v_old text; v_new text;
begin
  if (select md5(prosrc) from pg_proc where oid='security.coverage_bind_v2(uuid)'::regprocedure)<>'5ec8c7dacc81015248be32677e566c08' then
    raise exception 'security.coverage_bind_v2 changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('security.coverage_bind_v2(uuid)'::regprocedure);
  v_old:='by_code or (sc>=0.8 and sc-coalesce(nxt_c,0)>=0.1 and rk_u=1 and sc-coalesce(nxt_u,0)>=0.1) mutual';
  v_new:='by_code or (sc>=0.8 and sc-coalesce(nxt_c,0)>=0.1 and rk_u=1 and sc-coalesce(nxt_u,0)>=0.1)'
       ||' or (sc>=0.999 and coalesce(nxt_c,0)<0.999 and rk_u=1 and coalesce(nxt_u,0)<0.999) mutual';
  if (length(v_def)-length(replace(v_def,v_old,'')))/length(v_old)<>1 then raise exception 'rule anchor not found exactly once'; end if;
  execute replace(v_def,v_old,v_new);
end $patch$;
update pipeline.coverage_provider_discovery set bound_at=null where mapped_at is not null;
