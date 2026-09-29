-- CF-247 coverage sweep: read bound pages before ambiguous ones (pilot: 21 of 32 ambiguous best candidates were the
-- wrong page). Within a provider, bound pages come first; across providers, bound pages come first. Checksum-guarded.
do $patch$
declare v_def text;
begin
  if (select md5(prosrc) from pg_proc where oid='public.svc_coverage_read_next(int)'::regprocedure)<>'2d0b6174049a8a4e62c4b9123156a1dc' then
    raise exception 'svc_coverage_read_next changed since review; not replaced'; end if;
  v_def:=pg_get_functiondef('public.svc_coverage_read_next(int)'::regprocedure);
  v_def:=replace(v_def,'select p.course_id, p.provider_id, row_number() over (partition by p.provider_id order by p.next_read_at) rk',
                       'select p.course_id, p.provider_id, p.status st, row_number() over (partition by p.provider_id order by (p.status<>''bound''), p.next_read_at) rk');
  v_def:=replace(v_def,'order by rk, random()','order by (st<>''bound''), rk, random()');
  if position('order by (st<>''bound''), rk, random()' in v_def)=0 or position('p.status st,' in v_def)=0 then raise exception 'anchors not found'; end if;
  execute v_def;
end $patch$;
