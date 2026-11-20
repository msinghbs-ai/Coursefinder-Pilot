# StudySearch – Platform Admin guide

**Version:** 1.1 (reviewed for platform release v2.16.61)  
**Role:** Platform Admin (rank 6)  
**Change control:** CF-247  
**Source:** generated from the Pilot `src/guide/roleGuides.js` and the menu; never edited by hand.

## 1. What this role is for

Own the platform: approve and publish, activate sources, set limits and settings, manage users, and keep the go-live checklist.

## 2. What you can do

- Everything every other role can.
- Approve and publish destination data (Bulk Approve Drafts, Publish edition), activate Layer 1 sources after a dry run, approve central pages and fee schedules.
- Change settings, models, services and limits; manage users and roles; edit the Links & Email Templates and the email delivery provider.
- Everything a Curator does with completeness and provenance. The Missing field filter for Providers is the `missing` argument of the providers read (one list of fields); nothing in it writes to the catalogue.

## 3. What you cannot do

- Nothing is closed to you, but every approval, activation and setting change needs a reason and is kept in the control log; a passing test never switches anything on by itself.

## 4. Pages you can open

- **Courses**
- **Providers**: Providers, Campuses, Logos & assets, Archived
- **Scholarships**: Scholarships, Coverage
- **Entry requirements**: Provider entry matrix, Course entry requirements, Sources, reads and holds, Resolution inspection
- **Rankings & statistics**: Overview, Compare, Datasets
- **Coverage & completeness**: Courses, Attributes
- **Layer 1 Register**
- **Destination data**: Overview & editions, Localities & postcodes, City metrics & costs, Study rules, Careers & outcomes
- **Reference data**
- **Layer 2/3 Build & enrich**: Operations, Universities, Enrich fields, Enrichment plan, Adapter builder, Course sources, Flags, Scholarships
- **Layer 4 Review**: Inbox
- **Human Edits & Periodic Audit**: My Human Edits, All Human Edits (Admin Governance)
- **Platform health**: Health checks, Queues & yield, Integration queue, Storage & retention, Country & category completeness
- **Scheduled jobs**: Automations, Jobs, Task manager
- **Evidence**
- **Settings**: Settings, Integrations, API usage, Backup & restore
- **Models & services**: Services & limits, AI
- **Go-live checklist**
- **Users & roles**: Users & roles, Links & Email Templates
- **Provider contacts**
- **Guides**: Platform guide, Role guides, Platform Admin SOP, Operator SOP

## 5. Where to start

- Dashboard: the five cards and Active failures, then Layer 1 Register and Layer 4 Review for what only you can do.
- Follow the Platform Admin SOP (Guides › Platform Admin SOP) for the daily routine.

## 6. Common tasks

### Invite a person

1. Open Users & roles › Create user.
2. Enter the email and name, choose one role (its permissions are shown), choose Send invitation.
3. Review and create: the person gets an email whose link opens the admin sign-in.

### Publish a destination edition

1. Approve its localities and figures (Bulk Approve Drafts on each tab).
2. Record the edition terms, then Publish edition on Overview & editions with a reason.

## 7. When to ask someone

Changes to the consumer API need your recorded approval (G3); drops and deletes go out as a paste file, never a migration.

## 8. Version history

| Version | Date | Release | Change |
|---|---|---|---|
| 1.0 | 18 Nov 2026 | v2.16.35 | First issue. |
| 1.1 | 20 Nov 2026 | v2.16.61 | Completeness and provenance workflows added. |
