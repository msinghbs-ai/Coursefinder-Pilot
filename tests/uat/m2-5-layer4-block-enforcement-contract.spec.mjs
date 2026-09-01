import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'
import { writeRunEnvironment } from './support/runtime-evidence.mjs'

// CF-057 runtime rollback proof and post-DDL advisors were clean before this trigger.
test.describe('M2.5 universal Layer 4 block enforcement contract',()=>{
  test.beforeAll(async()=>{
    await writeRunEnvironment({
      suite:'m2-5-layer4-block-enforcement-contract',
      change_control:'CF-CHG-20260901-057',
    })
  })

  test('enforces independent block scopes at owning server boundaries',async()=>{
    const sql=await fs.readFile(
      'supabase/migrations/20260901211500_m2_5_universal_layer4_block_enforcement.sql',
      'utf8'
    )

    expect(sql).toContain('create or replace view security.layer4_active_blocks')
    expect(sql).toContain('create or replace view security.layer4_search_blocked_providers')
    expect(sql).toContain('create or replace view security.layer4_search_blocked_courses')
    expect(sql).toContain('create or replace view security.layer4_search_blocked_campuses')
    expect(sql).toContain('create or replace view security.layer4_search_blocked_scholarships')
    expect(sql).toContain('create or replace function security.layer4_entity_or_parent_blocked')
    expect(sql).toContain('create or replace function security.data_quality_quarantine_impl')

    const segment=(signature)=>{
      const marker=`-- ${signature}`
      const start=sql.indexOf(marker)
      expect(start, `missing migration section ${signature}`).toBeGreaterThanOrEqual(0)
      const next=sql.indexOf('\n-- ',start+marker.length)
      return sql.slice(start,next<0?sql.length:next)
    }

    const courseFacts=segment('svc_coursefacts_apply_record(uuid,uuid,text,text,text,text,text,jsonb,boolean)')
    expect(courseFacts).toContain("p_apply and security.layer4_entity_or_parent_blocked('course',v_course,'operational')")
    expect(courseFacts).toContain('course operationally blocked by Layer 4')

    const reserve=segment('layer3_reserve_interpretation_service(uuid,uuid,text,uuid,text,uuid,jsonb,text)')
    expect(reserve).toContain("security.layer4_entity_or_parent_blocked(lower(p_entity_type),p_entity_id,'operational')")
    expect(reserve).toContain("'call_required',false,'reason','layer4_operational_block'")

    const sourcePattern=segment('layer3_source_pattern_request_context_service(uuid,uuid)')
    expect(sourcePattern).toContain("security.layer4_entity_or_parent_blocked('provider',r.entity_id,'operational')")
    expect(sourcePattern).toContain("'executable',false,'reason','layer4_operational_block'")

    const readiness=segment('publishing.course_publication_readiness_v1(uuid,text)')
    expect(readiness).toContain("'layer4_publication_block'")
    expect(readiness).toContain("'layer4_publication_blocked',v_layer4_publication_blocked")

    const publication=segment('l4_api.publication_decide(text,uuid,text,text,jsonb,jsonb,text,text,jsonb)')
    expect(publication).toContain("p_event_type='publishable'")
    expect(publication).toContain("'publication'")
    expect(publication).toContain('entity publication blocked by Layer 4')

    const dq=segment('security.admin_data_quality_read(text,jsonb)')
    expect(dq).toContain("p_operation='data_quality_quarantine'")
    expect(dq).toContain("v_rank<3")
    expect(dq).toContain('security.data_quality_quarantine_impl(p_args)')

    const consumerSignatures=[
      'api.courses_list(uuid,character,text,text,integer,integer)',
      'api.providers_list(character,integer,integer)',
      'api.search_courses(text,character,text,boolean,integer)',
      'api.vector_candidates(vector,text,character,text,integer)',
      'api.website_course_lookup_preview_v1(text)',
      'api.website_course_search_preview_v1(text,text[],text[],text,text[],text[],text[],text[],numeric,numeric,boolean,boolean,boolean,text,integer,integer)',
      'api.website_course_search_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer,integer)',
      'api.website_course_search_v2(text,text[],text[],text[],text[],text[],boolean,numeric,boolean,boolean,boolean,text,integer,integer)',
      'api.zoho_campus_lookup_v1(text)',
      'api.zoho_campus_search_v1(text,text,text[],text[],timestamp with time zone,integer,integer)',
      'api.zoho_course_candidates_v1(text,text[],text[],text[],text[],text[],boolean,boolean,integer)',
      'api.zoho_course_lookup_v1(text)',
      'api.zoho_course_search_v1(text,text[],text[],text[],boolean,timestamp with time zone,integer,integer)',
      'api.zoho_course_search_v2(text,text[],text[],text[],text[],text[],text[],boolean,boolean,boolean,boolean,boolean,boolean,integer[],text[],text[],numeric,numeric,numeric,numeric,text[],timestamp with time zone,integer,integer)',
      'api.zoho_filter_options_v1(text,text,text,integer,integer)',
      'api.zoho_provider_lookup_v1(text)',
      'api.zoho_provider_search_v1(text,text,timestamp with time zone,integer,integer)',
      'api.zoho_scholarship_lookup_v1(text)',
      'api.zoho_scholarship_search_v1(text,text[],timestamp with time zone,integer,integer)',
      'api.zoho_sync_manifest_v1(timestamp with time zone)',
    ]
    for(const signature of consumerSignatures){
      expect(segment(signature),signature).toContain('layer4_search_blocked_')
    }

    // Search blocking is a read/admission rule: projection rows are retained.
    expect(sql).not.toMatch(/delete\s+from\s+search\.course_documents/i)
    expect(sql).not.toMatch(/delete\s+from\s+pipeline\.layer4_block_decisions/i)

    // Layer 1 authoritative regulatory ingestion is deliberately not rewritten by CF-057.
    expect(sql).not.toMatch(/create\s+or\s+replace\s+function\s+(?:public\.)?svc_layer1_/i)
  })
})
