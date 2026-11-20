// Guards: CF-247 s819 (Platform Admin 20 Nov 2026 09:55, chat S1-Build): Layer 4 decisions under 300 ms — the Inbox item read runs its
// unchanged query text by EXECUTE with its arguments known, and returns the same rows as the definition it replaced
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const MIG = fs.readFileSync('supabase/migrations/20261120116000_cf247_s819_layer4_inbox_items_execute.sql', 'utf8')

test('the live definition is md5-checked and only the argument names change in the query text', () => {
  expect(MIG).toContain("if md5(v_def) <> 'd19cd5e2c05a59b0c985afd87b6ce18a' then")
  expect(MIG).toContain("raise exception 'pre-check: security.layer4_inbox_items_v2 changed since it was read (definition md5 %)', md5(v_def);")
  for (const [name, n] of [['p_provider_id', 1], ['p_kind', 2], ['p_keys', 3], ['p_detail', 4]])
    expect(MIG).toContain(`v_src := regexp_replace(v_src, '\\m${name}\\M', '$${n}', 'g');`)
  expect(MIG).toContain("if v_src ~ '\\$[A-Za-z_]*\\$' or v_src ~ '\\mp_(provider_id|kind|keys|detail)[A-Za-z0-9_]' then")
})

test('the same signature and columns, run by EXECUTE with the four arguments as parameters', () => {
  expect(MIG).toContain("execute 'create or replace function security.layer4_inbox_items_v2(p_provider_id uuid default null, p_kind text default null, p_keys text[] default null, p_detail boolean default true)")
  expect(MIG).toContain(' returns table(kind text, ref text, provider_id uuid, subject text, why text, suggestion text, created_at timestamp with time zone, detail jsonb)')
  expect(MIG).toContain(' language plpgsql stable security definer')
  expect(MIG).toContain("  return query execute ' || quote_literal(v_src) || '\n    using p_provider_id, p_kind, p_keys, p_detail;")
  expect(MIG).not.toMatch(/create (or replace )?(function|view|table) (public|api)\./)
})

test('the post-check compares every row with the replaced definition and times real decisions, rolled back', () => {
  for (const s of [
    "raise exception 'post-check: the full read differs from the replaced definition'",
    "raise exception 'post-check: the keyed read differs from the replaced definition'",
    "raise exception 'post-check: one university''s read differs from the replaced definition'",
    "['held_scholarship', 'not_international']", "['aer_review', 'approve']", "['provider_description', 'approve']",
    "raise exception 'cf-s819-undo';",
    "if v_hs > 1000 then raise exception 'post-check: a held scholarship decision took % ms', v_hs; end if;",
  ]) expect(MIG).toContain(s)
  expect(MIG).toMatch(/^-- Replaces: .+$/m)
  expect(MIG).toMatch(/^-- Retires: nothing\.$/m)
})
