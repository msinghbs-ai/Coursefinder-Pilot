// Guards: F-INT.08 (S2-Intakes mandate, Platform Admin 13 Nov 2026 11:02: fix time-outs at their source): the intake wording lookup and its fingerprint keep their signatures and results, are PL/pgSQL, read the course's one stored page once and look up address variants only when the exact address does not match.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const mig = fs.readFileSync('supabase/migrations/20261113290000_cf247_intake_wording_speed.sql', 'utf8')
const body = (name) => mig.slice(mig.indexOf(`create or replace function security.${name}`), mig.indexOf('$function$;', mig.indexOf(`create or replace function security.${name}`)))

test('both functions keep their signatures, run as PL/pgSQL, security definer with an empty search path', () => {
  const w = body('intake_page_wording_v1(p_course uuid, p_evidence uuid, p_url text)')
  const f = body('intake_wording_fp_v1(p_course uuid, p_evidence uuid)')
  for (const b of [w, f]) {
    expect(b).toContain('returns text')
    expect(b).toContain('language plpgsql')
    expect(b).toContain('stable security definer')
    expect(b).toContain("set search_path to ''")
  }
})

test('the wording: exact and final address first, variants only when neither matches, filled intake quotes after the page wording', () => {
  const w = body('intake_page_wording_v1(p_course uuid, p_evidence uuid, p_url text)')
  expect(w).toContain('from pipeline.coverage_course_pages g where g.course_id = p_course;')
  expect(w).toContain('if v_gurl = p_url or v_final = p_url then v_match := true;')
  expect(w).toContain('elsif v_gurl = any ((select security.course_page_url_variants_v1(co.provider_id, p_url) from catalogue.courses co where co.id = p_course)::text[]) then v_match := true;')
  expect(w).toContain("f.field = 'intakes' and f.state = 'filled' and f.evidence_id = p_evidence")
  expect(w).toContain("else v_page || ' | ' || v_fill end")
})

test('the fingerprint is the same md5 of the sorted distinct wording parts', () => {
  const f = body('intake_wording_fp_v1(p_course uuid, p_evidence uuid)')
  expect(f).toContain("string_agg(s, '|' order by s)")
  expect(f).toContain("select distinct s from unnest(string_to_array(")
  expect(f).toContain("security.intake_page_wording_v1(p_course, p_evidence, (select e.source_url from pipeline.evidence_artifacts e where e.id = p_evidence)), ' | ')")
})

test('guarded by the live bodies, post-checked, nothing dropped, housekeeping lines present', () => {
  expect(mig).toContain("'eb380f591dc17bf536c94d999f4f1b26'")
  expect(mig).toContain("'1433922c14f8b545cc3a09bb557dd9fb'")
  expect(mig).toContain("raise exception 'post-check: the intake wording functions are not the PL/pgSQL versions'")
  expect(mig).not.toMatch(/^\s*(drop|delete|truncate)\b/im)
  expect(mig).toMatch(/^-- Replaces: security\.intake_page_wording_v1 and security\.intake_wording_fp_v1/m)
  expect(mig).toMatch(/^-- Retires: nothing\./m)
})
