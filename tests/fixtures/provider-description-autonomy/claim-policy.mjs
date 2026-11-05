// Guards: Platform Admin 5 Nov 2026 20:03 §2 (PR #877): evidence-aware campus, scholarship and guarantee validation; never a keyword-only rejection; course descriptions keep pdesc.claim_words.
import assert from'node:assert/strict'
import fs from'node:fs'
import{sql,quote}from'./db.mjs'
import{descriptionPageText,providerDescriptionSentences}from'../../../supabase/functions/coverage-sweep/description.ts'
const root='tests/fixtures/provider-description-autonomy/'
const migration=fs.readFileSync('supabase/migrations/20261106200000_cf247_provider_description_autonomy.sql','utf8')
const provider='10000000-0000-0000-0000-000000000001'
const doc=sql(`select to_jsonb(d) from fixture.documents d where provider_id=${quote(provider)};`,{role:'postgres',json:true})
// A controlled official About page: the fixture provider's stored page plus campus, scholarship and guarantee passages.
const passages=[
 'Aurora Maritime University has campuses in Hobart, Launceston and Burnie.',
 'Aurora Maritime University teaches students in Hobart, Launceston and Burnie.',
 'Aurora Maritime University offers scholarships for international students studying maritime programs.',
 'Graduates of Aurora Maritime University are prepared for employment at sea.',
 'The University advances maritime scholarship and ocean research.',
 'Aurora Maritime University does not guarantee accommodation for new students.',
]
const html=doc.html.replace('</main>',passages.map(p=>`<p>${p}</p>`).join('')+'</main>')
const page=descriptionPageText(html,16000)
const base=doc.model_answer.sentences[0]
const cases=[
 {name:'supported campus claim',text:'Aurora Maritime University teaches at campuses in Hobart, Launceston and Burnie.',quote:passages[0],ok:true},
 {name:'unsupported campus claim',text:'Aurora Maritime University teaches at campuses in Hobart, Launceston and Burnie.',quote:passages[1],ok:false,rule:'unsupported_claim'},
 {name:'supported scholarship mention',text:'Aurora Maritime University offers scholarships to international students in maritime programs.',quote:passages[2],ok:true},
 {name:'unsupported guarantee',text:'Graduates of Aurora Maritime University are guaranteed employment at sea.',quote:passages[3],ok:false,rule:'unsupported_claim'},
 {name:'word in a non-claim sense',text:'Aurora Maritime University advances maritime scholarship and ocean research.',quote:passages[4],ok:true},
 {name:'guarantee negated by the official quote',text:'Aurora Maritime University guarantees accommodation for new students.',quote:passages[5],ok:false,rule:'claim_negated_in_source'},
 {name:'negation kept as stated',text:'Aurora Maritime University does not guarantee accommodation to new students.',quote:passages[5],ok:true},
]
const validate=answer=>sql(`select security.provider_description_validate_v1(${quote(provider)},'https://p1.example.edu/about',now(),${quote(JSON.stringify(answer))}::jsonb);`,{role:'postgres',json:true})
const out=[]
for(const c of cases){
 const checked=providerDescriptionSentences({about_page:true,sentences:[base,{text:c.text,quote:c.quote}]},page,20)
 assert.ok(checked.sentences.every(s=>s.on_page),c.name+': every quote is on the stored official page')
 const r=validate(checked)
 if(c.ok)assert.ok(r.ok===true&&['propose','verified'].includes(r.outcome),c.name+': '+JSON.stringify(r))
 else{assert.equal(r.ok,false,c.name);assert.equal(r.rule,c.rule,c.name+': '+JSON.stringify(r))}
 out.push({case:c.name,ok:r.ok,outcome:r.outcome,rule:r.rule})
 console.log('PASS '+c.name+' -> '+(r.ok?r.outcome:r.rule))
}
// Word forms count as the same statement: a plural in the sentence is supported by the singular in the quote and the reverse.
assert.equal(sql(`select security.pdesc_claim_check_v1('Its campus is in Hobart.','Our campuses are in Hobart and Burnie','campus');`,{role:'postgres'}),'','plural quote supports a singular statement')
assert.equal(sql(`select security.pdesc_claim_check_v1('It has guaranteed places.','Places are guaranteed for local students','guarantee');`,{role:'postgres'}),'','tense form is the same statement')
// Course descriptions keep their own list: the migration leaves pdesc.claim_words exactly as production holds it, and replays without duplicates.
const prodClaimWords=JSON.parse(fs.readFileSync(root+'production-metadata.json')).settings.find(s=>s.key==='pdesc.claim_words').value
const proof=sql(`begin;
 ${migration};
 ${migration};
 select jsonb_build_object('claim_words',(select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.claim_words'),
  'evidence_words',(select value from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.evidence_claim_words'),
  'evidence_rows',(select count(*) from pipeline.platform_toolset_settings where toolset_key='pipeline' and key='pdesc.evidence_claim_words'));rollback;`,{role:'postgres',json:true})
assert.deepEqual(proof.claim_words,prodClaimWords,'pdesc.claim_words (also read by course descriptions) is unchanged by the migration')
assert.deepEqual(proof.evidence_words,['campus','scholarship','guarantee'],'evidence-checked words have their own provider-only list')
assert.equal(proof.evidence_rows,1,'replay adds no duplicate setting')
assert.ok(!/key\s*=\s*'pdesc\.claim_words'/.test(migration.replace(/--.*$/gm,'')),'no statement in the migration writes pdesc.claim_words')
fs.mkdirSync('docs/ui-evidence',{recursive:true})
fs.writeFileSync('docs/ui-evidence/provider-description-claim-policy.json',JSON.stringify({decision:'Platform Admin 5 Nov 2026 20:03 §2',cases:out,course_description_claim_words_unchanged:true,actual_vendor_calls:0},null,2)+'\n')
console.log('PASS evidence-aware campus, scholarship and guarantee validation; supported claims pass, unsupported and negated claims held; pdesc.claim_words unchanged for course descriptions')
