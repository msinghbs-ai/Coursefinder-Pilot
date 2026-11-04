// Guards: Provider Description mandate §3/8: unsupported campus, scholarship and guarantee claims refused; existing custom policy survives replay.
import assert from'node:assert/strict'
import fs from'node:fs'
import{sql,quote}from'./db.mjs'
import{descriptionPageText,descriptionSentences}from'../../../supabase/functions/coverage-sweep/description.ts'
const root='tests/fixtures/provider-description-autonomy/'
const migration=fs.readFileSync('supabase/migrations/20261105010000_provider_description_autonomy.sql','utf8')
const doc=sql("select to_jsonb(d) from fixture.documents d where provider_id='10000000-0000-0000-0000-000000000001';",{role:'postgres',json:true})
const page=descriptionPageText(doc.html,16000)
const cases=[]
for(const term of ['campus-based study','scholarships for applicants','guarantees personal mentoring']){
 const answer=structuredClone(doc.model_answer);answer.sentences[0].text=answer.sentences[0].text.replace(/\.$/,'')+' and offers '+term+'.'
 const checked=descriptionSentences(answer,page,20)
 const result=sql(`select security.provider_description_validate_v1('10000000-0000-0000-0000-000000000001','https://p1.example.edu/about',now(),${quote(JSON.stringify(checked))}::jsonb);`,{role:'postgres',json:true})
 assert.equal(result.rule,'unsupported_claim',term);assert.equal(result.ok,false,term)
 cases.push({term,rule:result.rule})
}
const base=JSON.parse(fs.readFileSync(root+'production-metadata.json')).settings.find(s=>s.key==='pdesc.claim_words').value
const custom=[...base,'bespokeclaim','CAMPUS']
const customProof=sql(`begin;
 update pipeline.platform_toolset_settings set value=${quote(JSON.stringify(custom))}::jsonb where toolset_key='pipeline' and key='pdesc.claim_words';
 ${migration};
 create temp table claim_after_first as select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.claim_words';
 ${migration};
 select jsonb_build_object('value',(select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.claim_words'),'first',(select value from claim_after_first));rollback;`,{role:'postgres',json:true})
assert.deepEqual(customProof.value,customProof.first,'reapply does not append duplicate policy words')
assert.ok(customProof.value.includes('bespokeclaim')&&customProof.value.includes('CAMPUS'),'custom policy values are preserved verbatim')
for(const word of ['campus','campuses','scholarship','scholarships','guarantee','guaranteed','guarantees'])assert.equal(customProof.value.filter(v=>v.toLowerCase()===word).length,1,word+' occurs once')
fs.mkdirSync('docs/ui-evidence',{recursive:true})
fs.writeFileSync('docs/ui-evidence/provider-description-claim-policy.json',JSON.stringify({cases,custom_words_preserved:true,replay_duplicates:0,actual_vendor_calls:0},null,2)+'\n')
console.log('PASS unsupported campus, scholarship and guarantee claims; exact custom words retained; repeated policy migration adds no duplicates')
