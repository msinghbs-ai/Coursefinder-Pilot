-- Guards: Platform Admin mandate 5 Nov 2026 17:31, Course Catalogue columns: production-schema parity of the fixture.
-- One fingerprint of every table the change reads or writes: columns (type, not null), constraints (foreign keys only between
-- fixture tables, the others listed by name), indexes, triggers, RLS, policies and grants to anon/authenticated. The same query
-- runs read-only on production; the runner compares the two digests table by table.
with t(rel) as (select unnest(string_to_array(:'tables', ',')::regclass[])),
cols as (
  select a.attrelid::regclass::text rel, string_agg(a.attname||' '||format_type(a.atttypid,a.atttypmod)||case when a.attnotnull then ' nn' else '' end, ', ' order by a.attname collate "C") d
  from pg_attribute a join t on t.rel=a.attrelid where a.attnum>0 and not a.attisdropped group by 1),
cons as (
  select c.conrelid::regclass::text rel, string_agg(case when c.contype='f' and not exists(select 1 from t where t.rel=c.confrelid) then 'fk-outside '||c.confrelid::regclass::text||' '||pg_get_constraintdef(c.oid) else pg_get_constraintdef(c.oid) end, ' | ' order by c.conname collate "C") d
  from pg_constraint c join t on t.rel=c.conrelid where c.contype in ('p','u','c','f','x') group by 1),
idx as (
  select i.indrelid::regclass::text rel, string_agg(regexp_replace(pg_get_indexdef(i.indexrelid),' INDEX \S+ ON ',' INDEX ON '), ' | ' order by regexp_replace(pg_get_indexdef(i.indexrelid),' INDEX \S+ ON ',' INDEX ON ') collate "C") d
  from pg_index i join t on t.rel=i.indrelid group by 1),
trg as (
  select g.tgrelid::regclass::text rel, string_agg(g.tgname||':'||g.tgtype::text||':'||g.tgfoid::regproc::text, ' | ' order by g.tgname collate "C", g.tgtype) d
  from pg_trigger g join t on t.rel=g.tgrelid where not g.tgisinternal group by 1),
pol as (
  select p.polrelid::regclass::text rel, string_agg(p.polname||':'||p.polcmd::text||':'||coalesce(pg_get_expr(p.polqual,p.polrelid),'')||':'||coalesce(pg_get_expr(p.polwithcheck,p.polrelid),''), ' | ' order by p.polname collate "C") d
  from pg_policy p join t on t.rel=p.polrelid group by 1),
gr as (
  select (table_schema||'.'||table_name)::regclass::text rel, string_agg(grantee||':'||privilege_type, ',' order by grantee||':'||privilege_type collate "C") d
  from information_schema.role_table_grants g where grantee in ('anon','authenticated') and (table_schema||'.'||table_name)::regclass in (select rel from t) group by 1)
select string_agg(t.rel::regclass::text||' '||md5(concat_ws(' || ', c.d, k.d, i.d, g2.d, p.d, gr.d, (select relrowsecurity::text from pg_class where oid=t.rel))), E'\n' order by t.rel::regclass::text collate "C")
from t left join cols c on c.rel=t.rel::regclass::text left join cons k on k.rel=t.rel::regclass::text left join idx i on i.rel=t.rel::regclass::text
left join trg g2 on g2.rel=t.rel::regclass::text left join pol p on p.rel=t.rel::regclass::text left join gr on gr.rel=t.rel::regclass::text;
