// Guards: PR #872 relevant schema parity, authoritative metadata only; never a production script.
import fs from 'node:fs'
const a=JSON.parse(fs.readFileSync('tests/fixtures/intake-ui/production-parity.json'))
const b=JSON.parse(fs.readFileSync('tests/fixtures/intake-ui/production-parity-more.json'))
const q=s=>"'"+s.replaceAll("'","''")+"'"
for(const table of ['pipeline.evidence_lineage_stats','pipeline.evidence_entity_links']) {
 const cs=b.columns.filter(c=>c.table===table)
 console.log(`create table if not exists ${table} (${cs.map(c=>`${c.name} ${c.type}${c.default?' default '+c.default:''}${c.not_null?' not null':''}`).join(',')});`)
}
for(const c of b.columns.filter(c=>c.table==='pipeline.admin_jobs')) {
 console.log(`alter table pipeline.admin_jobs add column if not exists ${c.name} ${c.type}${c.default?' default '+c.default:''};`)
 if(c.default) console.log(`alter table pipeline.admin_jobs alter column ${c.name} set default ${c.default};`)
 if(c.not_null) console.log(`alter table pipeline.admin_jobs alter column ${c.name} set not null;`)
}
console.log('alter table pipeline.ops_outcome_codes add column if not exists title text, add column if not exists counts_as_movement boolean;')
for(const c of a.outcome_codes) console.log(`update pipeline.ops_outcome_codes set title=${q(c.title)},counts_as_movement=${c.counts_as_movement} where code=${q(c.code)};`)
for(const c of [...a.constraints,...b.evidence_constraints]) {
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(c.table)}::regclass and conname=${q(c.name)}) then alter table ${c.table} add constraint ${c.name} ${c.definition}; end if; end $p$;`)
 // Fail on any constraint drift, not just absence.
 console.log(`do $p$ begin if not exists(select 1 from pg_constraint where conrelid=${q(c.table)}::regclass and conname=${q(c.name)} and pg_get_constraintdef(oid)=${q(c.definition)}) then raise exception 'constraint parity failed: ${c.name}'; end if; end $p$;`)
}
console.log(fs.readFileSync('tests/fixtures/intake-ui/evidence-trigger-definitions.sql','utf8'))
for(const t of a.triggers.filter(t=>t.name.startsWith('evidence_'))) {
 console.log(`drop trigger if exists ${t.name} on catalogue.course_intakes;\n${t.definition};`)
}
for(const i of b.indexes.filter(i=>/course_intakes_(course_idx|evidence_idx|campus_idx)|courses_provider_code_trim_active_idx/.test(i))) console.log(i.replace('CREATE INDEX','CREATE INDEX IF NOT EXISTS')+';')
for(const f of a.function_signatures) {
 console.log(`revoke all on function ${f.signature} from public,anon,authenticated,service_role;`)
 if(f.signature.includes('admin_job_run_now')) console.log(`grant execute on function ${f.signature} to authenticated,service_role;`)
}
console.log("do $$begin create role authenticator; exception when duplicate_object then null; end$$; alter role authenticated set statement_timeout='8s'; alter role authenticator set statement_timeout='8s';")

for(const t of a.triggers) console.log(`do $p$ begin if not exists(select 1 from pg_trigger where tgrelid='catalogue.course_intakes'::regclass and tgname=${q(t.name)} and pg_get_triggerdef(oid)=${q(t.definition)}) then raise exception 'trigger parity failed: ${t.name}'; end if; end $p$;`)
for(const f of a.function_signatures) {
 const hash=f.signature.includes('job_run_now_v1(text,text,jsonb,uuid)')?'2640319be221ab00f39e6e767b78a7b3':f.md5
 console.log(`do $p$ begin if md5(pg_get_functiondef(${q(f.signature)}::regprocedure))<>${q(hash)} then raise exception 'function parity failed: ${f.signature}'; end if; end $p$;`)
 const isPublic=f.signature.includes('admin_job_run_now_v1')
 for(const role of ['anon','authenticated','service_role']) console.log(`do $p$ begin if has_function_privilege('${role}',${q(f.signature)},'EXECUTE')<>${isPublic&&role!=='anon'} then raise exception 'function grant parity failed'; end if; end $p$;`)
}
console.log("do $$begin raise notice 'PASS authoritative constraint, trigger, signature, grant and outcome-code parity'; end$$;")
