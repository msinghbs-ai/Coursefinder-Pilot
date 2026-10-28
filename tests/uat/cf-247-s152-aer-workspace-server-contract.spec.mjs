// Guards: CF-247 AER operations workspace server (Platform Admin mandate 29 Oct 2026 08:06; admin docs/platform/AER-OPERATIONS-WORKSPACE-DECISION-2026-10-29.md W3-W14): one governed RPC; reads for every role, bounded and filtered on the server with whitelisted sorting; writes for Curator and above with a reason, the row as read (stale refused), source-supported values, no identity collision, no hard delete, one history entry per changed field; proposed AI rows never edited or activated; restore only after a workspace withdrawal or quarantine; re-read Platform Admin only, one source, never past a terminal hold; the resolver and consumer API untouched
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
const m = fs.readFileSync('supabase/migrations/20261029010000_cf247_aer_workspace.sql', 'utf8')
const code = m.split('\n').filter((l) => !/^\s*--/.test(l)).join('\n')

test('one RPC for signed-in roles only; reads bounded at 100 a page; filters and sorting on the server from a fixed list', () => {
  expect(code).toContain('create or replace function public.admin_aer(p_action text, p_args jsonb default \'{}\'::jsonb) returns jsonb')
  expect(code).toContain("if auth.uid() is null or v_rank < 1 then raise exception 'assigned StudySearch role required' using errcode = '42501'; end if;")
  expect(m).toContain("v_size := greatest(1, least(coalesce((a->>'page_size')::int, 50), 100));  -- fixed: a page is at most 100 rows (W11)")
  expect(code).toContain("revoke all on function public.admin_aer(text, jsonb) from public, anon;")
  expect(code).toContain("grant execute on function public.admin_aer(text, jsonb) to authenticated;")
  for (const f of ["($1->>'country' is null or m.country_code = upper($1->>'country'))", "($1->>'level' is null or l.short_code = $1->>'level' or m.level_label = $1->>'level')",
    "($1->>'matrix_kind' is null or m.matrix_kind = $1->>'matrix_kind')", "($1->>'band' is null or m.benchmark_band = $1->>'band')", "($1->>'edition' is null or m.edition = $1->>'edition')",
    "($1->>'intake_year' is null or m.intake_year = ($1->>'intake_year')::int)", "($1->>'read_state' is null or coalesce(r.state, 'manual') = $1->>'read_state')",
    "($1->>'requirement_kind' is null or x.kind = $1->>'requirement_kind')", "($1->>'audience' is null or x.audience = $1->>'audience')", "($1->>'as_at_from' is null or x.as_at >= ($1->>'as_at_from')::date)"]) expect(code).toContain(f)
  // sorting is chosen from a fixed list, never the caller's text; filter values are bound parameters
  expect(code).toContain("v_sort := case a->>'sort' when 'provider' then 'f.provider_name' when 'country' then 'f.country_code'")
  expect(code).toContain("v_dir := case when lower(coalesce(a->>'direction', 'asc')) = 'desc' then 'desc' else 'asc' end;")
  expect(code).toContain('execute v_sql into v_total, v_rows using a, v_size, v_off;')
  expect(code).not.toMatch(/format\([^)]*a->>/)
})

test('writes: Curator and above, a reason, the row as read; proposed rows are decided in Layer 4; source-supported values', () => {
  expect(code).toContain("elsif v_rank < 3 then raise exception 'Curator role or above required' using errcode = '42501'; end if;")
  expect(code).toContain("if length(v_reason) < 5 then raise exception 'give a reason (kept in the history)' using errcode = '22023'; end if;")
  expect(code).toContain("if m.updated_at is distinct from v_exp then raise exception 'this row was changed by someone else since you opened it; reload and try again' using errcode = '40001'; end if;")
  expect(code).toContain("if x.updated_at is distinct from v_exp then raise exception 'this row was changed by someone else since you opened it; reload and try again' using errcode = '40001'; end if;")
  expect(code.match(/if [mx]\.status = 'proposed' then raise exception 'a proposed row is decided in Layer 4, not edited here'/g)).toHaveLength(2)
  expect(code).toContain("if m.min_value is not null and coalesce(m.grade_scale, 'none') = 'none' then raise exception 'a numeric value needs its scale")
  expect(code).toContain("if x.min_entry_score is not null and nullif(btrim(x.min_entry_score_basis), '') is null then raise exception 'a course score needs its printed basis")
  expect(code).toContain("if not security.aer_band_in_quote_v1(m.benchmark_band, m.quote) then raise exception")
  expect(code).toContain("if not security.aer_numbers_in_quote_v1(m.min_grade, m.quote) then raise exception")
  expect(code).toContain("exception when unique_violation then\n      raise exception 'another active row already has this provider, country, level, band and qualification; correct that row instead' using errcode = '23505';")
  // the quote, source and stored copy are never edited
  expect(code).toContain("v_editable := array['qualification', 'level_label', 'level_code', 'band', 'min_grade', 'min_value', 'scale', 'conditions', 'edition', 'intake_year', 'as_at'];")
  expect(code).toContain("v_editable := array['description', 'min_grade', 'min_value', 'scale', 'min_entry_score', 'min_entry_score_basis', 'band', 'as_at'];")
  expect(code).toContain("if exists (select 1 from jsonb_object_keys(ch) k0 where not (k0 = any (v_editable))) then raise exception 'this field cannot be changed here'")
  // conditions are validated parts; the helper's loop variable never shadows a query alias (found by the 29 Oct rolled-back dry run)
  expect(code).toContain("declare v jsonb := coalesce(p, '{}'::jsonb); v_item jsonb;")
  expect(code).toContain("if exists (select 1 from jsonb_object_keys(v) k where k not in ('best_n', 'subject_minimums', 'alternatives')) then")
  expect(code).toContain("elsif v_key = 'conditions' then m.conditions := security.aer_conditions_v1(ch->'conditions');")
})

