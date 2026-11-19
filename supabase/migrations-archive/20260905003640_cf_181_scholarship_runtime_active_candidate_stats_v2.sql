do $$
declare d text;
begin
 select pg_get_functiondef(p.oid) into d from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='security' and p.proname='admin_scholarship_runtime_read';
 d:=replace(d,'and d.classification = ''detail_ready''::text','and d.status = ''discovered''::text and d.classification = ''detail_ready''::text');
 d:=replace(d,'and d.classification = ''needs_review''::text','and d.status = ''discovered''::text and d.classification = ''needs_review''::text');
 execute d;
end $$;
comment on function security.admin_scholarship_runtime_read(jsonb) is 'CF-181 active Scholarship runtime statistics: detail_ready and needs_review count only status=discovered candidates; historical acquired/superseded classifications remain auditable but do not inflate executable queue metrics.';
