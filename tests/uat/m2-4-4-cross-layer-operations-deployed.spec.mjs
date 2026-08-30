import fs from 'node:fs/promises'
import { test, expect } from '@playwright/test'

test.describe('M2.4.4 cross-layer operations and housekeeping @deployed',()=>{
  test('checked-in recovery, retention, scheduler and Layer 3 alert contracts remain governed',async()=>{
    const l1=await fs.readFile('supabase/migrations/20260830021400_m2_4_4_layer1_legacy_stale_job_recovery.sql','utf8')
    expect(l1).toContain("j.job_type = 'regulatory_sync'")
    expect(l1).toContain("interval '45 minutes'")
    expect(l1).toContain("interval '30 minutes'")
    expect(l1).toContain("'governed_evidence_deleted', 0")
    expect(l1).toContain("'source_versions_deleted', 0")
    expect(l1).toContain("'canonical_history_deleted', 0")

    const l2=await fs.readFile('supabase/migrations/20260827224000_m2_4_2_layer2_refresh_housekeeping.sql','utf8')
    expect(l2).toContain('coursefinder-layer2-refresh-dispatcher')
    expect(l2).toContain('coursefinder-layer2-housekeeping')
    expect(l2).toContain('layer2_run_batch_recover_stuck')
    expect(l2).toContain('governed_evidence_deleted')

    const l3Recovery=await fs.readFile('supabase/migrations/20260829130640_m2_4_3_layer3_concurrency_recovery_housekeeping.sql','utf8')
    expect(l3Recovery).toContain("interval '20 minutes'")
    expect(l3Recovery).toContain('layer3_housekeeping_service')
    expect(l3Recovery).toContain("'history_deleted',false")

    const alerts=await fs.readFile('supabase/migrations/20260830071523_m2_4_4_layer3_operational_alerts.sql','utf8')
    expect(alerts).toContain('layer3_operational_alerts_read')
    expect(alerts).toContain("'stale_execution'")
    expect(alerts).toContain("'unqualified_profile'")
    expect(alerts).toContain("'latest_benchmark_failed'")
    expect(alerts).toContain("'provider_error_streak'")
    expect(alerts).toContain("'cost_ceiling_exceeded'")
    expect(alerts).toMatch(/revoke all on function security\.layer3_operational_alerts_read\(\) from anon/i)
    expect(alerts).toMatch(/grant execute on function security\.layer3_operational_alerts_read\(\) to authenticated/i)

    const bridge=await fs.readFile('supabase/migrations/20260830072215_m2_4_4_layer3_alert_admin_read_bridge.sql','utf8')
    expect(bridge).toContain("p_operation='layer3_ops_alerts'")
    expect(bridge).toContain('security.layer3_operational_alerts_read()')
    expect(bridge).toContain('Layer 2 alert dispatch marker not found')
  })
})
