# Stored calendar layouts (R1 regression pages)

Excerpts of documents held in `provider_fact_sources` (read through the read-only `provider_facts_inspect` mode on 5 Nov 2026).

| File | Fact source | Fidelity |
|---|---|---|
| `unsw-academic-calendar.md` | `12d60ee8-6cff-4278-bdcf-2da17285936a` | Verbatim from the heading `# Academic calendars` to `Semester 1 2028` (navigation and footer removed). |
| `rmit-2027-he.md` | `3ceff6fc…` | Heading structure and the Semester 1 row verbatim. |
| `swinburne-2027-summary.md` | `9d578424…` | Title, note heading and the four rows verbatim (trailing columns cut). |
| `newcastle-2027.md` | `4d9783db…` | Bold title and grid header verbatim; the "Teaching starts" row is a layout stand-in, not the published dates. |
| `sydney-wall-2026.md` | `65ddfd93…` | The `## 2026` heading layout; the row is a layout stand-in, not the published dates. |

The tests prove where a year comes from, so the layout (headings, tabs, title lines) is what matters. Values asserted as real are the UNSW 2027 terms (15 Feb, 31 May, 13 Sep 2027), RMIT (1 March 2027) and Swinburne (01 Mar 2027).
