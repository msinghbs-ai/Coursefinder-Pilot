// Guards: Provider Description autonomy mandate §6: a direct Layer 4 link must reach its exact decision beyond the first page.
// Navigation-order regression only. Uses the actual constrained review table and a captured production keyset contract;
// does not simulate the full Inbox union or a reviewer decision. All added rows roll back in the isolated Docker database.
import assert from 'node:assert/strict'
import crypto from 'node:crypto'
import fs from 'node:fs'
import { fileURLToPath } from 'node:url'
import { layer4DeepLinkCursor } from '../../../src/layer4-deep-link.js'
import { sql, quote } from './db.mjs'

export function navigationRegression() {
  const contract = JSON.parse(fs.readFileSync(new URL('./navigation-contract.json', import.meta.url), 'utf8'))
  assert.equal(crypto.createHash('md5').update(contract.items_definition).digest('hex'), contract.items_md5)
  assert.equal(crypto.createHash('md5').update(contract.source_definition).digest('hex'), contract.source_md5)
  const adapterField = JSON.parse(fs.readFileSync(new URL('./navigation-helper-metadata.json', import.meta.url), 'utf8'))
  assert.equal(sql(`select md5(pg_get_functiondef(${quote(adapterField.signature)}::regprocedure));`, { role: 'postgres' }), adapterField.md5)
  assert.ok(contract.items_definition.includes('(x.o, x.kind, x.created_at, x.ref) > (v_ao, v_ak, v_aat, v_ar) order by o, kind, created_at, ref'))
  assert.ok(contract.source_definition.includes("when r.entity_type = 'course' and r.field_code = 'course_description_first_read' then 'provider_description'"))
  const kind = 'provider_description'
  const target = 'ffffffff-ffff-ffff-ffff-ffffff000000'
  const at = '2026-11-04T12:34:56.123456+00:00'
  const cursor = layer4DeepLinkCursor(contract.kinds, kind, target, at)
  assert.ok(cursor)
  assert.equal(cursor.after_at, at)
  const targetNumber = BigInt('0x' + target.replaceAll('-', ''))
  const keys = Array.from({ length: 600 }, (_, i) => {
    const h = (targetNumber - BigInt(i + 1)).toString(16).padStart(32, '0')
    return { n: i + 1, review_id: `${h.slice(0,8)}-${h.slice(8,12)}-${h.slice(12,16)}-${h.slice(16,20)}-${h.slice(20)}` }
  })
  const resultText = sql(`begin;
    create temp table navigation_keys as select n,review_id::uuid,md5('fixture:navigation-course:'||n)::uuid course_id
      from jsonb_to_recordset(${quote(JSON.stringify(keys))}::jsonb) as x(n integer,review_id text);
    insert into catalogue.courses(id,provider_id,canonical_title,lifecycle_status)
      select course_id,'10000000-0000-0000-0000-000000000001'::uuid,'Fictional navigation course '||n,'active' from navigation_keys;
    insert into pipeline.layer4_review_items(id,entity_type,entity_id,field_code,evidence_id,status,created_at,proposed_value)
      select n.review_id,'course',n.course_id,'course_description_first_read',d.evidence_id,'pending',${quote(at)}::timestamptz,
      jsonb_build_object('description','Fictional navigation evidence; never admitted')
      from navigation_keys n cross join fixture.documents d where d.provider_id='10000000-0000-0000-0000-000000000001'::uuid;
    insert into pipeline.layer4_review_items(id,entity_type,entity_id,field_code,evidence_id,status,created_at,proposed_value)
      select '${target}'::uuid,'provider',d.provider_id,'provider_description',d.evidence_id,'pending',${quote(at)}::timestamptz,
      jsonb_build_object('description','Fictional navigation target; never admitted')
      from fixture.documents d where d.provider_id='10000000-0000-0000-0000-000000000001'::uuid;
    with x as (
      select ${cursor.after_o}::integer o,'provider_description'::text kind,r.created_at,r.id::text ref
      from pipeline.layer4_review_items r left join catalogue.courses c on r.entity_type='course' and c.id=r.entity_id
      where r.status='pending'
      and ((r.entity_type='provider' and r.field_code='provider_description') or (r.entity_type='course' and r.field_code='course_description_first_read'))
      and coalesce(c.provider_id,case when r.entity_type='provider' then r.entity_id end)='10000000-0000-0000-0000-000000000001'::uuid
      and (r.id='${target}'::uuid or r.id in(select review_id from navigation_keys))
    ), naive as (select * from x order by o,kind,created_at,ref limit 500),
    pg as (select * from x where (x.o,x.kind,x.created_at,x.ref)>(${cursor.after_o},${quote(cursor.after_kind)},${quote(cursor.after_at)}::timestamptz,${quote(cursor.after_ref)}) order by o,kind,created_at,ref limit 500)
    select jsonb_build_object('total',(select count(*) from x),'naive_count',(select count(*) from naive),
      'naive_has_target',exists(select 1 from naive where ref='${target}'),
      'before',(select count(*) from x where (x.o,x.kind,x.created_at,x.ref)<=(${cursor.after_o},${quote(cursor.after_kind)},${quote(cursor.after_at)}::timestamptz,${quote(cursor.after_ref)})),
      'first_ref',(select ref from pg order by o,kind,created_at,ref limit 1),'seek_count',(select count(*) from pg));
    rollback;`, { role: 'postgres' })
  const result = JSON.parse(resultText.split('\n').find(line => line.startsWith('{')))
  assert.equal(result.total, 601)
  assert.equal(result.naive_count, 500)
  assert.equal(result.naive_has_target, false)
  assert.equal(result.before, 600)
  assert.equal(result.first_ref, target)
  assert.equal(result.seek_count, 1)
  assert.equal(sql(`select count(*) from pipeline.layer4_review_items where id='${target}'::uuid;`, { role: 'postgres' }), '0')
  const report = { boundary: 'Navigation-order regression on real constrained PostgreSQL review rows, not full Inbox end-to-end execution. All 601 temporary review rows and 600 course rows rolled back; no decision submitted.', captured_contract_at: contract.captured_at, items_md5: contract.items_md5, source_md5: contract.source_md5, cursor, result }
  fs.mkdirSync('docs/ui-evidence', { recursive: true })
  fs.writeFileSync('docs/ui-evidence/provider-description-navigation.json', JSON.stringify(report, null, 2) + '\n')
  process.stdout.write('PASS actual review-table keyset reaches the exact decision after 600 same-kind, same-provider, same-microsecond predecessors\n')
  return report
}

if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) navigationRegression()
