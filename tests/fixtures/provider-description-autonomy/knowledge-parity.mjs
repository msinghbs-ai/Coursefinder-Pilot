// Guards: Provider Description mandate §8 and §10: exact existing recovery knowledge schema and contracts, metadata only.
import fs from 'node:fs'
const m=JSON.parse(fs.readFileSync(new URL('./production-knowledge.json',import.meta.url)))
const q=s=>"'"+String(s).replaceAll("'","''")+"'", id=s=>'"'+String(s).replaceAll('"','""')+'"'
for(const table of ['ops_remedies','ops_remedy_knowledge','ops_remedy_runs','ops_remedy_outcomes']) {
 console.log(`create table if not exists pipeline.${table} ();`)
 for(const c of m.columns.filter(c=>c.table_name===table)) {
  if(c.column_default?.includes('nextval(')){
   const seq=c.column_default.match(/nextval\('([^']+)'/)[1]
   console.log(`create sequence if not exists ${seq};`)
  }
  console.log(`alter table pipeline.${table} add column if not exists ${id(c.column_name)} ${c.udt_name};`)
  if(c.column_default)console.log(`alter table pipeline.${table} alter column ${id(c.column_name)} set default ${c.column_default};`)
  console.log(`alter table pipeline.${table} alter column ${id(c.column_name)} ${c.is_nullable==='NO'?'set':'drop'} not null;`)
 }
}
for(const c of [...m.constraints].sort((a,b)=>(a.type==='f')-(b.type==='f'))){
 const rel=`${c.schema}.${c.table}`
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(rel)}::regclass and conname=${q(c.name)}) then alter table ${rel} add constraint ${c.name} ${c.definition}; end if; if not exists(select 1 from pg_constraint where conrelid=${q(rel)}::regclass and conname=${q(c.name)} and pg_get_constraintdef(oid)=${q(c.definition)}) then raise exception 'recovery knowledge constraint drift: ${c.name}'; end if; end $p$;`)
}
for(const i of m.indexes)console.log(i.indexdef.replace(/CREATE (UNIQUE )?INDEX /,(_,u)=>`CREATE ${u||''}INDEX IF NOT EXISTS `)+';')
for(const r of m.rls)console.log(`alter table pipeline.${r.table} ${r.enabled?'enable':'disable'} row level security; revoke all on pipeline.${r.table} from public,anon,authenticated;`)
for(const p of m.policies||[])throw new Error('Unexpected recovery knowledge policy needs exact reconstruction: '+p.policyname)
