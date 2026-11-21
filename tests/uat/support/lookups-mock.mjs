// CF-247 s930 (S1-Dynamic-Lookups): the live lookups (public.admin_lookups_v1) as the mocked screens read them
export const LOOKUPS = {
  as_at: '2026-11-21T01:15:43Z',
  countries: [
    { code: 'AU', name: 'Australia', target: true, providers: 1543, courses: 25685 },
    { code: 'NZ', name: 'New Zealand', target: true, providers: 417, courses: 6514 },
    { code: 'CA', name: 'Canada', target: true, providers: 1130, courses: 3825 },
  ],
  study_levels: [{ id: 'l-ug', code: 'bachelor', name: 'Bachelor' }],
  intake_years: [2026, 2027, 2028],
  providers: { active: 3090, published: 2830 },
}
export const mockLookups = (page, lookups = LOOKUPS) => page.route('**/rest/v1/rpc/admin_lookups_v1', (route) => route.fulfill({ json: lookups }))
