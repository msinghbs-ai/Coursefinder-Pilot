import {test,expect} from '@playwright/test'
import fs from 'node:fs'

const sql=fs.readFileSync('supabase/migrations/20260913113000_cf_093_firecrawl_zenrows_exhaustion_parking.sql','utf8')

test('CF-093 uses Firecrawl/ZenRows and parks bounded exhaustion into Layer 3/Layer 4',()=>{
  expect(sql).toContain("p.provider_key in ('firecrawl','zenrows')")
  expect(sql).toContain("when 'firecrawl' then 10 when 'zenrows' then 20")
  expect(sql).toContain("'scheduler_layer2_exhaustion','blocked'")
  expect(sql).toContain("'blocked_pending_evidence'")
  expect(sql).toContain("'official_course_url'")
  expect(sql).toContain("'route','firecrawl_then_zenrows'")
  expect(sql).toContain("'canonical_mutation_authorised',false")
  expect(sql).toContain("status='handoff_started'")
  expect(sql).not.toContain("provider_key in ('scrape-do','scraperapi')")
  expect(sql).not.toContain("insert into publishing.")
  expect(sql).not.toContain("insert into search.")
})
