// How the data connects (v2.16.42, Platform Admin 18 Nov 2026 14:23: "the end-to-end relational model linking Destinations -> Providers ->
// Courses -> Study Rules & Career Outcomes so Website (Wix) and Zoho teams consume correlated data cleanly"). Shown on Guides › Platform guide
// (section How the data connects) and mirrored to the admin repo (docs/platform/ENTITY-CORRELATION-MODEL.md). Every API path below is a live,
// undeprecated Website API v3 path in ref.api_field_dictionary (checked 18 Nov 2026); the website and Zoho read the same shapes.
export const ENTITY_LINKS=[
  { from:'Destination', to:'Provider', key:'country_code, then locality_id',
    how:'A destination is a country (country_code) and its localities (locality_id). A provider belongs to a country, and each campus is placed in a locality by its postcode once that locality is approved.',
    paths:['destination: localities[].country_code, localities[].locality_id','provider: item.country_code, item.campuses[].locality.locality_id, item.campuses[].is_primary'] },
  { from:'Provider', to:'Course', key:'the course\'s provider and campuses',
    how:'A course carries its provider and the campuses it runs at, with the same locality. Use the primary campus when one place is needed. Accreditations (AACSB, EQUIS, AMBA and national quality ratings) belong to the provider and are repeated on every course.',
    paths:['course: item.country_code, item.campuses[].locality.locality_id, item.campuses[].is_primary, item.provider.accreditations[].body_code','provider: item.accreditations[].body_code'] },
  { from:'Course', to:'Course facts', key:'the course item',
    how:'Study load (full-time, part-time or both) and, for a course with no campus, why (empty_reason_code). Entry requirements (AER) are the course\'s own, with the basis they rest on. Scholarships linked to the course come with it.',
    paths:['course: item.study_load, item.empty_reason_code, item.entry_requirements.summary, item.entry_requirements.basis, item.scholarships[].name','search: items[].study_load, items[].entry_requirements.summary'] },
  { from:'Course', to:'Study rules & career outcomes', key:'country_code (rules), country_code and locality_id (outcomes)',
    how:'Visa, work and study rules apply to the whole country: join on the course\'s country_code. Career outcomes are by country and, where published, by locality: join on country_code and the campus locality_id. City figures (population, climate, living costs) are on the locality.',
    paths:['destination: study_rules[].country_code, study_rules[].rule_category, study_rules[].title','destination: career_outcomes[].country_code, career_outcomes[].locality_id, career_outcomes[].occupation_scheme, career_outcomes[].occupation_code','destination: localities[].metrics[].category, localities[].metrics[].key, localities[].metrics[].value, localities[].metrics[].unit'] },
]
export const ENTITY_RULES=[
  'Join on the codes, never on names: country_code (ISO 3166-1 alpha-2) and locality_id.',
  'A value that is null is not held; do not read it as zero, none or not offered.',
  'Destination figures, rules and outcomes reach the API only from a published edition with approved terms; their attribution must be shown where they are shown.',
  'Climate figures are long-term averages, not forecasts. The icon rule (sunny, partly cloudy, rain, heavy rain, storm, snow, wind) is in the developer guide and src/lib/climate-icons.js.',
]
