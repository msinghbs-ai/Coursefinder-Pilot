-- CF-247 readiness phase 4: permission and structure fingerprint for the 17 application schemas.
-- Run in two projects and compare: equal fp per kind means equal grants, RLS flags and policies.
with s as (select oid, nspname from pg_namespace where nspname in ('admin_api','api','catalogue','integration','l4_api','pim','pim_api','pipeline','private','public','publishing','ranking','ref','scholarship','search','security','workflow')),
acl(obj, a) as (
  select 'f:'||p.oid::regprocedure::text, coalesce((select string_agg(case when e.grantee=0 then 'PUBLIC' else e.grantee::regrole::text end||'='||e.privilege_type, ',' order by 1) from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) e), '')
    from pg_proc p join s on s.oid=p.pronamespace where p.proname <> 'rls_auto_enable'
  union all
  select 'r:'||c.relkind::text||':'||c.oid::regclass::text||':rls='||c.relrowsecurity::text||c.relforcerowsecurity::text, coalesce((select string_agg(case when e.grantee=0 then 'PUBLIC' else e.grantee::regrole::text end||'='||e.privilege_type, ',' order by 1) from aclexplode(coalesce(c.relacl, acldefault(case when c.relkind='S' then 's'::"char" else 'r'::"char" end, c.relowner))) e), '')
    from pg_class c join s on s.oid=c.relnamespace where c.relkind in ('r','p','v','m','S','f')
  union all
  select 'n:'||s.nspname::text, coalesce((select string_agg(case when e.grantee=0 then 'PUBLIC' else e.grantee::regrole::text end||'='||e.privilege_type, ',' order by 1) from aclexplode(n.nspacl) e), '')
    from pg_namespace n join s on s.oid=n.oid
  union all
  select 'c:'||a.attrelid::regclass::text||'.'||a.attname::text, (select string_agg(e.grantee::regrole::text||'='||e.privilege_type, ',' order by 1) from aclexplode(a.attacl) e)
    from pg_attribute a join pg_class c on c.oid=a.attrelid join s on s.oid=c.relnamespace where a.attacl is not null
  union all
  select 'p:'||schemaname::text||'.'||tablename::text||'.'||policyname::text, permissive||cmd||roles::text||coalesce(qual,'')||coalesce(with_check,'') from pg_policies where schemaname in (select nspname from s)
)
select left(obj,1) kind, count(*) n, md5(string_agg(obj||'|'||a, E'\n' order by obj)) fp from acl group by 1 order by 1;
