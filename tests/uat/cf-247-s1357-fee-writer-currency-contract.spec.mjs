// Guards: SS-Programme-Control PC-20261128-CONTINUOUS-BUILD-EXECUTE (28 Nov 2026, S1-RM-Design): fee writers record an explicit valid source currency or the provider country's currency, never AUD by default, and hold an unknown currency (s1357).
import { test, expect } from "@playwright/test";
import fs from "node:fs";
import path from "node:path";

const MIGRATION = path.join(
  process.cwd(),
  "supabase/migrations/20261201130000_cf247_s1357_fee_writer_currency_country_neutral.sql",
);
const sql = fs.readFileSync(MIGRATION, "utf8");

// The text each guarded DO block writes in (the $nN$ ... $nN$ literals).
const replacements = [...sql.matchAll(/\$n(\d+)\$([\s\S]*?)\$n\1\$/g)].map((m) => m[2]);
const blocks = sql.split(/^-- (?=[a-z_]+\.[a-z0-9_]+: \d+ edit)/m).slice(1);

const WRITERS = [
  "security.fee_rule_run_v1(bigint, boolean, uuid)",
  "security.provider_rule_admit_v1(boolean, integer)",
  "security.provider_basis_rule_admit_v1(boolean, integer)",
  "public.svc_coursefacts_apply_record(uuid, uuid, text, text, text, text, text, jsonb, boolean)",
  "security.layer4_tuition_apply_impl(uuid, uuid, jsonb, text)",
  "security.layer3_tuition_admit_assumed_annual_v1(integer)",
  "security.adapter_overwrite_v1(integer)",
];

test.describe("s1357 fee writers: country-neutral currency", () => {
  test("one resolver: explicit active ISO code wins, else the provider country's currency, else null", () => {
    expect(sql).toContain("create or replace function security.fee_currency_resolve_v1(p_provider_id uuid, p_explicit text default null)");
    expect(sql).toMatch(/cy\.code = upper\(btrim\(p_explicit\)\) and cy\.status = 'active'/);
    expect(sql).toMatch(/join ref\.currencies cy on cy\.code = k\.default_currency_code and cy\.status = 'active'/);
    expect(sql).toContain("comment on function security.fee_currency_resolve_v1(uuid, text)");
    expect(sql).toMatch(/revoke all on function security\.fee_currency_resolve_v1\(uuid, text\) from anon, authenticated;/);
    expect(sql).toMatch(/grant execute on function security\.fee_currency_resolve_v1\(uuid, text\) to service_role;/);
    // the resolver itself never names a currency
    const resolver = sql.slice(sql.indexOf("create or replace function security.fee_currency_resolve_v1"), sql.indexOf("comment on function"));
    expect(resolver).not.toMatch(/'[A-Z]{3}'/);
  });

  test("each of the seven writers is edited from its live definition, every marker found exactly once", () => {
    for (const fn of WRITERS) {
      expect(sql, fn).toContain(`pg_get_functiondef('${fn}'::regprocedure)`);
    }
    expect(blocks.length).toBe(WRITERS.length);
    for (const b of blocks) {
      const edits = [...b.matchAll(/d := replace\(d, \$o(\d+)\$/g)].length;
      const checks = [...b.matchAll(/marker is not found exactly once/g)].length;
      expect(edits).toBeGreaterThan(0);
      expect(checks).toBe(edits);
      expect(b).toContain("execute d;");
    }
  });

  test("no fixed AUD value, AUD default, country map or AUD/NZD/CAD allowlist is written back", () => {
    for (const r of replacements) {
      expect(r).not.toMatch(/,\s*'AUD'\s*,/); // a fixed currency value in an insert
      expect(r).not.toMatch(/'AUD'\)\s*;/); // coalesce(..., 'AUD')
      expect(r).not.toMatch(/else 'AUD' end/); // country map with an AUD fallback
      expect(r).not.toMatch(/in \('AUD','NZD','CAD'\)/); // allowlist
      expect(r).not.toMatch(/when 'NZ' then 'NZD'/);
      // the only AUD literal allowed is an explicit A$/AUD marker read from the source text
      for (const m of r.matchAll(/'AUD'/g)) {
        expect(r.slice(Math.max(0, m.index - 80), m.index)).toMatch(/~\* '\(\^\|\[\^a-z\]\)\(aud\(\[\^a-z\]\|\$\)\|a\\s\*\\\$\)' then $/);
      }
    }
  });

  test("an unknown currency is held or refused, never written as null", () => {
    expect(sql).toContain("if v_cur is null then n_cur := n_cur + 1; continue; end if;");
    expect(sql).toContain("'currency_unknown', n_cur");
    expect(sql).toContain("if v_code is null or v_source is null or v_cur is null then continue; end if;");
    expect(sql).toContain("outcome = 'currency not known (held)'");
    expect(sql).toContain("if v_cur is null then v_cur_unknown:=v_cur_unknown+1; continue; end if;");
    expect(sql).toContain("'currency_unknown',v_cur_unknown");
    expect(sql).toContain("if v_currency is null then raise exception 'currency not known:");
    expect(sql).toContain("if v_cur is null then raise exception 'currency must be an active ISO currency code");
    expect(sql).toContain("or v_cur is null or not exists (select 1 from ref.currencies cy where cy.code = v_cur and cy.status = 'active')");
    expect(sql).toContain("and v_fee is not null and v_cur is not null and v_fee between");
  });

  test("housekeeping: Replaces/Retires, no drop, delete, truncate, table, job or consumer API object", () => {
    expect(sql).toMatch(/^-- Replaces: /m);
    expect(sql).toMatch(/^-- Retires: nothing\./m);
    const code = sql.replace(/^--.*$/gm, "");
    expect(code).not.toMatch(/\b(drop|truncate)\s/i);
    expect(code).not.toMatch(/\bdelete\s+from\b/i);
    expect(code).not.toMatch(/\bcreate\s+table\b/i);
    expect(code).not.toMatch(/cron\.schedule/i);
    expect(code).not.toMatch(/website_v2_|website_edge_|website_api_v2_|zoho_edge_|svc_website_settings_v1|\bapi\./);
  });
});
