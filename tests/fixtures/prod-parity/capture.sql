-- Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026): production-representative constraints, grants, RLS, triggers and function signatures.
-- Production-parity capture query (read only). Do not run this file directly: `node scripts/prod-parity-capture.mjs capture-sql ...`
-- fills {{SCOPE}} and {{LOOKUP_ROWS}} and prints one SELECT. Run it through mcp__Supabase__execute_sql (project fxcwkweaxjtknorudmwp only,
-- outside the load policy's forbidden minutes) or psql, and save the single "manifest" value as JSON.
-- It reads only pg_catalog plus the explicitly named lookup tables (code values; refused if a column looks like personal data).
-- pg_get_functiondef and format_type print names relative to the session search_path, so the manifest records it and the fixture sets it.
with scope as (select {{SCOPE}}::jsonb s),
personal(p) as (select {{PERSONAL}}::text),
tin as (select x fq from scope, jsonb_array_elements_text(s->'tables') x),
lin as (select x fq from scope, jsonb_array_elements_text(s->'lookups') x),
fin as (select x f from scope, jsonb_array_elements_text(s->'functions') x),
t0 as (
  select c.oid, n.nspname || '.' || c.relname fq, 'target' kind from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname || '.' || c.relname in (select fq from tin) and c.relkind in ('r', 'p')
  union
  select c.oid, n.nspname || '.' || c.relname, 'lookup' from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname || '.' || c.relname in (select fq from lin) and n.nspname || '.' || c.relname not in (select fq from tin) and c.relkind in ('r', 'p')),
tr as (
  select * from t0
  union
  select distinct k.confrelid, n.nspname || '.' || c.relname, 'referenced' from pg_constraint k join pg_class c on c.oid = k.confrelid
    join pg_namespace n on n.oid = c.relnamespace
   where k.contype = 'f' and k.conrelid in (select oid from t0 where kind = 'target') and k.confrelid not in (select oid from t0)),
keycols as (
  select k.conrelid oid, a.attname from pg_constraint k join pg_attribute a on a.attrelid = k.conrelid and a.attnum = any(k.conkey)
   where k.contype in ('p', 'u') and k.conrelid in (select oid from tr where kind = 'referenced')),
cols as (
  select tr.fq, tr.kind, a.attnum, a.attname, format_type(a.atttypid, a.atttypmod) typ, a.atttypid, a.attnotnull,
         case when tr.kind = 'target' then pg_get_expr(d.adbin, d.adrelid) end def, a.attidentity::text attidentity, a.attgenerated::text attgenerated
    from tr join pg_attribute a on a.attrelid = tr.oid and a.attnum > 0 and not a.attisdropped
    left join pg_attrdef d on d.adrelid = a.attrelid and d.adnum = a.attnum
   where tr.kind <> 'referenced' or (tr.oid, a.attname) in (select oid, attname from keycols)),
cons as (
  select tr.fq, k.conname, k.contype::text contype, pg_get_constraintdef(k.oid) def
    from tr join pg_constraint k on k.conrelid = tr.oid
   where tr.kind = 'target' or k.contype in ('p', 'u')),
idx as (
  select tr.fq, ic.relname iname, pg_get_indexdef(i.indexrelid) def
    from tr join pg_index i on i.indrelid = tr.oid join pg_class ic on ic.oid = i.indexrelid
   where tr.kind = 'target' and not exists (select 1 from pg_constraint k where k.conindid = i.indexrelid and k.conrelid = tr.oid)),
trg as (
  select tr.fq, g.tgname, pg_get_triggerdef(g.oid) def, g.tgenabled::text enabled, g.tgfoid
    from tr join pg_trigger g on g.tgrelid = tr.oid and not g.tgisinternal where tr.kind = 'target'),
pol as (
  select tr.fq, p.polname, p.polpermissive, p.polcmd::text cmd,
         (select array_agg(case r when 0 then 'public' else pg_get_userbyid(r) end order by 1) from unnest(p.polroles) r) roles,
         pg_get_expr(p.polqual, p.polrelid) qual, pg_get_expr(p.polwithcheck, p.polrelid) wcheck
    from tr join pg_policy p on p.polrelid = tr.oid where tr.kind = 'target'),
tgr as (
  select tr.fq, case a.grantee when 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end grantee,
         string_agg(a.privilege_type || case when a.is_grantable then '*' else '' end, ',' order by a.privilege_type) privs
    from tr join pg_class c on c.oid = tr.oid, aclexplode(coalesce(c.relacl, acldefault('r', c.relowner))) a
   where tr.kind = 'target' and a.grantee <> c.relowner group by 1, 2),
fsel as (
  select p.oid, 'target' kind from pg_proc p where p.oid in (select to_regprocedure(f) from fin where f like '%(%')
  union
  select p.oid, 'target' from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname || '.' || p.proname in (select f from fin where f not like '%(%')
  union
  select g.tgfoid, 'trigger' from trg g
  union
  -- functions a target table needs outside pg_catalog: trigger WHEN clauses, defaults, check constraints and policies
  select d.refobjid, 'dependency' from pg_depend d join pg_proc p on p.oid = d.refobjid join pg_namespace n on n.oid = p.pronamespace
   where d.refclassid = 'pg_proc'::regclass and n.nspname not in ('pg_catalog', 'information_schema', 'extensions')
     and ((d.classid = 'pg_trigger'::regclass and d.objid in (select g.oid from pg_trigger g join tr on tr.oid = g.tgrelid and tr.kind = 'target'))
       or (d.classid = 'pg_attrdef'::regclass and d.objid in (select a.oid from pg_attrdef a join tr on tr.oid = a.adrelid and tr.kind = 'target'))
       or (d.classid = 'pg_constraint'::regclass and d.objid in (select k.oid from pg_constraint k join tr on tr.oid = k.conrelid and tr.kind = 'target'))
       or (d.classid = 'pg_policy'::regclass and d.objid in (select y.oid from pg_policy y join tr on tr.oid = y.polrelid and tr.kind = 'target')))),
fsel1 as (select oid, (array_agg(kind order by case kind when 'target' then 0 when 'trigger' then 1 else 2 end))[1] kind from fsel group by oid),
fns as (
  select p.oid::regprocedure::text sig, f.kind, md5(pg_get_functiondef(p.oid)) md5, pg_get_functiondef(p.oid) def, p.prokind::text prokind,
         (select string_agg(case a.grantee when 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end, ',' order by 1)
            from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee <> p.proowner) execs
    from fsel1 f join pg_proc p on p.oid = f.oid),
typs as (
  select distinct t.oid, format_type(t.oid, null) name, t.typtype::text typtype from cols c join pg_type t0 on t0.oid = c.atttypid
    join pg_type t on t.oid = case when t0.typcategory = 'A' then t0.typelem else t0.oid end
    join pg_namespace n on n.oid = t.typnamespace
   where t.typtype in ('e', 'd') and n.nspname not in ('pg_catalog', 'information_schema')),
typ as (
  select y.name, y.typtype,
         case when y.typtype = 'e' then (select jsonb_agg(e.enumlabel order by e.enumsortorder) from pg_enum e where e.enumtypid = y.oid) end labels,
         case when y.typtype = 'd' then (select format_type(t.typbasetype, t.typtypmod) from pg_type t where t.oid = y.oid) end base,
         case when y.typtype = 'd' then (select jsonb_agg(pg_get_constraintdef(k.oid) order by k.conname) from pg_constraint k where k.contypid = y.oid) end checks
    from typs y),
roles as (
  -- the effective time-outs: a setting for this database wins over the role-wide one
  select r.rolname, (select string_agg(x, ',' order by x) from (
                       select distinct on (split_part(x, '=', 1)) x from pg_db_role_setting s, unnest(s.setconfig) x
                        where s.setrole = r.oid and s.setdatabase in (0, (select oid from pg_database where datname = current_database()))
                          and split_part(x, '=', 1) in ('statement_timeout', 'lock_timeout', 'idle_in_transaction_session_timeout')
                        order by split_part(x, '=', 1), s.setdatabase desc) e) settings
    from pg_roles r where r.rolname in ('anon', 'authenticated', 'authenticator', 'service_role')),
nsp as (
  select n.nspname, case a.grantee when 0 then 'PUBLIC' else pg_get_userbyid(a.grantee) end grantee,
         string_agg(a.privilege_type || case when a.is_grantable then '*' else '' end, ',' order by a.privilege_type) privs
    from pg_namespace n, aclexplode(coalesce(n.nspacl, acldefault('n', n.nspowner))) a
   where a.grantee <> n.nspowner
     and n.nspname in (select split_part(fq, '.', 1) from tr union select n2.nspname from fns join pg_proc p on p.oid::regprocedure::text = fns.sig join pg_namespace n2 on n2.oid = p.pronamespace)
   group by 1, 2),
lk(fq, refused, rows) as (select null::text, null::text, null::jsonb where false {{LOOKUP_ROWS}}),
missing as (
  select 'table ' || fq m from tin where fq not in (select fq from tr) union all
  select 'lookup ' || fq from lin where fq not in (select fq from tr) union all
  select 'function ' || f from fin where (f like '%(%' and to_regprocedure(f) is null)
     or (f not like '%(%' and not exists (select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname || '.' || p.proname = f))),
facts(k, v) as (
  select 'session|search_path', current_setting('search_path') union all
  select 'table|' || tr.fq, tr.kind || '|' || c.relkind::text || '|rls=' || c.relrowsecurity || '|force=' || c.relforcerowsecurity
    from tr join pg_class c on c.oid = tr.oid union all
  select 'column|' || fq || '|' || attname, typ || '|notnull=' || attnotnull || '|default=' || coalesce(def, '') || '|identity=' || attidentity || '|generated=' || attgenerated from cols union all
  select 'constraint|' || fq || '|' || conname, contype || '|' || def from cons union all
  select 'index|' || fq || '|' || iname, def from idx union all
  select 'trigger|' || fq || '|' || tgname, def || '|enabled=' || enabled from trg union all
  select 'policy|' || fq || '|' || polname, case when polpermissive then 'permissive' else 'restrictive' end || '|' || cmd || '|' || array_to_string(roles, ',')
         || '|using=' || coalesce(qual, '') || '|check=' || coalesce(wcheck, '') from pol union all
  select 'grant|' || fq || '|' || grantee, privs from tgr union all
  select 'function|' || sig, md5 || '|' || kind from fns union all
  select 'execute|' || sig, coalesce(execs, '') from fns union all
  select 'type|' || name, typtype || '|' || coalesce(labels::text, '') || coalesce(base, '') || '|' || coalesce(checks::text, '') from typ union all
  select 'schema|' || nspname || '|' || grantee, privs from nsp union all
  select 'role|' || rolname, coalesce(settings, '') from roles union all
  select 'lookup_rows|' || fq, coalesce(refused, jsonb_array_length(rows) || '|' || md5(rows::text)) from lk union all
  select 'missing|' || m, 'missing' from missing)
select jsonb_build_object(
  'tool', 'prod-parity-capture v1',
  'server_version_num', current_setting('server_version_num')::int,
  'search_path', current_setting('search_path'),
  'scope', (select s from scope),
  'tables', coalesce((select jsonb_agg(jsonb_build_object(
      'fq', tr.fq, 'kind', tr.kind, 'relkind', c.relkind::text, 'rls', c.relrowsecurity, 'force_rls', c.relforcerowsecurity,
      'columns', (select coalesce(jsonb_agg(jsonb_build_object('name', attname, 'type', typ, 'not_null', attnotnull, 'default', def,
                    'identity', nullif(attidentity, ''), 'generated', nullif(attgenerated, '')) order by attnum), '[]') from cols where cols.fq = tr.fq),
      'constraints', (select coalesce(jsonb_agg(jsonb_build_object('name', conname, 'type', contype, 'def', def) order by contype, conname), '[]') from cons where cons.fq = tr.fq),
      'indexes', (select coalesce(jsonb_agg(jsonb_build_object('name', iname, 'def', def) order by iname), '[]') from idx where idx.fq = tr.fq),
      'triggers', (select coalesce(jsonb_agg(jsonb_build_object('name', tgname, 'def', def, 'enabled', enabled, 'function', tgfoid::regprocedure::text) order by tgname), '[]') from trg where trg.fq = tr.fq),
      'policies', (select coalesce(jsonb_agg(jsonb_build_object('name', polname, 'permissive', polpermissive, 'cmd', cmd, 'roles', roles, 'using', qual, 'check', wcheck) order by polname), '[]') from pol where pol.fq = tr.fq),
      'grants', (select coalesce(jsonb_agg(jsonb_build_object('grantee', grantee, 'privileges', privs) order by grantee), '[]') from tgr where tgr.fq = tr.fq),
      'rows', (select rows from lk where lk.fq = tr.fq), 'refused', (select refused from lk where lk.fq = tr.fq))
      order by case tr.kind when 'lookup' then 0 when 'referenced' then 1 else 2 end, tr.fq) from tr join pg_class c on c.oid = tr.oid), '[]'),
  'functions', coalesce((select jsonb_agg(jsonb_build_object('sig', sig, 'kind', kind, 'prokind', prokind, 'md5', md5, 'execute', coalesce(execs, ''), 'def', def) order by kind desc, sig) from fns), '[]'),
  'types', coalesce((select jsonb_agg(jsonb_build_object('name', name, 'typtype', typtype, 'labels', labels, 'base', base, 'checks', checks) order by name) from typ), '[]'),
  'schemas', coalesce((select jsonb_agg(jsonb_build_object('name', nspname, 'grantee', grantee, 'privileges', privs) order by nspname, grantee) from nsp), '[]'),
  'roles', coalesce((select jsonb_agg(jsonb_build_object('name', rolname, 'settings', settings) order by rolname) from roles), '[]'),
  'missing', coalesce((select jsonb_agg(m order by m) from missing), '[]'),
  'facts', (select jsonb_object_agg(k, v) from facts)) as manifest
