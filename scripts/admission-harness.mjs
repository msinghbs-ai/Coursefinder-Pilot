#!/usr/bin/env node
// CF-247 pre-AI admission harness for pre-ai-admission-v1 (Decision 278; admin docs/audits/studysearch-pre-ai-admission-gate-design.md §6).
// Guarded by tests/uat/cf-247-s543-pre-ai-admission-gate-contract.spec.mjs (it runs --self-test).
// Validates a sample of stored evidence copies end to end against the storage contract and the shadow admission gates, using the worker's own
// pure modules, so what it reports is what the worker would decide. READ ONLY: it downloads objects, never writes, deletes, calls AI or Firecrawl.
//
//   node --experimental-strip-types scripts/admission-harness.mjs --self-test
//   node --experimental-strip-types scripts/admission-harness.mjs --manifest sample.json --dir ./objects     (copies already downloaded)
//   SUPABASE_URL=… SUPABASE_SERVICE_ROLE_KEY=… node --experimental-strip-types scripts/admission-harness.mjs --manifest sample.json --supabase
//
// sample.json is the output of query H1 in docs/audits/sql/admission-integrity-checks.sql (one JSON array of manifest rows with a "lane").
// Exit code 1 means a STORAGE CONTRACT failure (missing object, zero bytes, hash mismatch, path/hash disagreement). Gate rejections are
// measurements and never fail the run.
import { readFile, writeFile } from "node:fs/promises";
import { gunzipSync, gzipSync } from "node:zlib";
import { createHash } from "node:crypto";
import path from "node:path";
import { pathToFileURL } from "node:url";

const argv = process.argv.slice(2);
const opt = (k, d = null) => { const i = argv.indexOf(`--${k}`); return i >= 0 && argv[i + 1] && !argv[i + 1].startsWith("--") ? argv[i + 1] : d };
const flag = (k) => argv.includes(`--${k}`);
const workerDir = path.resolve(opt("worker", "supabase/functions/coverage-sweep"));
const G = await import(pathToFileURL(path.join(workerDir, "admission-gate.ts")).href);

const sha256 = (buf) => createHash("sha256").update(buf).digest("hex");
// the content hash is taken over the decompressed BYTES (G.contentSha256), never over decoded text; the text is decoded the way the worker decodes
// a stored copy (TextDecoder: UTF-8, byte-order mark dropped), so the gate sees the page the worker would send
const decode = (row, bytes) => {
  const raw = new Uint8Array(row.container === "gzip" || /\.gz$/.test(row.storage_path) ? gunzipSync(bytes) : bytes);
  return { raw, text: /pdf/.test(row.content_mime) ? "" : new TextDecoder("utf-8").decode(raw) };
};
async function fetchObject(row) {
  if (flag("supabase")) {
    const base = process.env.SUPABASE_URL, key = process.env.SUPABASE_SERVICE_ROLE_KEY;
    if (!base || !key) throw Error("SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are required with --supabase");
    const r = await fetch(`${base.replace(/\/$/, "")}/storage/v1/object/${row.bucket || "evidence"}/${row.storage_path.split("/").map(encodeURIComponent).join("/")}`, { headers: { authorization: `Bearer ${key}`, apikey: key } });
    if (!r.ok) return { missing: true, status: r.status };
    return { bytes: Buffer.from(await r.arrayBuffer()) };
  }
  const dir = opt("dir"); if (!dir) throw Error("--dir or --supabase is required with --manifest");
  try { return { bytes: await readFile(path.join(dir, row.storage_path)) } } catch { return { missing: true, status: 404 } }
}

