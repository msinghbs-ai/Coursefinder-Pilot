// Guards: Provider Description mandate §8–9: exact production evidence-lineage dependency contracts, schema and code metadata only.
import assert from 'node:assert/strict'
import fs from 'node:fs'
import { sql, quote } from './db.mjs'
const metadata=JSON.parse(fs.readFileSync(new URL('./production-lineage.json',import.meta.url)))
metadata.functions.push(JSON.parse(fs.readFileSync(new URL('./production-manual-column-guard.json',import.meta.url))))
const relations=metadata.tables.map(t=>t.schema+'.'+t.name), signatures=metadata.functions.map(f=>f.signature)
const actual=sql(`select jsonb_build_object('tables',(select jsonb_agg(jsonb_build_object('relation',c.oid::regclass::text,'rls',c.relrowsecurity,'force_rls',c.relforcerowsecurity,'acl',c.relacl,'owner',r.rolname)) from pg_class c join pg_roles r on r.oid=c.relowner where c.oid=any(array[${relations.map(r=>quote(r)+'::regclass').join(',')}])),
'columns',(select jsonb_agg(jsonb_build_object('relation',c.oid::regclass::text,'name',a.attname,'type',format_type(a.atttypid,a.atttypmod),'notnull',a.attnotnull,'default',pg_get_expr(d.adbin,d.adrelid),'position',a.attnum)) from pg_class c join pg_attribute a on a.attrelid=c.oid and a.attnum>0 and not a.attisdropped left join pg_attrdef d on d.adrelid=c.oid and d.adnum=a.attnum where c.oid=any(array[${relations.map(r=>quote(r)+'::regclass').join(',')}])),
'constraints',(select jsonb_agg(jsonb_build_object('relation',conrelid::regclass::text,'name',conname,'definition',pg_get_constraintdef(oid))) from pg_constraint where conrelid=any(array[${relations.map(r=>quote(r)+'::regclass').join(',')}])),
'functions',(select jsonb_agg(jsonb_build_object('signature',sig,'md5',md5(pg_get_functiondef(sig::regprocedure)),'anon',has_function_privilege('anon',sig,'EXECUTE'),'authenticated',has_function_privilege('authenticated',sig,'EXECUTE'),'service_role',has_function_privilege('service_role',sig,'EXECUTE'))) from unnest(array[${signatures.map(quote).join(',')}])sig));`,{role:'postgres',json:true})
for(const expected of metadata.tables){const found=actual.tables.find(t=>t.relation===expected.schema+'.'+expected.name);for(const key of ['rls','force_rls','owner'])assert.equal(found?.[key],expected[key],`${expected.name} ${key}`);assert.deepEqual(found?.acl,expected.acl,`${expected.name} table ACL`)}
assert.equal(actual.columns.length,metadata.columns.length,'lineage column count')
for(const expected of metadata.columns){const found=actual.columns.find(c=>c.relation===expected.relation&&c.name===expected.name);assert.deepEqual(found,expected,`${expected.relation}.${expected.name} column metadata`)}
assert.equal(actual.constraints.length,metadata.constraints.length,'lineage constraint count')
for(const expected of metadata.constraints){const found=actual.constraints.find(c=>c.relation===expected.relation&&c.name===expected.name);assert.deepEqual(found,expected,`${expected.name} constraint definition`)}
for(const expected of metadata.functions){const found=actual.functions.find(f=>f.signature===expected.signature);assert.equal(found?.md5,expected.md5,expected.signature+' live function hash');for(const role of ['anon','authenticated','service_role']){const executable=expected.acl==null||expected.acl.some(acl=>acl.startsWith(role+'=X/')||acl.startsWith('=X/'));assert.equal(found?.[role],executable,expected.signature+' '+role+' EXECUTE')}}
console.log(`PASS production lineage parity: ${metadata.columns.length} columns, ${metadata.constraints.length} real constraints, ${metadata.functions.length} exact live function hashes and grants`)
