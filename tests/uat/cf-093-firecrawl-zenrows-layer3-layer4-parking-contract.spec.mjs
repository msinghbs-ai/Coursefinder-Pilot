import {test,expect} from '@playwright/test'
import fs from 'node:fs'

const sql=fs.readFileSync('supabase/migrations/20260913113000_cf_093_firecrawl_zenrows_exhaustion_parking.sql','utf8')

test('CF-093 uses Firecrawl/ZenRows and parks only unresolved bounded exhaustion into Layer 3/Layer 4',()=>{
  expect(sql).toContain("p.provider_key in ('firecrawl','zenrows')")
  expect(sql).toContain("when 'firecrawl' then 10")
  expect(sql).toContain("when 'zenrows' then 20")
  expect(sql).toContain("'manual_governed','blocked'")
  expect(sql).toContain("'blocked_pending_evidence'")
  expect(sql).toContain("'official_course_url'")
  expect(sql).toContain("'route','firecrawl_then_zenrows'")
  expect(sql).toContain("'canonical_mutation_authorised',false")
  expect(sql).toContain("status='handoff_started'")
  expect(sql).toContain("dc.selected=true")
  expect(sql).toContain("nullif(dc.discovered_url,'') is not null")
  expect(sql).toContain("dc.created_at>=v_binding.activated_at")
  expect(sql).toContain("any(v_unresolved)")
  expect(sql).toContain("foreach v_course in array v_unresolved")
  expect(sql).not.toContain("provider_key in ('scrape-do','scraperapi')")
  expect(sql).not.toContain("insert into publishing.")
  expect(sql).not.toContain("insert into search.")
})
