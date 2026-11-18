// Guards: Provider description route (Platform Admin 19 Nov 2026 07:39 decision 2): GPT-4.1 mini is allowed and qualified for provider_description only and is that service's one pinned model, with a daily cap of US$0.50; no other service lists it; the route is changed only from the state read live, the prompt must be version 5, and Firecrawl is switched off for provider descriptions.
// CF-247 S763. Migration 20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain. G1, G2, G3 and housekeeping are guarded centrally by s42, s32 and s57.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const code = fs.readFileSync('supabase/migrations/20261119090000_cf247_pdesc_route_gpt41_mini_stored_page_drain.sql', 'utf8').split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one pinned model for one service, with its cap, from the state read live', () => {
  expect(code).toContain("set cascade = array['gpt-4.1-mini'], previous_model = 'qwen/qwen3-30b-a3b-instruct-2507', daily_usd_cap = 0.5, changed_at = now(),")
  expect(code).toContain("where service_code = 'provider_description' and cascade = array['qwen3-30b'];")
  expect(code).toContain("raise exception 'the provider_description route is not the one read on 19 Nov 07:40 (the Platform Admin changed it); nothing applied';")
  expect(code).toContain("raise exception 'the active provider-description prompt is not version 5; nothing applied';")
  expect(code).not.toMatch(/openrouter\/auto|cascade = array\['gpt-4\.1-mini', /)
})

test('the model is qualified for this service only, by recorded decision, and no other service may list it', () => {
  expect(code).toContain("select 'provider_description', 'gpt-4.1-mini', 'provider-description-p5', 'qualified', true,")
  expect(code).toContain("where code = 'gpt-4.1-mini' and status <> 'allowed';")
  expect(code).toContain("raise exception 'post-check: another service lists gpt-4.1-mini';")
  expect(code).toContain("if v->>'model' is distinct from 'openai/gpt-4.1-mini' or (v->'cap'->>'usd')::numeric <> 0.5 then")
  expect((code.match(/update pipeline\.ai_service_routes/g) || []).length).toBe(1)
})

test('no Firecrawl for provider descriptions; nothing created or dropped', () => {
  expect(code).toContain("where toolset_key = 'pipeline' and key = 'pdesc.acquire_firecrawl' and value <> '0'::jsonb;")
  expect(code).toContain("raise exception 'post-check: Firecrawl is still on for provider descriptions';")
  expect(code).not.toMatch(/create (or replace )?function|cron\.schedule|create table|alter table|add column/i)
  expect(code).not.toMatch(/\bdrop\s+(table|function|trigger|schema|index|view)\b|\bdelete\s+from\b|\btruncate\b/i)
})
