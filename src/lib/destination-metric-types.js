// CF-247 S1-RM-Design (Platform Admin 18 Nov 2026 21:23, s695): the Metric type pills on Destination data › City metrics & costs.
// One pill per source family. Climate and population are city figures (destination.locality_metrics by metric_category);
// careers are occupation outcomes (career_outcome rows) and study rules are visa and living-cost rules (study_rule rows),
// so those two pills show their own lists in place, with any living-cost city figures beside the rules.

export const METRIC_TYPES = [
  { key: 'all', label: 'All' },
  { key: 'climate', label: 'Climate & Weather (BOM)', source: 'Bureau of Meteorology', categories: ['climate', 'weather'] },
  { key: 'population', label: 'Population & Demographics (ABS)', source: 'Australian Bureau of Statistics', categories: ['population', 'demographics', 'demographic'] },
  { key: 'careers', label: 'Careers, Jobs & Salaries (JSA)', source: 'Jobs and Skills Australia', categories: ['careers', 'jobs', 'salary', 'labour_market'], kind: 'career_outcome' },
  { key: 'rules', label: 'Study Rules & Living Costs (Home Affairs)', source: 'Department of Home Affairs', categories: ['cost_of_living', 'living_cost', 'living_costs', 'rent'], kind: 'study_rule' },
]

export function metricTypeOf(row) {
  const c = String(row?.metric_category || '').toLowerCase()
  return METRIC_TYPES.find(t => (t.categories || []).includes(c))?.key || null
}
export function filterMetrics(rows, type) {
  const list = Array.isArray(rows) ? rows : []
  return !type || type === 'all' ? list : list.filter(r => metricTypeOf(r) === type)
}
// counts per pill from the loaded city figures (careers and rules are counted by their own lists when loaded)
export function countByType(rows, extra = {}) {
  const out = Object.fromEntries(METRIC_TYPES.map(t => [t.key, 0]))
  for (const r of rows || []) { out.all++; const k = metricTypeOf(r); if (k) out[k]++ }
  for (const [k, n] of Object.entries(extra)) if (n != null && k in out) out[k] += Number(n) || 0
  return out
}
export const readTypeParam = () => { try { const v = new URLSearchParams(String(location.hash).split('?')[1] || '').get('type'); return METRIC_TYPES.some(t => t.key === v) ? v : 'all' } catch { return 'all' } }
