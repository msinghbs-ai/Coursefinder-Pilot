// Guards: G2 (no operational value in code) for the THE and QS public readers: the apply batch size is the pipeline setting reading.ranking_apply_batch_rows
// s969 (third fix to s966): a re-read of a published edition (every row an update) passed the 8 s statement limit in batches of 200. The batch
// size is now a setting read through svc_worker_settings_v1, and a re-read keeps the edition's public access.
import { test, expect } from '@playwright/test'
import fs from 'node:fs'

const ETL = fs.readFileSync('supabase/functions/ranking-layer1-etl/index.ts', 'utf8')
const MIG = fs.readFileSync('supabase/migrations/20261122140000_cf247_s969_ranking_apply_batch_setting.sql', 'utf8')

test('s969: batch size from the setting; public access kept on a re-read; THE re-read queued after deploy', () => {
  expect(ETL).toContain('const VERSION="ranking-layer1-etl-v1.8.2"')
  expect(ETL).toContain('service.rpc("svc_worker_settings_v1",{})')
  expect(ETL).toContain('(ws||{})["reading.ranking_apply_batch_rows"]')
  expect(ETL).not.toMatch(/const batchSize=\d+/)
  expect(MIG).toContain("('pipeline', 'reading.ranking_apply_batch_rows', 'Ranking rows applied a call',")
  expect(MIG).toContain("'number', '50'::jsonb, 10, 500, 'rows a call', 900, 'Job sizes', 'ranking-layer1-etl (THE and QS Layer 1 readers)'")
  expect(MIG).toContain("select pg_temp.edit_re('public.svc_ranking_ingest_apply(text,integer,text,text,uuid,text,text,jsonb)', '2cca41270f90cca1fc9e2b9286f984b4'")
  expect(MIG).toContain("access_status=case when editions.access_status='public' then 'public' else 'licensed_upload' end")
  expect(MIG).toContain("'s969-reread:' || s.id::text")
  expect(MIG).toMatch(/^-- Replaces: /m)
  expect(MIG).toContain('security.consumer_api_check_v1()')
  expect(MIG).not.toMatch(/cron\.schedule|\bdrop (table|function|index|schema|view|trigger)|delete from |truncate /i)
})
