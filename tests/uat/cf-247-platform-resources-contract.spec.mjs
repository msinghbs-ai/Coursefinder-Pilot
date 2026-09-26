import { test, expect } from '@playwright/test'
import fs from 'node:fs'

// Decision 153: platform resources and cost are shown first in Environment & Migration.
test('Platform resources panel: mounted, governed reads, admin-only cost edits, unique refresh name',async()=>{
  const ws=fs.readFileSync('src/EnvironmentMigrationWorkspace.jsx','utf8')
  expect(ws).toContain("import PlatformResourcesPanel from'./PlatformResourcesPanel'")
  expect(ws).toContain('<PlatformResourcesPanel onError={onError}/>')
  const panel=fs.readFileSync('src/PlatformResourcesPanel.jsx','utf8')
  expect(panel).toContain("rpc('admin_platform_resources_read_v1'")
  expect(panel).toContain("rpc('admin_platform_cost_model_save_v1'")
  expect(panel).toContain("const editable=data.can_edit&&it.basis!=='usage_actual'")
  expect(panel).toContain('aria-label="Refresh resources"')
  expect(panel).not.toContain('>Refresh</button>')
  expect(panel).toContain("rpc('admin_admission_lifecycle_read_v1'")
  expect(panel).toContain('<h3>Admission lifecycle</h3>')
})
