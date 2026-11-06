#!/usr/bin/env node
// Guards: decision 19:14 §8 (Platform Admin 5 Nov 2026) for English requirements (Platform Admin 6 Nov 2026 §3): parses fixture pages with the REAL v0.3.0 parser for the database scenarios in groups-tests.sql.
import { loadParser } from './baseline.mjs'
const FACULTY_TABLE = `## IELTS Academic

| Faculty | Undergraduate | Postgraduate coursework |
|---|---|---|
| Social Sciences | Overall 6.5 (no band less than 6.0) | Overall 7.0 (no band less than 6.5) |
| Economics and Law | Overall 7.0 (no band less than 6.5) | Overall 7.0 (no band less than 6.5) |
| Science | Overall 6.0 (no band less than 6.0) | Overall 6.5 (no band less than 6.0) |
`
if (process.argv[1] && import.meta.url.endsWith(process.argv[1].split('/').pop())) {
  const { englishPolicy } = await loadParser()
  if (process.argv[2] === 'parsed-faculty-table') process.stdout.write(JSON.stringify(englishPolicy(FACULTY_TABLE)))
  else { console.error('usage: groups.mjs parsed-faculty-table'); process.exit(2) }
}
export { FACULTY_TABLE }