async function runManifest() {
  const rows = JSON.parse(await readFile(opt("manifest"), "utf8"));
  const out = [], tally = { rows: rows.length, contract_fail: 0, missing: 0, admit: 0, would_reject: 0, would_park: 0, tokens_saved_estimate: 0 }, byReason = {};
  for (const row of rows) {
    const rec = { evidence_id: row.evidence_id, storage_path: row.storage_path, lane: row.lane };
    const o = await fetchObject(row);
    if (o.missing) { rec.contract = { ok: false, problems: ["object_missing"], status: o.status }; tally.contract_fail++; tally.missing++; out.push(rec); continue }
    const stored = o.bytes.length, { raw, text } = decode(row, o.bytes);
    const m = { ...row, stored_bytes: stored, content_bytes: raw.length };
    rec.contract = await G.verifyManifest(m, raw);
    if (!rec.contract.ok) tally.contract_fail++;
    if (text && row.lane) {
      const d = await G.admit({ lane: row.lane, html: text, url: row.final_url || row.source_url, manifest: m, raw_bytes: raw, linked_sha256: row.linked_sha256 || null,
        prompt_key: row.prompt_key || "harness", model: row.model || "harness", schema_key: row.schema_key || row.lane }, { budget_chars: Number(row.budget_chars) || undefined });
      rec.gate = { would: d.would, reasons: d.reasons.map((r) => r.code), sent_chars: d.sent_chars, tokens_saved_estimate: d.tokens_saved_estimate, signals: { main_chars: d.signals.main_chars, scholarship: d.signals.scholarship?.score, preflight: d.signals.preflight, leak: d.signals.leak } };
      tally[d.would === "admit" ? "admit" : d.would === "park" ? "would_park" : "would_reject"]++; tally.tokens_saved_estimate += d.tokens_saved_estimate;
      for (const r of d.reasons) byReason[r.code] = (byReason[r.code] || 0) + 1;
    }
    out.push(rec);
  }
  const report = { harness: "admission-harness", gate: G.ADMISSION_GATE, at: new Date().toISOString(), tally, by_reason: byReason, rows: out };
  if (opt("out")) await writeFile(opt("out"), JSON.stringify(report, null, 2));
  console.log(JSON.stringify({ tally, by_reason: byReason }, null, 2));
  for (const r of out.filter((x) => !x.contract?.ok)) console.log(`CONTRACT FAIL ${r.storage_path}: ${(r.contract?.problems || []).join(",")}`);
  process.exit(tally.contract_fail ? 1 : 0);
}

