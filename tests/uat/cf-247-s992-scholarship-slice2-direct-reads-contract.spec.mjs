// Guards: Platform Admin 23 Nov 2026 15:39, 17:45 and 17:49 AEDT (s992 scholarship slice 2: $0 direct reads for Charles Darwin and Lincoln; copy-less pages read directly while the Firecrawl lane is held; listing pages read directly first).
// The listing reader reads directly first and uses the direct copy only when it gives items; the stored-first switch goes off; the two Charles Darwin international pages are listing sources read first; Firecrawl stays behind svc_fc_spend at its zero total.
import { test, expect } from '@playwright/test';
import fs from 'node:fs';

const sql = fs.readFileSync('supabase/migrations/20261123200000_cf247_s992_scholarship_slice2_direct_reads.sql', 'utf8');
const w = fs.readFileSync('supabase/functions/coverage-sweep/index.ts', 'utf8');

test('s992: listing page read directly first; direct copy used only when it gives items; scraper fallback unchanged', () => {
  expect(w).toContain('const WORKER = "coverage-sweep-worker-v1.0.35"; // v1.0.35 (23 Nov 2026, CF-247 s992');
  expect(w).toContain('let pg = await readSch(url, r.provider_id, wsNum("scholarship.catalogue_render_wait_ms", 5000), true);');
  expect(w).toContain('if (pg.via === "direct" && pg.status === "read" && scholarshipListing(pg.html, pg.finalUrl || url, r.hosts || [], maxItems).length + awardSections(pg.html, pg.finalUrl || url).length === 0)');
  expect(w).toContain('pg = await readSch(url, r.provider_id, wsNum("scholarship.catalogue_render_wait_ms", 5000), false);');
  expect(w).toContain('if (!(await useFc("sch_scrape", providerId, url, true))) return none("waiting_scraper");');
});

test('s992: stored-first off with its reason; zero Firecrawl total required; CDU sources and Lincoln read first; guarded', () => {
  expect(sql).toContain("security.fc_setting_num_v1('daily_budget_total', 15000) <> 0");
  expect(sql).toContain("key = 'lanes.stored_first_on' and value = to_jsonb(1)");
  expect(sql).toContain("array['https://www.cdu.edu.au/international/how-apply/scholarships', 'https://www.cdu.edu.au/international/scholarships']");
  expect(sql).toContain("if not security.url_on_provider_sites(v_url, v_cdu) then raise exception");
  expect(sql).toContain("'manual', true, 'waiting', null, security.system_actor_id())");
  expect(sql).toContain("update pipeline.scholarship_listing_pages set next_read_at = null");
  expect(sql).toContain('post-check: the Charles Darwin listing sources are not both active');
  expect(sql).not.toMatch(/create table|cron\.(schedule|unschedule)|daily_budget_total'.*to_jsonb|publication_status = 'published'/i);
});
