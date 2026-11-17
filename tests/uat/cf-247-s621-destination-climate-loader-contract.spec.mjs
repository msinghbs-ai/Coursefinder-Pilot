// Guards: RM1I climate figures (Platform Admin 18 Nov 2026 10:31 "build the non-breaking ingestion/refresh pipeline into destination.locality_metrics (with source attribution and /destination API v3 exposure)"; Study Square 13 Nov: long-term climate averages, summer and winter averages and annual rainfall): BOM pages are read and parsed deterministically, figures load as draft with attribution and evidence (Platform Admin 10:44: load into draft editions; terms and publication stay the Platform Admin's; a dry run or a restricted edition writes nothing), a reviewed figure is never changed, and the consumer API is not reshaped.
// CF-247 S621. supabase/migrations/20261118123000_cf247_rm1i_destination_climate_loader.sql, supabase/functions/_shared/cf247-bom-climate.js, supabase/functions/layer1-destination-geo-loader/index.ts.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'
import { parseBomClimate, parseStatisticRow } from '../../supabase/functions/_shared/cf247-bom-climate.js'

const M = fs.readFileSync('supabase/migrations/20261118123000_cf247_rm1i_destination_climate_loader.sql', 'utf8')
const E = fs.readFileSync('supabase/functions/layer1-destination-geo-loader/index.ts', 'utf8')

const row = (label, vals, annual, years, from, to) => `<tr><th>${label}</th>${vals.map((v) => `<td>${v}</td>`).join('')}<td>${annual}</td><td>${years}</td><td>${from}<br>${to}</td></tr>`
const PAGE = `<p>Site number: <b>086071</b></p><table><tr><th>Statistics</th><th>Jan</th><th>Feb</th><th>Mar</th><th>Apr</th><th>May</th><th>Jun</th><th>Jul</th><th>Aug</th><th>Sep</th><th>Oct</th><th>Nov</th><th>Dec</th><th>Annual</th><th>Years</th><th>Plot</th></tr>
${row('Mean maximum temperature (&deg;C)', [25.9, 25.8, 23.9, 20.3, 16.7, 14.1, 13.4, 14.9, 17.2, 19.7, 22.0, 24.2], 19.8, 161, 1855, 2015)}
${row('Highest temperature (&deg;C)', [46.4, 45.6, 41.7, 34.9, 28.7, 22.4, 23.1, 26.5, 31.4, 36.9, 40.9, 43.7], 46.4, 156, 1859, 2015)}
${row('Mean minimum temperature (&deg;C)', [14.3, 14.6, 13.2, 10.8, 8.6, 6.9, 6.0, 6.7, 8.0, 9.6, 11.4, 13.0], 10.3, 161, 1855, 2015)}
${row('Mean rainfall (mm)', [47.6, 47.5, 50.7, 57.5, 56.2, 49.4, 47.6, 50.2, 58.4, 66.4, 59.8, 59.3], 650.0, 160, 1855, 2015)}
</table><p>Product IDCJCM0037 Prepared at Thu 26 Feb 2026 01:31:41 AM AEDT</p>`

test('the BOM reader takes the three monthly statistics, the years of record and the station number from the page', () => {
  const p = parseBomClimate(PAGE)
  expect(p.station).toBe('086071')
  expect(p.prepared).toBe('Thu 26 Feb 2026 01:31:41 AM AEDT')
  expect(p.missing).toEqual([])
  expect(p.statistics.mean_max_temp_c).toEqual({ months: [25.9, 25.8, 23.9, 20.3, 16.7, 14.1, 13.4, 14.9, 17.2, 19.7, 22.0, 24.2], annual: 19.8, first_year: 1855, last_year: 2015 })
  expect(p.statistics.mean_rainfall_mm.annual).toBe(650)
  expect(parseStatisticRow(['Mean rainfall (mm)', '1', '2'])).toBeNull()
  expect(parseBomClimate('<table><tr><td>nothing</td></tr></table>').missing).toEqual(['mean_max_temp_c', 'mean_min_temp_c', 'mean_rainfall_mm'])
})

test('the load writes draft figures with attribution, holds on a dry run or restricted terms, and keeps reviewed figures', () => {
  expect(M).toContain("'BOM Climate statistics for Australian locations (IDCJCM0037)', current_date, 'draft', 'https://www.bom.gov.au/climate/averages/'")
  expect(M).toContain("'pending', now()")
  expect(M).toContain("v_hold := v_ed.terms_status = 'restricted' or coalesce((p_payload->>'dry_run')::boolean, false);")
  expect(M).toContain("if v_hold then continue; end if;")
  expect(M).toContain("v_kept := v_kept + 1;  -- approved, published, superseded or withdrawn: never changed by a load")
  expect(M).toContain("values (v_st.locality_id, 'climate', m.key, v_val, m.unit, v_period, v_ed.edition_label, x->>'page_url',")
  expect(M).toContain("v_ed.attribution_text || ' Station ' || v_st.station_name || ' (' || v_st.station_id || ').', 'draft', v_ev);")
  for (const k of ['climate_summer_mean_max_c', 'climate_summer_mean_min_c', 'climate_winter_mean_max_c', 'climate_winter_mean_min_c', 'climate_annual_rainfall_mm']) expect(M).toContain(`'${k}'`)
  expect(M).toContain("array[12,1,2]::smallint[], array[6,7,8]::smallint[]")
  expect(M).toContain("raise exception 'post-check: the climate edition terms stay pending until the Platform Admin records them'")
  expect(M).toContain("'dry_run', true, 'stations'")
  expect(M).not.toMatch(/terms_status\s*=\s*'approved'\s*(,|where|$)/m)
})

test('a catalogued monthly job and Run now reach the loader; nothing is deleted and the consumer API is not touched', () => {
  expect(M).toContain("select cron.schedule('destination-climate-load', '30 18,19 * * *', 'select pipeline.svc_pilot_submit_nonce(''layer1-destination-geo-loader'', jsonb_build_object(''mode'', ''climate'', ''trigger'', ''schedule'')) where security.destination_climate_load_due_v1()');")
  expect(M).toContain("('destination-climate-load', 'Layer 1 register', 301, 'Destination: BOM climate averages',")
  expect(M).toContain("if md5(v_src) <> 'd16a59eddf235cbb23a8cefa0f69b1e6' then raise exception")
  expect(M).toContain("('destination-climate-load', 'layer1-destination-geo-loader', jsonb_build_object('mode', 'climate'))")
  expect(M).toMatch(/-- Replaces: nothing/)
  expect(M).toMatch(/-- Retires: nothing\./)
  expect(M).toMatch(/comment on table destination\.climate_stations is/)
  expect(M).not.toMatch(/^\s*(delete from|drop |truncate )/im)
  expect(M).not.toMatch(/create or replace function public\.(website_|zoho_|svc_website_settings)/)
  expect(E).toContain('import { parseBomClimate } from "../_shared/cf247-bom-climate.js";')
  expect(E).toContain('if (clean(body.mode) === "climate") return await climate(service, runId, trigger, started);')
  expect(E).toContain('throw new Error(`page is station ${parsed.station}, expected ${st.station_id}`)')
  expect(E).toContain('const VERSION = "layer1-destination-geo-loader-v1.1.0";')
})
