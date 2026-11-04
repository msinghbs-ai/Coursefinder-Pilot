// Guards: Provider Description mandate §8: exact frozen post-migration functions, grants, atomic replay and deliberate drift refusal.
import assert from'node:assert/strict'
import fs from'node:fs'
import{sql,quote}from'./db.mjs'
const root='tests/fixtures/provider-description-autonomy/'
const hashes=JSON.parse(fs.readFileSync(root+'migration-function-hashes.json'))
const migration=fs.readFileSync('supabase/migrations/20261105010000_provider_description_autonomy.sql','utf8')
const actual=()=>sql(`select jsonb_object_agg(sig,md5(pg_get_functiondef(sig::regprocedure))) from unnest(array[${Object.keys(hashes).map(quote).join(',')}])sig;`,{role:'postgres',json:true})
assert.deepEqual(actual(),hashes,'exact frozen after hashes')
sql('begin;'+migration+';commit;',{role:'postgres'})
assert.deepEqual(actual(),hashes,'second atomic migration apply changes no guarded function')
const signature='security.provider_description_enqueue_v1()'
const def=sql(`select pg_get_functiondef(${quote(signature)}::regprocedure);`,{role:'postgres'})
assert.ok(def.includes('provider-description-autonomy-v1'))
const tampered=def.replace('provider-description-autonomy-v1','provider-description-autonomy-v1\n-- deliberately drifted fixture body retaining old marker')
let rejected=false
try{sql('begin;'+tampered+';'+migration+';commit;',{role:'postgres'})}catch(e){assert.match(String(e.stderr||e.message),/dependency drift/);rejected=true}
assert.ok(rejected,'a retained marker never exempts function drift from exact hashes')
assert.deepEqual(actual(),hashes,'failed drift transaction rolls back all replacements')
const grants=sql(`select jsonb_build_object('admin_anon',has_function_privilege('anon','public.admin_provider_description_run_v1(text,jsonb)','EXECUTE'),'admin_auth',has_function_privilege('authenticated','public.admin_provider_description_run_v1(text,jsonb)','EXECUTE'),'cohort_auth',has_function_privilege('authenticated','public.svc_provider_description_cohort_next(integer,uuid)','EXECUTE'),'cohort_service',has_function_privilege('service_role','public.svc_provider_description_cohort_next(integer,uuid)','EXECUTE'),'reserve_auth',has_function_privilege('authenticated','public.svc_provider_description_reserve_v1(uuid,text,numeric,text)','EXECUTE'),'reserve_service',has_function_privilege('service_role','public.svc_provider_description_reserve_v1(uuid,text,numeric,text)','EXECUTE'),'private_auth',has_function_privilege('authenticated','security.provider_description_run_result_v1(uuid)','EXECUTE'));`,{role:'postgres',json:true})
assert.deepEqual(grants,{admin_anon:false,admin_auth:true,cohort_auth:false,cohort_service:true,reserve_auth:false,reserve_service:true,private_auth:false})
fs.writeFileSync('docs/ui-evidence/provider-description-migration-replay.json',JSON.stringify({atomic_replay:'PASS',retained_marker_drift_refused:true,rollback_preserved_functions:true,after_hashes:hashes,grants},null,2)+'\n')
console.log('PASS exact after hashes, atomic migration replay, retained-marker drift refusal, rollback and new public/private EXECUTE grants')
