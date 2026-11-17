-- CF-247 v2.15.301 (20 Oct 2026). Platform Admin 19:23: "Ask me nav menu wise and its tab wise questions with its use and recommended choice
-- to keep, move or retire"; answers 19:2x; 19:31 "Go". The UI release moves and retires the screens below; this records them in the
-- component register (screens only). No function, table or job changes; every old address redirects in the admin shell (src/nav-map.js).
--   Scholarships › Extraction            → Models & services › AI & OpenRouter ("Move to Models & services › AI")
--   Reference data › Key dates, › Reference sources → Reference data (one list, type filter); › Ranking imports → Rankings & statistics › Datasets
--   Coverage & completeness › Progress   → Running now and Levers views retired (Overview and Journeys kept)
--   Coverage & completeness › Flags      → Layer 2/3 Build & enrich › Flags
--   Layer 1 Register › Scholarships      → Layer 2/3 Build & enrich › Scholarships (one tab: finding, then reading)
--   Sources and Layer 1 Register › Sources → Layer 1 Register (one Sources page with a layer filter; registers first)
--   Platform health › Capacity           → Go-live checklist
--   API usage                            → Settings › API usage (Pipeline Operator and above, as before)
--   Data model                           → retired (read only; the attribute data stays); its address opens Coverage & completeness › Attributes
--   Storage & retention                  → Platform health › Storage & retention (Platform Admin only, as before)
-- Replaces: nothing (screens only)
-- Retires: screens Scholarships › Extraction, Reference data › Key dates, Reference data › Reference sources, Reference data › Ranking imports,
--   Coverage & completeness › Flags, Layer 1 Register › Scholarships, Layer 1 Register › Sources, Sources, Platform health › Capacity,
--   API usage, Data model, Storage & retention (their content lives on in the new places; nothing to drop)
-- Nothing dropped or deleted. Consumer API not touched (Decision 266).

update pipeline.component_register r set status = 'retired', replaced_by = s.by, note = coalesce(r.note || '; ', '') || 'retired v2.15.301 (Platform Admin 20 Oct 2026 menu review)', updated_at = now()
  from (values
   ('Scholarships › Extraction', 'Models & services › AI & OpenRouter (Scholarship extraction)'),
   ('Reference data › Key dates', 'Reference data (one list, type Key dates)'),
   ('Reference data › Reference sources', 'Reference data (one list, type Reference sources)'),
   ('Reference data › Ranking imports', 'Rankings & statistics › Datasets (Ranking imports)'),
   ('Coverage & completeness › Flags', 'Layer 2/3 Build & enrich › Flags'),
   ('Layer 1 Register › Scholarships', 'Layer 2/3 Build & enrich › Scholarships'),
   ('Layer 1 Register › Sources', 'Layer 1 Register (Sources, Registers filter)'),
   ('Sources', 'Layer 1 Register (Sources, All layers filter)'),
   ('Platform health › Capacity', 'Go-live checklist (Capacity)'),
   ('API usage', 'Settings › API usage'),
   ('Data model', 'Nothing: retired (read only, no use); Coverage & completeness › Attributes'),
   ('Storage & retention', 'Platform health › Storage & retention')) s(name, by)
 where r.kind = 'screen' and r.name = s.name and r.status <> 'retired';

update pipeline.component_register set note = coalesce(note || '; ', '') || 'v2.15.301: Running now and Levers views retired; Overview and Journeys kept', updated_at = now()
 where kind = 'screen' and name = 'Coverage & completeness › Progress' and coalesce(note, '') not like '%v2.15.301%';
update pipeline.component_register set note = coalesce(note || '; ', '') || 'v2.15.301: Waiting for you is the Layer 4 Inbox by kind', updated_at = now()
 where kind = 'screen' and name = 'Dashboard' and coalesce(note, '') not like '%v2.15.301%';

insert into pipeline.component_register(kind, name, layer, purpose, status, introduced_in) values
 ('screen', 'Layer 2/3 Build & enrich › Flags', 'Layer 2/3', 'The flag unit: what is held out of the queues, why, and its history; release or hold (moved from Coverage)', 'active', '20261020110000'),
 ('screen', 'Layer 2/3 Build & enrich › Scholarships', 'Layer 2/3', 'Finding scholarships (countries and sources) and reading them (jobs and limits), one tab', 'active', '20261020110000'),
 ('screen', 'Settings › API usage', 'Platform', 'Calls to Zoho API v2 and Website API v2 by key and action; rotate or switch off keys (moved from the API usage page)', 'active', '20261020110000'),
 ('screen', 'Platform health › Storage & retention', 'Platform', 'What takes space, the rule for each category, and purging it (moved from its own page)', 'active', '20261020110000')
on conflict (kind, name) do nothing;
