// Guards: Provider Description mandate §8, relevant live function/table privileges; new RPC grants come from migration.
import fs from 'node:fs'
const root='tests/fixtures/provider-description-autonomy/'
const p=JSON.parse(fs.readFileSync(root+'production-parity.json'))
const m=JSON.parse(fs.readFileSync(root+'production-more.json'))
const grants=JSON.parse(fs.readFileSync(root+'production-exact-function-grants.json'))
const sigs=JSON.parse(fs.readFileSync(root+'function-signatures.json'))
for(const s of sigs) {
 console.log(`revoke all on function ${s.signature} from public,anon,authenticated,service_role;`)
 const canonical=x=>x.replace(/\s*,\s*/g,',').replace(/\s+/g,' ').trim()
 for(const role of ['PUBLIC','anon','authenticated','service_role'])if(grants.some(g=>canonical(g.signature)===canonical(s.signature)&&g.grantee===role))console.log(`grant execute on function ${s.signature} to ${role};`)
}
console.log('grant usage on schema public,auth,security to authenticated,service_role;')
for(const r of p.rls){
 console.log(`revoke all on ${r.relation} from public,anon,authenticated,service_role;`)
 for(const g of m.table_grants.filter(g=>`${g.table_schema}.${g.table_name}`===r.relation))console.log(`grant ${g.privilege_type} on ${r.relation} to ${g.grantee};`)
}
