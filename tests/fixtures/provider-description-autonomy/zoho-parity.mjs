// Guards: Provider Description mandate §8–9: actual Zoho provider payload/cache schema; unrelated contact/import rows remain empty.
import fs from 'node:fs'
const m=JSON.parse(fs.readFileSync(new URL('./production-zoho.json',import.meta.url))), e=JSON.parse(fs.readFileSync(new URL('./production-zoho-external-keys.json',import.meta.url)))
const q=s=>"'"+String(s).replaceAll("'","''")+"'", id=s=>'"'+String(s).replaceAll('"','""')+'"'
console.log("create schema if not exists extensions; create or replace function extensions.gen_random_uuid() returns uuid language sql volatile as 'select pg_catalog.gen_random_uuid()';")
for(const seq of m.sequences||[])console.log(`create sequence if not exists ${seq.schema}.${seq.name} as ${seq.data_type} increment ${seq.increment_by} minvalue ${seq.min_value} maxvalue ${seq.max_value} start ${seq.start_value} cache ${seq.cache_size} ${seq.cycle?'cycle':'no cycle'};`)
for(const rel of new Set([...m.columns,...e.columns].map(c=>`${c.table_schema}.${c.table_name}`)))console.log(`create table if not exists ${rel} ();`)
for(const c of [...m.columns,...e.columns]){
 const rel=`${c.table_schema}.${c.table_name}`
 console.log(`alter table ${rel} add column if not exists ${id(c.column_name)} ${c.udt_name};`)
 if(c.column_default)console.log(`alter table ${rel} alter column ${id(c.column_name)} set default ${c.column_default};`)
 console.log(`alter table ${rel} alter column ${id(c.column_name)} ${c.is_nullable==='NO'?'set':'drop'} not null;`)
}
for(const c of [...m.constraints,...e.constraints].sort((a,b)=>(a.type==='f')-(b.type==='f'))){
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(c.relation)}::regclass and conname=${q(c.name)}) then alter table ${c.relation} add constraint ${c.name} ${c.definition}; end if; if not exists(select 1 from pg_constraint where conrelid=${q(c.relation)}::regclass and conname=${q(c.name)} and pg_get_constraintdef(oid)=${q(c.definition)}) then raise exception 'Zoho provider parity: ${c.name}'; end if; end $p$;`)
}
for(const i of m.indexes)console.log(i.indexdef.replace(/CREATE (UNIQUE )?INDEX /,(_,u)=>`CREATE ${u||''}INDEX IF NOT EXISTS `)+';')
for(const r of m.rls)console.log(`alter table ${r.relation} ${r.enabled?'enable':'disable'} row level security;`)
for(const p of m.policies||[])console.log(`drop policy if exists ${id(p.policyname)} on ${p.schemaname}.${p.tablename}; create policy ${id(p.policyname)} on ${p.schemaname}.${p.tablename} ${p.permissive==='RESTRICTIVE'?'as restrictive':''} for ${p.cmd} to ${p.roles.map(id).join(',')}${p.qual?' using('+p.qual+')':''}${p.with_check?' with check('+p.with_check+')':''};`)
