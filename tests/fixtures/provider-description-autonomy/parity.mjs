// Guards: 4 Nov 2026 Provider Description mandate §8: production schema, no production data.
import fs from 'node:fs'
const root='tests/fixtures/provider-description-autonomy/'
const m=JSON.parse(fs.readFileSync(root+'production-metadata.json'))
const p=JSON.parse(fs.readFileSync(root+'production-parity.json'))
const q=s=>"'"+String(s).replaceAll("'","''")+"'"
console.log(`create schema if not exists pim; create schema if not exists integration;
create table pim.entity_registry(id uuid primary key); create table ref.subdivisions(id uuid primary key);
create table integration.systems(id uuid primary key);
create table pipeline.layer2_source_profile_versions(id uuid primary key);
create table pipeline.jobs(id uuid primary key,source_profile_version_id uuid);
create table pipeline.layer4_course_field_resolutions(id uuid primary key);
`)
for(const t of ['admin_jobs','admin_job_kinds','ops_outcome_codes']){
 const cs=m.columns.filter(c=>c.table_schema==='pipeline'&&c.table_name===t)
 console.log(`create table if not exists pipeline.${t} (${cs.map(c=>`${c.column_name} ${c.udt_name}${c.column_default?' default '+c.column_default:''}${c.is_nullable==='NO'?' not null':''}`).join(',')});`)
}
for(const c of m.columns){
 const table=`${c.table_schema}.${c.table_name}`
 console.log(`alter table ${table} add column if not exists ${c.column_name} ${c.udt_name};`)
 console.log(`do $type$ begin if exists(select 1 from information_schema.columns where table_schema=${q(c.table_schema)} and table_name=${q(c.table_name)} and column_name=${q(c.column_name)} and udt_name<>${q(c.udt_name)}) then alter table ${table} alter column ${c.column_name} type ${c.udt_name}; end if; end $type$;`)
 console.log(`alter table ${table} alter column ${c.column_name} ${c.column_default?'set default '+c.column_default:'drop default'};`)
 console.log(`alter table ${table} alter column ${c.column_name} ${c.is_nullable==='NO'?'set':'drop'} not null;`)
}
for(const o of m.outcomes)console.log(`insert into pipeline.ops_outcome_codes(code,title,counts_as_movement) values(${q(o.code)},${q(o.title)},${o.counts_as_movement});`)
for(const o of m.job_kinds)console.log(`insert into pipeline.admin_job_kinds(kind,label,what,can_pause,added_in) values(${q(o.kind)},${q(o.label)},${q(o.what)},${o.can_pause},${q(o.added_in)});`)
console.log('alter table pipeline.ops_outcome_codes add primary key(code); alter table pipeline.admin_job_kinds add primary key(kind);')
for(const c of p.constraints){
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(c.relation)}::regclass and conname=${q(c.conname)}) then alter table ${c.relation} add constraint ${c.conname} ${c.definition}; end if; end $p$;`)
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(c.relation)}::regclass and conname=${q(c.conname)} and pg_get_constraintdef(oid,true)=${q(c.definition)}) then raise exception 'constraint parity failed: ${c.conname}'; end if; end $p$;`)
}
for(const s of [...m.settings,...JSON.parse(fs.readFileSync(root+'production-layer4-settings.json')),...JSON.parse(fs.readFileSync(root+'production-reader-limits.json'))])console.log(`insert into pipeline.platform_toolset_settings(toolset_key,key,kind,value) values (${q(s.toolset_key)},${q(s.key)},${q(s.kind)},${q(JSON.stringify(s.value))}::jsonb) on conflict(toolset_key,key) do update set value=excluded.value;`)
for(const r of p.rls)console.log(`alter table ${r.relation} ${r.relrowsecurity?'enable':'disable'} row level security;`)
console.log("alter role authenticated set statement_timeout='8s'; alter role anon set statement_timeout='3s';")
