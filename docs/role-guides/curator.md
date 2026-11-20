# StudySearch – Curator guide

**Version:** 1.1 (reviewed for platform release v2.16.61)  
**Role:** Curator (rank 3)  
**Change control:** CF-247  
**Source:** generated from the Pilot `src/guide/roleGuides.js` and the menu; never edited by hand.

## 1. What this role is for

Keep the catalogue right: decide what waits for a person, correct records by hand, and prepare new sources and reference data for a Platform Admin to approve.

## 2. What you can do

- Everything a Counsellor can.
- Open Layer 4 Review › Inbox, read every item, and decide the kinds open to your role (an item whose decision needs a higher role says so and its buttons are greyed); correct course, provider, campus and scholarship values by hand (a value entered by hand is never overwritten by automation).
- Open Layer 1 Register and prepare + Add source drafts (country, record type, field mapping); edit key dates and reference site details.
- Read Destination data, Reference data, Platform health and Evidence.
- Find incomplete records in one click: Missing field pills on Courses and Providers, a Completeness bar on every row, and in a provider's drawer a Completeness and provenance panel (the description's source reads Register, AI verified or Human input · Locked). Tick providers to get a bar with Fill fields, Queue to Intake Run & Validate, Flag primary campus (Platform Admin), Export selected (CSV) and Clear. A Human Locked pill marks any tracked field a person has locked, in the provider and course drawers.
- Layer 2/3 Build & enrich › Operations › Intake Run & Validate: pick approved Australian universities or hand-picked courses and read the stages, evidence and before / after intake values.
- Layer 1 Register › + Add source is where a new country is prepared (country, record type, field mapping).

## 3. What you cannot do

- Activate a source, approve or publish destination data, change settings, run or pause jobs, or manage users. Those buttons are greyed for you, and the server refuses them too.
- Re-infer a parser or send work back to the AI (Pipeline Operator and above).

## 4. Pages you can open

- **Courses**
- **Providers**: Providers, Campuses, Archived
- **Scholarships**: Scholarships, Coverage
- **Entry requirements**: Provider entry matrix, Course entry requirements, Sources, reads and holds, Resolution inspection
- **Rankings & statistics**: Overview, Compare, Datasets
- **Coverage & completeness**: Courses, Attributes
- **Layer 1 Register**
- **Destination data**: Overview & editions, Localities & postcodes, City metrics & costs, Study rules, Careers & outcomes
- **Reference data**
- **Layer 2/3 Build & enrich**: Operations, Universities, Enrich fields, Enrichment plan, Course sources, Flags
- **Layer 4 Review**: Inbox
- **Platform health**: Health checks, Queues & yield, Country & category completeness
- **Evidence**
- **Models & services**: AI
- **Provider contacts**
- **Guides**: Platform guide, Role guides, Platform Admin SOP, Operator SOP

## 5. Where to start

- Layer 4 Review › Review by rule: choose the queue and the largest rule group; work one card at a time.
- Layer 1 Register › + Add source › Continue a draft: finish the mapping, then tell a Platform Admin it is ready to activate.

## 6. Common tasks

### Work the Inbox

1. Open Layer 4 Review (Review by rule opens first).
2. Pick a queue and a rule group; read the quote and the source page; decide it, or correct the record, where your role allows.
3. The decision is kept with who, when and why.

### Fix the incomplete providers in a country

1. Open Providers, choose the country, then the Missing field pills you care about (for example Website).
2. Tick the providers to work on; the bar offers Fill fields (description only), Queue to Intake Run & Validate, Flag primary campus (Platform Admin) and Export selected (CSV).
3. Open a provider: the Completeness and provenance panel shows what is held, what is missing and where the description came from.

### Prepare a new source for a country

1. Open Layer 1 Register › + Add source.
2. Choose the country and the record type, map the fields, note the licence terms.
3. Save the draft. A Platform Admin activates it after a dry run.

## 7. When to ask someone

Anything that needs approving, activating or publishing goes to a Platform Admin; a job that looks stuck goes to a Pipeline Operator.

## 8. Version history

| Version | Date | Release | Change |
|---|---|---|---|
| 1.0 | 18 Nov 2026 | v2.16.35 | First issue. |
| 1.1 | 20 Nov 2026 | v2.16.61 | Completeness, Missing field pills, bulk bar and provenance panel; Intake Run & Validate and Layer 1 country preparation named. |
