// CF-247 AER missing-university follow-up (Platform Admin approval 3 Nov 2026 18:14 §1): lists the requirement-document links in stored copies or
// a directly fetched landing page, so the ACU, CQU and Deakin sources can be verified. Free and read only: it reads local files only.
// Usage: node extract-links.mjs <file> [<file> ...]   (files: the stored .md.gz / .html.gz copies downloaded from bucket "evidence", or .html)
// Prints each link whose text or address names academic or entry requirements, a country or qualification table, or a PDF, with its base host.
import fs from 'node:fs'
import zlib from 'node:zlib'
const want = /(academic|entry|admission|requirement|countr|qualification|equivalen|minimum|\.pdf\b|\/-\/media\/|__data\/assets)/i
for (const f of process.argv.slice(2)) {
  let buf = fs.readFileSync(f)
  if (buf[0] === 0x1f && buf[1] === 0x8b) buf = zlib.gunzipSync(buf)
  const text = buf.toString('utf8'), seen = new Set()
  const md = [...text.matchAll(/\[([^\]]{0,200})\]\((https?:\/\/[^)\s]+|\/[^)\s]+)\)/g)].map((m) => [m[1], m[2]])
  const html = [...text.matchAll(/<a\b[^>]*href="([^"]+)"[^>]*>([\s\S]{0,300}?)<\/a>/gi)].map((m) => [m[2].replace(/<[^>]+>/g, ' ').replace(/\s+/g, ' ').trim(), m[1]])
  console.log(`# ${f}`)
  for (const [label, href] of [...md, ...html]) {
    if (!(want.test(label) || want.test(href)) || seen.has(href)) continue
    seen.add(href); console.log(`${href}\t${label.slice(0, 120)}`)
  }
}