test('add from stored evidence; lifecycle within the existing statuses; restore only what the workspace withdrew; no delete', () => {
  expect(code).toContain("if v_ev.id is null or v_ev.storage_path is null then raise exception 'choose the stored copy of the source page'")
  expect(code).toContain("raise exception 'the stored copy is of another address (%); store the source page first'")
  expect(code).toContain("m.provenance := jsonb_build_object('reader', 'manual', 'actor', auth.uid(), 'reason', v_reason, 'at', now(), 'evidence_id', v_ev.id);")
  expect(code).toContain("update catalogue.provider_entry_matrix set status = 'inactive', status_reason = 'withdrawn: ' || v_reason, withdrawal_reason = left(v_reason, 500),")
  expect(code).toContain("update catalogue.provider_entry_matrix set status = 'unverified', status_reason = 'quarantined: ' || v_reason")
  expect(code).toContain("raise exception 'only a row withdrawn or quarantined here can be restored; a row never admitted is decided in Layer 4'")
  expect(code).not.toMatch(/\b(delete from|drop |truncate)\b/i)
  expect(code).not.toMatch(/status = '(withdrawn|quarantined|deleted)'/)  // no new status vocabulary
})

test('history: one entry per changed field with before, after, reason and actor; drawer reads it back (bounded)', () => {
  expect(code).toContain("select case v_kind when 'matrix' then 'entry_matrix' else 'course_entry' end, v_id, f.key, 'edit', v_cur->f.key, v_new->f.key, v_reason, auth.uid()")
  expect(code).toContain("and (v_cur->f.key) is distinct from f.value;")
  expect(code).toContain("v_id, 'status', a->>'lifecycle', v_cur->'status', v_new->'status', v_reason, auth.uid());")
  expect(m).toContain("and h0.entity_id = v_id order by h0.at desc, h0.id desc limit 50) h left join auth.users u on u.id = h.actor),  -- fixed: 50 history entries")
})

test('re-read: Platform Admin, one source, in scope, AI allowed, nothing waiting, never past a terminal hold; through the existing mechanism', () => {
  expect(code).toContain("if v_rank < 6 then raise exception 'Platform Admin role required' using errcode = '42501'; end if;")
  expect(code).toContain("if not security.entry_matrix_enabled_v1(v_src.provider_id) then raise exception 'this provider is outside the reading scope (entry.providers)'")
  expect(code).toContain("if not security.ai_use_allowed_v1('entry_matrix') then raise exception 'AI reading is stopped (AI limits); nothing was asked'")
  expect(code).toContain("if v_run.state in ('queued', 'leased') then raise exception 'a read of this source is already waiting or running'")
  expect(code).toContain("if v_run.state = 'failed' and v_run.error like 'held_unparsed%' then")
  expect(code).toContain("v_out := public.admin_entry_matrix_reread(array[v_src.id], v_reason);")
  expect(code).not.toMatch(/cron\.schedule|insert into pipeline\.(automation_catalogue|admin_job_kinds)/)
})

test('resolution inspection calls the live resolver unchanged; the consumer API and resolver are not edited', () => {
  expect(code).toContain("v_out := security.entry_resolve_v1(v_id, v_cc);")
  expect(code).not.toMatch(/create or replace function (security\.entry_resolve_v1|security\.entry_(course|matrix)_payload_v1|public\.website_|public\.zoho_|api\.)/)
  expect(m).toMatch(/^-- Replaces: nothing/m)
  expect(m).toMatch(/^-- Retires: /m)
  expect(code).toContain("comment on function public.admin_aer(text, jsonb) is")
})
