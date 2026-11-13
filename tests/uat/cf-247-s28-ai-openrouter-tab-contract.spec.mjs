// Guards: CF-247 v2.15.264 (S28): Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration of OpenAI and access to toolsets and limits;
// CF-247 v2.15.264 (S28): Platform Admin, 13 Oct 2026 00:09: "Layer 3 has removed the configuration of OpenAI and access to toolsets
// and limits; restore them as a tab in Models & services." Decisions: three tabs; scholarship AI models editable in the AI tab.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const sql = fs.readFileSync('supabase/migrations/20261013012100_cf247_ai_openrouter_tab.sql', 'utf8')

test('12100: one read for the AI tab; central pages model and switch by a Platform Admin with a reason; nothing dropped', () => {
  expect(sql).toContain('create or replace function public.admin_ai_config_read() returns jsonb')
  expect(sql).toContain("if auth.uid() is null or coalesce(security.current_role_rank(), 0) < 6 then raise exception 'Platform Admin required'")
  expect(sql).toContain("if length(v_reason) < 4 then raise exception 'a reason is required'; end if;")
  expect(sql).toContain("x.status <> 'retired' and x.model_identifier <> 'person'")
  expect(sql).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
})

// v2.16.0 (Platform Admin 13 Nov 2026 19:14): the three tests of the AI & OpenRouter tab (its nav entry, its cards, the AI model switches) are
// retired with the screen; Models & services › AI is guarded by cf-247-ai-models-services-ui. The read above stays: the key controls use it.
