do $patch$
declare d text; n text;
begin
  d:=pg_get_functiondef('security.evidence_storage_dedupe_v1(text,boolean)'::regprocedure);
  if md5(d)<>'b748100227c68629580be364ececdb2a' then raise exception 'evidence_storage_dedupe_v1 changed since review (%); not patched', md5(d); end if;
  n:=replace(d,$a$if p_scope not in ('layer1') then$a$,$a$if p_scope not in ('layer1','layer2') then$a$);
  n:=replace(n,$a$and s.provider_id is null and e.evidence_type='regulatory_snapshot';$a$,
    $a$and ((p_scope='layer1' and s.provider_id is null and e.evidence_type='regulatory_snapshot')
       or (p_scope='layer2' and s.provider_id is not null and e.evidence_type in ('layer2_screenshot','layer2_html_snapshot')));$a$);
  if n=d or (length(n)-length(d))<100 then raise exception 'patch points not found'; end if;
  execute n;
end $patch$;
