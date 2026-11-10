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
| `monash-summary-dates.md` | `574a5dde-dc9b-481f-9b02-d43b2b1b4a77` | The table header and the two teaching-period rows verbatim (11 Nov 2026, `provider_facts_inspect`); other rows cut. |
| `flinders-semester-dates.md` | `21294194-3b87-4059-b468-d94a0d463775` | The year header and the Summer, Semester one and Semester two week 1 rows verbatim (11 Nov 2026). |
| `deakin-2027-trimester.md` | `16322681-6faf-46ae-9d97-4e73a93d968b` | Title, headings and three Trimester 1 rows verbatim (11 Nov 2026). |
| `qut-teaching-periods.md` | `1d03e3ca-04ce-4962-8405-3bef4eb5d51b` | The 2026/2027 year headings and three Semester blocks verbatim (11 Nov 2026). |

Decisions 270 and 270a (calendar-v2.2, `cf-247-s528-calendar-edition-year-contract`): real values asserted are Monash Semester 1 = 1 Mar 2027 and 28 Feb 2028, Semester 2 = 26 Jul 2027 (column years), Flinders Semester one week 1 = 1 March 2027, Deakin Trimester 1 = 1 March 2027 (a Monday) and QUT Semester 1 = 22 February 2027. Note: the stored Monash copy has a year header row (`| | 2026 | 2027 | 2028 |`), so it resolves by column; the range-heading rule (270a) is proved on the same table with the header blanked.

