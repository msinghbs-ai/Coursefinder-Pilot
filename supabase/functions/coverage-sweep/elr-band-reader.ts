// CF-247 s906 (session S1-ELR-Bands-And-Crawl, Platform Admin 21 Nov 2026 09:00 AEDT): elr-band-v1.0, a pure, deterministic reader of the English band a stored course
// page names ("English language band: B", "English band 2", "| English language band | B |", "English level 3"), for a university whose central English page defines
// those bands (elr-central-v1.2 band_defs). No model, no fetch, no write. Only the labels the university defines are reported; IELTS sub-score wording ("band 6.0",
// "no band below 6.0", "IELTS band 7") is never a band. The database decides what the label means (security.elr_band_record_v1).
export const ELR_BAND_VERSION = "elr-band-v1.0"
export type BandMention = { band: string; quote: string }

// "English (language) (proficiency) (entry) (requirement(s)) [:–-] (is) (Band|Level) X"
const INLINE = /\bEnglish(?:\s+language)?(?:\s+proficiency)?(?:\s+(?:entry\s+)?requirements?)?(?:\s+(?:band|level))?\s*(?:[:\-–]\s*|\s+is\s+|\s+)\(?\s*(band|level)?\s*([A-F]|[1-9])(?![.\d])\b/gi
// a table row: "| English language band | B |"
const CELL = /\bEnglish(?:\s+language)?(?:\s+proficiency)?\s+(band|level)\b[^|\n]*\|\s*(?:(?:band|level)\s+)?([A-F]|[1-9])\s*\|/i

export function bandMentions(text: string, known: string[]): BandMention[] {
  const want = new Set(known.map((k) => k.toLowerCase()))
  const out = new Map<string, string>()
  for (const raw of text.split(/\n/)) {
    const line = raw.trim()
    if (!line || !/\bEnglish\b/i.test(line)) continue
    const cell = line.match(CELL)
    if (cell) { const b = `${cell[1].toLowerCase()} ${cell[2].toUpperCase()}`; if (want.has(b.toLowerCase()) && !out.has(b)) out.set(b, line.slice(0, 300)); continue }
    for (const m of line.matchAll(INLINE)) {
      // the word band/level must be in the phrase ("English band B", "English language level: 2"); a bare "English 6" is not a label
      const phrase = m[0]
      const word = (m[1] || (phrase.match(/\b(band|level)\b/i) || [])[1] || "").toLowerCase()
      if (!word) continue
      const b = `${word} ${m[2].toUpperCase()}`
      if (want.has(b.toLowerCase()) && !out.has(b)) out.set(b, line.slice(0, 300))
    }
  }
  return [...out].map(([band, quote]) => ({ band, quote }))
}
