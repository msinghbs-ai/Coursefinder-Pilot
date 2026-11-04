// Guards: Provider Description mandate §6 and §8: actual provider registration references and schema.
import fs from 'node:fs'
const m=JSON.parse(fs.readFileSync(new URL('./production-registrations.json',import.meta.url)))
const q=s=>"'"+String(s).replaceAll("'","''")+"'"
console.log('create table if not exists catalogue.provider_registrations ();')
for(const c of m.columns){
 console.log(`alter table catalogue.provider_registrations add column if not exists ${c.column_name} ${c.udt_name};`)
 if(c.column_default)console.log(`alter table catalogue.provider_registrations alter column ${c.column_name} set default ${c.column_default};`)
 console.log(`alter table catalogue.provider_registrations alter column ${c.column_name} ${c.is_nullable==='NO'?'set':'drop'} not null;`)
}
for(const c of m.constraints)console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid='catalogue.provider_registrations'::regclass and conname=${q(c.name)}) then alter table catalogue.provider_registrations add constraint ${c.name} ${c.definition}; end if; if not exists(select 1 from pg_constraint where conrelid='catalogue.provider_registrations'::regclass and conname=${q(c.name)} and pg_get_constraintdef(oid)=${q(c.definition)}) then raise exception 'registration constraint parity: ${c.name}'; end if; end $p$;`)
for(const i of m.indexes)console.log(i.indexdef.replace(/CREATE (UNIQUE )?INDEX /,(_,u)=>`CREATE ${u||''}INDEX IF NOT EXISTS `)+';')
console.log(`alter table catalogue.provider_registrations ${m.rls.enabled?'enable':'disable'} row level security;`)
for(const p of m.policies||[])console.log(`create policy ${p.policyname} on catalogue.provider_registrations ${p.permissive==='RESTRICTIVE'?'as restrictive':''} for ${p.cmd} to ${p.roles.map(q).join(',')}${p.qual?' using('+p.qual+')':''}${p.with_check?' with check('+p.with_check+')':''};`)