// ---------- self-test: fixed fixtures, one per reason, plus admit cases ----------
async function selfTest() {
  const page = (title, body, h1 = title) => `<!doctype html><html><head><title>${title}</title></head><body><nav>Home Study Research</nav><main><h1>${h1}</h1>${body}</main><footer>Privacy</footer></body></html>`;
  const para = (s, n = 1) => `<p>${s}</p>`.repeat(n);
  const course = page("Master of Data Science | Example University",
    "<h2>Overview</h2>" + para("This two-year course builds skills in statistics, machine learning and data engineering for industry roles.", 6) +
    "<h2>Entry requirements</h2>" + para("A bachelor degree in any discipline with a minimum GPA of 4.5 on a 7-point scale.") +
    "<h3>English language requirements</h3>" + para("IELTS Academic 6.5 overall with no band below 6.0.") +
    "<h2>Fees</h2><table><thead><tr><th>Student</th><th>Annual fee</th></tr></thead><tbody><tr><td>International</td><td>AUD 48,000</td></tr></tbody></table>");
  const award = page("Global Excellence Scholarship | Example University",
    para("The Global Excellence Scholarship offers a 25% reduction in tuition fees for international students commencing a coursework degree.") +
    "<h2>Eligibility</h2>" + para("Applicants must be international students holding an offer for full-time study.") +
    "<h2>How to apply</h2>" + para("You are automatically considered when you apply for admission. Applications close 30 November.") );
  const news = page("Campus news | Example University", para("Our rowing team won the regional regatta this weekend and the library opens late during exams.", 8));
  const listing = page("Scholarships", Array.from({ length: 20 }, (_, i) => `<li><a href="/scholarships/award-${i}">Award ${i}</a></li>`).join(""));
  const thin = page("Scholarship", "<p>Loading…</p>");
  const captcha = page("Just a moment...", "<p>Verify you are human by completing the action below. cf-chl</p>");
  const notFound = page("Page not found | Example University", para("Sorry, the page you are looking for could not be found. Try the search.", 3));
  const leaky = page("Bachelor of Arts", "<h2>Entry requirements</h2>" + para("ATAR 70 or equivalent. IELTS 6.5.") + `<p>${"QUJDRA".repeat(60)}</p>`);
  const sha = (s) => sha256(Buffer.from(s, "utf8"));
  const manifest = (html, extra = {}) => ({ evidence_id: "00000000-0000-0000-0000-000000000000", bucket: "evidence", storage_path: `layer2/AU/coverage/p/c/${sha(html)}.html.gz`, container: "gzip",
    content_mime: "text/html", content_sha256: sha(html), stored_bytes: 100, content_bytes: Buffer.byteLength(html), source_url: "https://example.edu/x", page_status: 200, captured_at: new Date().toISOString(), ...extra });
  const base = { url: "https://example.edu/x", prompt_key: "p", model: "m", schema_key: "s" };
  const cases = [
    ["course page admitted to the AER read", { ...base, lane: "aer", html: course, manifest: manifest(course), computed_sha: sha(course) }, "admit", []],
    ["award page admitted to the scholarship read", { ...base, lane: "scholarship", html: award, url: "https://example.edu/scholarships/global" }, "admit", []],
    ["fee table admitted to the fee read", { ...base, lane: "tuition_fees", html: course }, "admit", []],
    ["news page: scholarship score too low", { ...base, lane: "scholarship", html: news }, "reject", ["scholarship_low_signal"]],
    ["listing page routed away from a single-award read", { ...base, lane: "scholarship", html: listing, url: "https://example.edu/scholarships" }, "reject", ["scholarship_listing"]],
    ["near-empty copy is thin", { ...base, lane: "scholarship", html: thin }, "reject", ["thin_page"]],
    ["challenge page is a soft block", { ...base, lane: "scholarship", html: captcha }, "reject", ["soft_block"]],
    ["200 page that says not found", { ...base, lane: "aer", html: notFound }, "reject", ["soft_not_found"]],
    ["news page has no AER signal", { ...base, lane: "aer", html: news }, "reject", ["aer_no_signal"]],
    ["base64 run in the sent text is a prompt leak", { ...base, lane: "aer", html: leaky }, "reject", ["prompt_leak"]],
    ["hash mismatch fails the storage contract", { ...base, lane: "aer", html: course, manifest: manifest(course), computed_sha: "0".repeat(64) }, "reject", ["manifest_invalid"]],
    ["404 page status fails before any read", { ...base, lane: "aer", html: course, manifest: manifest(course, { page_status: 404 }), computed_sha: sha(course) }, "reject", ["page_not_ok"]],
  ];
  let failed = 0;
  for (const [name, input, want, reasons] of cases) {
    const d = await G.admit(input, {});
    const codes = d.reasons.map((r) => r.code);
    const ok = d.would === want && reasons.every((r) => codes.includes(r)) && d.decision === "admit" && (want === "admit" ? d.shadow === false : d.shadow === true);
    if (!ok) failed++;
    console.log(`${ok ? "PASS" : "FAIL"}  ${name}: would ${d.would} [${codes.join(",")}] decision ${d.decision}${d.shadow ? " (shadow)" : ""}`);
  }
  // enforcement is per reason and explicit
  const enforced = await G.admit({ ...base, lane: "scholarship", html: thin }, { enforce: { thin_page: true } });
  const eok = enforced.decision === "reject" && enforced.shadow === false && enforced.tokens_saved_estimate >= 0;
  if (!eok) failed++; console.log(`${eok ? "PASS" : "FAIL"}  enforce thin_page: decision ${enforced.decision}`);
  // Decision 278 D2: the scholarship score is measured only; even a switch set to 1 never stops a read, and the score is recorded
  const lowSig = await G.admit({ ...base, lane: "scholarship", html: news }, { enforce: { scholarship_low_signal: true } });
  const d2 = lowSig.decision === "admit" && lowSig.would === "reject" && lowSig.shadow === true && typeof lowSig.signals.scholarship?.score === "number";
  if (!d2) failed++; console.log(`${d2 ? "PASS" : "FAIL"}  D2 scholarship score measured only: decision ${lowSig.decision}, score ${lowSig.signals.scholarship?.score}`);
  // duplicate input parks (reuse), it does not reject
  const first = await G.admit({ ...base, lane: "aer", html: course });
  const dup = await G.admit({ ...base, lane: "aer", html: course, seen_fingerprints: new Set([first.fingerprint]) }, { enforce: { duplicate_input: true }, park_routed: true });
  const dok = dup.decision === "park" && dup.reasons.some((r) => r.code === "duplicate_input");
  if (!dok) failed++; console.log(`${dok ? "PASS" : "FAIL"}  duplicate input parks for reuse: decision ${dup.decision}`);
  // with no route for parked items an enforced park is never a drop: it stays shadow and the read goes ahead
  const unrouted = await G.admit({ ...base, lane: "aer", html: course, seen_fingerprints: new Set([first.fingerprint]) }, { enforce: { duplicate_input: true } });
  const uok = unrouted.decision === "admit" && unrouted.would === "park" && unrouted.shadow === true;
  if (!uok) failed++; console.log(`${uok ? "PASS" : "FAIL"}  enforced park without a park route stays shadow: decision ${unrouted.decision}, would ${unrouted.would}`);
  // scholarship bundle: a changed (or added, or removed) linked eligibility page is a different input, so it never hits duplicate_input
  const awardUrl = "https://example.edu/scholarships/global", L1 = sha("Eligibility: international students with an offer."), L2 = sha("Eligibility: domestic students only.");
  const s0 = await G.admit({ ...base, lane: "scholarship", html: award, url: awardUrl, linked_sha256: L1 });
  const seenS = new Set([s0.fingerprint]);
  const same = await G.admit({ ...base, lane: "scholarship", html: award, url: awardUrl, linked_sha256: L1, seen_fingerprints: seenS });
  const changed = await G.admit({ ...base, lane: "scholarship", html: award, url: awardUrl, linked_sha256: L2, seen_fingerprints: seenS });
  const absent = await G.admit({ ...base, lane: "scholarship", html: award, url: awardUrl, linked_sha256: null, seen_fingerprints: seenS });
  const has = (d) => d.reasons.some((r) => r.code === "duplicate_input");
  const fok = has(same) && !has(changed) && !has(absent) && new Set([s0.input_sha256, changed.input_sha256, absent.input_sha256]).size === 3 && changed.signals.input.linked_sha256 === L2 && absent.signals.input.linked_sha256 === "none";
  if (!fok) failed++; console.log(`${fok ? "PASS" : "FAIL"}  linked page in the fingerprint: same bundle hits, changed or absent linked page does not`);
  // multi-byte page with a byte-order mark: hashed over its bytes, an intact copy never shows hash_mismatch (decode-then-encode would)
  const mbHtml = page("Bourse d'excellence — 奨学金 | Université", para("Une réduction de 25 % des frais de scolarité pour les étudiants internationaux — 留学生向け奨学金。", 6));
  const mbBytes = new Uint8Array(Buffer.concat([Buffer.from([0xef, 0xbb, 0xbf]), Buffer.from(mbHtml, "utf8")]));
  const mbSha = sha256(mbBytes), opened = await G.openCopy(new Uint8Array(gzipSync(mbBytes)), "gzip");
  const mbMan = manifest(mbHtml, { storage_path: `layer2/AU/scholarships/p/ai/1/${mbSha}.html.gz`, content_sha256: mbSha });
  const viaBytes = await G.verifyManifest(mbMan, opened.bytes), viaText = G.checkManifest(mbMan, sha(opened.text));
  const mbGate = await G.admit({ ...base, lane: "scholarship", html: opened.text, manifest: mbMan, raw_bytes: opened.bytes });
  const mok = opened.sha256 === mbSha && viaBytes.ok && !viaText.ok && viaText.problems.includes("hash_mismatch") && !mbGate.reasons.some((r) => r.code === "manifest_invalid") && mbGate.signals.input.page_sha256 === mbSha;
  if (!mok) failed++; console.log(`${mok ? "PASS" : "FAIL"}  multi-byte copy with a byte-order mark hashed over its bytes: no false hash_mismatch (decoded text would give one)`);
  // a stored copy opened without its capture time is checked on what its bytes prove (OPENED_COPY_REQUIRED), not failed for the missing time
  const noTime = { ...mbMan }; delete noTime.captured_at;
  const oc = await G.verifyManifest(noTime, opened.bytes, { require: G.OPENED_COPY_REQUIRED }), full = await G.verifyManifest(noTime, opened.bytes);
  const ook = oc.ok && !full.ok && full.problems.includes("missing_field");
  if (!ook) failed++; console.log(`${ook ? "PASS" : "FAIL"}  opened copy without a capture time: OPENED_COPY_REQUIRED passes, the full contract names the missing field`);
  // over budget splits/parks, never cuts: the sent text is the full selection
  const big = await G.admit({ ...base, lane: "course_overview", html: course }, { budget_chars: 50 });
  const bok = big.would === "park" && big.sent_chars > 50;
  if (!bok) failed++; console.log(`${bok ? "PASS" : "FAIL"}  over budget parks with reason (sent ${big.sent_chars} > 50, not cut)`);
  // every selected line is a labelled block line: proximity and offsets survive
  const { seg } = G.segment(course, null, ["aer"]);
  const lok = seg.text.aer.split("\n").every((l) => /^\[B\d+ @(\d+|data)\] /.test(l)) && seg.by_lane.aer.block_ids.length > 0;
  if (!lok) failed++; console.log(`${lok ? "PASS" : "FAIL"}  AER segment keeps [B#] block labels (${seg.by_lane.aer.block_ids.length} blocks)`);
  console.log(failed ? `\n${failed} FAILED` : `\nall ${cases.length + 9} checks passed`);
  process.exit(failed ? 1 : 0);
}

if (flag("self-test")) await selfTest();
else if (opt("manifest")) await runManifest();
else { console.error("usage: --self-test | --manifest <file> (--dir <dir> | --supabase) [--out report.json] [--worker <coverage-sweep dir>]"); process.exit(2) }
