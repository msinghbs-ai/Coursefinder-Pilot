// CF-247 pre-AI admission and enrichment gate, pre-ai-admission-v1 (Decision 278, Platform Admin 14 Nov 2026 16:10; shadow, worker v0.95.0).
// Design: admin docs/audits/studysearch-pre-ai-admission-gate-design.md (14 Nov 2026), built on SHARED-SOURCE-TO-PUBLISHED-ENRICHMENT-DESIGN.md §11
// (F2 section slicer, F3 high-recall negative filter, F4 content cache, F5 split/park, never truncate, F6 observability).
//
// It sits between a stored evidence copy and one paid AI read and answers one question: should this read be sent? It changes nothing by itself:
//   * it reuses the platform's one block contract (lean-input.ts leanText lean-md-v1 → aer-v2.ts aerV3Blocks lean-blocks-v1 → lean-sections.ts
//     selectSections) and its existing page checks (firecrawl.ts readOutcome soft-block words, scholarship.ts isListingPage, fees.ts hasFeeAmount);
//   * every decision is SHADOW unless the caller passes enforce=true for that reason code, and the caller only does that when the Platform Admin has
//     switched the reason's setting on after its false-negative rate was measured (CLAUDE.md: a passing qualification never switches anything on);
//   * every threshold comes from the caller's settings (G2); the defaults below are only used when a setting is absent and are the same numbers the
//     worker already uses for the same purpose (300 characters of main text = readDirect "read"; 200 = the least text that can carry a sentence).
// Pure functions only (no network, no storage, no database), so a contract spec and the CLI harness can run them.
// Page content is data: nothing here follows an instruction found on a page.
import { leanText, preflight, sha256Hex, type LeanText } from "./lean-input.ts";
import { aerV3Blocks, type AerBlocks } from "./aer-v2.ts";
import { selectSections, SECTION_DEFAULTS, type SectionOptions } from "./lean-sections.ts";
import { mainText, isListingPage } from "./scholarship.ts";
import { hasFeeAmount } from "./fees.ts";

export const ADMISSION_GATE = "pre-ai-admission-v1";  // never edited in place once released: a different rule set is a new version

// ---------- 1. Storage contract: one manifest per stored copy ----------
// The manifest is not a new file in storage: it is the pipeline.evidence_artifacts row plus what the reader measured when it opened the copy.
// One raw copy per page stays the source of truth (content-addressed, gzip). A derived lean-md-v1 sidecar is optional and versioned (§11 F1/F2).
export type ArtifactManifest = {
  evidence_id: string | null;          // pipeline.evidence_artifacts.id (null only for a read not yet registered)
  bucket: "evidence";
  storage_path: string;                // e.g. layer2/AU/coverage/<provider>/<course>/<sha>.html.gz
  container: "gzip" | "none";          // how the object is stored (objects are application/gzip; evidence_artifacts.mime_type names the content)
  content_mime: "text/html" | "text/markdown" | "text/plain" | "application/pdf" | "application/json";
  content_sha256: string;              // SHA-256 of the decompressed content bytes, as the worker computes it (evidence_artifacts.content_hash)
  stored_bytes: number;                // storage.objects metadata size (compressed)
  content_bytes?: number | null;       // decompressed size, when the reader opened the copy
  source_url: string;
  final_url?: string | null;
  fetched_via?: "direct" | "firecrawl" | "upload" | null;
  http_status?: number | null;         // transport status of the fetch (direct) or of the Firecrawl API call
  page_status?: number | null;         // the page's own status (Firecrawl data.metadata.statusCode; equals http_status for a direct read)
  captured_at: string;                 // ISO time
  sidecar?: { converter: string; storage_path: string; content_sha256: string; of_sha256: string } | null;
};
export type ManifestProblem =
  | "missing_field" | "zero_bytes" | "hash_format" | "hash_mismatch" | "path_hash_disagrees" | "page_not_ok" | "page_status_unknown"
  | "sidecar_of_other_copy" | "content_mime_unknown";
const HEX64 = /^[0-9a-f]{64}$/;
const MIMES = new Set(["text/html", "text/markdown", "text/plain", "application/pdf", "application/json"]);
// The full contract (a registered copy: pipeline.evidence_artifacts row). A reader that opened a stored copy whose capture time it does not hold
// (the scholarship queue hands out a path only) checks what the bytes it opened can prove: OPENED_COPY_REQUIRED.
export const MANIFEST_REQUIRED = ["bucket", "storage_path", "container", "content_mime", "content_sha256", "stored_bytes", "source_url", "captured_at"] as const;
export const OPENED_COPY_REQUIRED = ["bucket", "storage_path", "container", "content_mime", "content_sha256", "stored_bytes", "source_url"] as const;
export type ManifestField = (typeof MANIFEST_REQUIRED)[number];

// SHA-256 of BYTES. The content hash of a stored copy is always taken over the decompressed bytes exactly as stored, before any text decoding:
// decoding and re-encoding is not an identity (a UTF-8 byte-order mark is dropped by TextDecoder, an invalid sequence becomes U+FFFD), so a hash
// of decoded-then-encoded text can disagree with the stored hash for a copy that is intact (a false hash_mismatch on multi-byte pages).
export async function contentSha256(bytes: Uint8Array): Promise<string> {
  const d = await crypto.subtle.digest("SHA-256", bytes as BufferSource);
  return [...new Uint8Array(d)].map((b) => b.toString(16).padStart(2, "0")).join("");
}
// Open a stored object: decompress to bytes, hash the bytes, then decode. The text is decoded exactly as the worker's storedHtml decodes it
// (Response.text(): UTF-8, byte-order mark dropped, invalid sequences replaced), so the page a reader sends is unchanged by going through here.
export async function openCopy(stored: Uint8Array, container: "gzip" | "none"): Promise<{ bytes: Uint8Array; sha256: string; text: string; stored_bytes: number; content_bytes: number }> {
  const bytes = container === "gzip"
    ? new Uint8Array(await new Response(new Blob([stored as BlobPart]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer())
    : stored;
  return { bytes, sha256: await contentSha256(bytes), text: new TextDecoder("utf-8").decode(bytes), stored_bytes: stored.length, content_bytes: bytes.length };
}
// The manifest check over the bytes the reader opened (the entry point a reader uses): the hash is computed here, from the bytes.
export async function verifyManifest(m: Partial<ArtifactManifest>, contentBytes: Uint8Array, opt: { require?: readonly ManifestField[] } = {}) {
  return checkManifest({ ...m, content_bytes: contentBytes.length }, await contentSha256(contentBytes), opt);
}

// Strict structural check of a manifest. computedSha is the reader's own SHA-256 of the decompressed BYTES (contentSha256 / openCopy /
// verifyManifest; never a hash of decoded text). "page_status_unknown" is a warning, not a failure: most Firecrawl read paths do not record the
// page's own status today (audit finding S3).
export function checkManifest(m: Partial<ArtifactManifest>, computedSha?: string | null, opt: { require?: readonly ManifestField[] } = {}): { ok: boolean; problems: ManifestProblem[]; warnings: ManifestProblem[] } {
  const problems: ManifestProblem[] = [], warnings: ManifestProblem[] = [];
  for (const k of opt.require ?? MANIFEST_REQUIRED)
    if (m[k] === undefined || m[k] === null || m[k] === "") { problems.push("missing_field"); break }
  if (computedSha && !HEX64.test(computedSha)) problems.push("hash_format");
  if (m.content_mime && !MIMES.has(m.content_mime)) problems.push("content_mime_unknown");
  if (typeof m.stored_bytes === "number" && m.stored_bytes <= 0) problems.push("zero_bytes");
  if (m.content_bytes !== undefined && m.content_bytes !== null && m.content_bytes <= 0) problems.push("zero_bytes");
  if (m.content_sha256 && !HEX64.test(m.content_sha256)) problems.push("hash_format");
  if (computedSha && m.content_sha256 && computedSha !== m.content_sha256) problems.push("hash_mismatch");
  const inPath = String(m.storage_path || "").match(/([0-9a-f]{64})\.[a-z.]+$/)?.[1];
  if (inPath && m.content_sha256 && inPath !== m.content_sha256) problems.push("path_hash_disagrees");
  const ps = m.page_status ?? null;
  if (ps === null) warnings.push("page_status_unknown"); else if (ps < 200 || ps > 299) problems.push("page_not_ok");
  if (m.sidecar && m.content_sha256 && m.sidecar.of_sha256 !== m.content_sha256) problems.push("sidecar_of_other_copy");
  return { ok: problems.length === 0, problems: [...new Set(problems)], warnings };
}

// ---------- 2. Stage A: sanitise and section (deterministic, local) ----------
export type Lane = "aer" | "scholarship" | "tuition_fees" | "course_overview" | "course_fields";
// the lean-sections field each lane is selected by (lane "course_fields" asks several fields; each is selected and the union is kept)
const LANE_FIELDS: Record<Lane, string[]> = {
  aer: ["entry_requirements", "english"],
  scholarship: [],                                   // a scholarship page is read whole (one award page); its gate is page-level
  tuition_fees: ["fees"],
  course_overview: ["description"],
  course_fields: ["duration", "campus", "delivery", "intakes", "international"],
};
// residue that must never reach a prompt: markup, script/style bodies, long base64 runs, data URIs, JSON blobs
const LEAK = {
  markup: /<\/?(?:div|span|script|style|table|tr|td|a|img|iframe|meta|link|svg|path|button|input|form|noscript)\b[^>]*>/gi,
  base64: /[A-Za-z0-9+/]{240,}={0,2}/g,
  data_uri: /data:[a-z]+\/[a-z0-9.+-]+;base64,/gi,
  json_blob: /\{\s*"[^"]{1,40}"\s*:\s*(?:"[^"]*"|\d+|true|false|null|\{|\[)(?:[^{}]|\{[^{}]*\}){200,}\}/g,
};
export type LeakReport = { markup: number; base64: number; data_uri: number; json_blob: number; clean: boolean };
export function leakCheck(text: string): LeakReport {
  const n = (re: RegExp) => (String(text || "").match(re) || []).length;
  const r = { markup: n(LEAK.markup), base64: n(LEAK.base64), data_uri: n(LEAK.data_uri), json_blob: n(LEAK.json_blob) };
  return { ...r, clean: r.markup + r.base64 + r.data_uri + r.json_blob === 0 };
}

export type Segments = { input: string; lean_chars: number; blocks: number; by_lane: Record<string, { block_ids: string[]; chars: number; no_selection: boolean }>; text: Record<string, string> };
// One page as typed segments. The labelled [B<n> @<offset>] lines are kept unchanged, so every quote still resolves to its block and its offset in the
// stored copy (AER v3 exact_block / lead_in_block proximity, §11 F2 "preserve exact spans and offsets").
export function segment(html: string, data: string | null, lanes: Lane[], opt: SectionOptions = SECTION_DEFAULTS): { lean: LeanText; blocks: AerBlocks; seg: Segments } {
  const lean = leanText(html), blocks = aerV3Blocks(lean, data);
  const by_lane: Segments["by_lane"] = {}, text: Record<string, string> = {};
  for (const lane of lanes) {
    const fields = LANE_FIELDS[lane];
    if (!fields.length) { by_lane[lane] = { block_ids: blocks.blocks.map((b) => `B${b.n}`), chars: blocks.text.length, no_selection: false }; text[lane] = blocks.text; continue }
    const ids = new Set<string>();
    for (const f of fields) for (const id of selectSections(blocks, f, opt).block_ids) ids.add(id);
    const keep = blocks.blocks.filter((b) => ids.has(`B${b.n}`)), lines = blocks.text.split("\n");
    const t = blocks.blocks.map((b, i) => (ids.has(`B${b.n}`) ? lines[i] : null)).filter((x): x is string => x !== null).join("\n");
    // no selection is reported, never acted on: the page is then read whole (lean-sections-v1 rule)
    by_lane[lane] = { block_ids: keep.map((b) => `B${b.n}`), chars: t.length, no_selection: keep.filter((b) => b.kind !== "data").length === 0 };
    text[lane] = by_lane[lane].no_selection ? blocks.text : t;
  }
  return { lean, blocks, seg: { input: blocks.input, lean_chars: lean.text.length, blocks: blocks.blocks.length, by_lane, text } };
}

// ---------- 3. Stage B: admission gates ----------
export type Reason =
  | "manifest_invalid" | "page_not_ok" | "soft_block" | "soft_not_found" | "thin_page" | "prompt_leak" | "over_budget_split"
  | "aer_no_signal" | "scholarship_listing" | "scholarship_low_signal" | "fees_no_amount" | "duplicate_input";
export type GateSettings = {
  min_main_chars?: number;            // admission.min_main_chars (default 300: readDirect's "read" floor)
  sch_min_score?: number;             // admission.scholarship_min_score (default 2 of 6)
  budget_chars?: number;              // the read's own input limit (enrich.page_chars, reading.aer_v2_page_chars, ...): over it → split or park, never cut
  enforce?: Partial<Record<Reason, boolean>>;  // admission.enforce.<reason>: off by default; only a measured reason is ever switched on
  // A park (duplicate_input: reuse the earlier answer; over_budget_split: wait for the split reader) is enforced only where the caller has a route
  // for parked items. Without one an enforced park would be a silent drop of the read, so it stays shadow (recorded, the read goes ahead).
  park_routed?: boolean;
};
export type Decision = {
  gate: string; lane: Lane; decision: "admit" | "reject" | "park"; shadow: boolean;
  would: "admit" | "reject" | "park";              // what the gate would do with every reason enforced
  reasons: { code: Reason; detail: string }[];
  signals: Record<string, unknown>;
  sent_chars: number; tokens_saved_estimate: number; // chars/4, an estimate only: real tokens come from the model's usage block
  input_sha256: string; fingerprint: string | null;
};
export const PARK = new Set<Reason>(["over_budget_split", "duplicate_input"]);  // decisions that hold a read for reuse or a split, never drop it
// Decision 278 D2 (Platform Admin 14 Nov 2026): the scholarship keyword score is measured only. It is recorded with every decision and is never
// enforced, whatever a setting says (it has no admission.enforce switch).
export const MEASURE_ONLY = new Set<Reason>(["scholarship_low_signal"]);
const SOFT_BLOCK = /captcha|cf-chl|access denied|are you a robot|verify you are human|request unsuccessful|incapsula/i;  // firecrawl.ts readOutcome
const SOFT_404 = /\b(page (?:not found|cannot be found|could not be found|doesn'?t exist|does not exist|no longer exists)|404 (?:error|not found)|error 404|we can'?t find (?:the|that|this) page|sorry,? (?:the|this) page)\b/i;
const titleOf = (h: string) => (h.match(/<title[^>]*>([\s\S]*?)<\/title>/i)?.[1] || "").replace(/\s+/g, " ").trim();
const h1Of = (h: string) => (h.match(/<h1\b[^>]*>([\s\S]*?)<\/h1>/i)?.[1] || "").replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();

// deterministic scholarship signals, 0–6. Reported with every decision so the threshold can be tuned from data, never guessed.
export function scholarshipScore(html: string, text: string): { score: number; parts: Record<string, boolean> } {
  const head = `${titleOf(html)} ${h1Of(html)}`;
  const parts = {
    award_in_title: /\b(scholarships?|burs(?:ary|aries)|awards?|grants?|stipends?|prizes?|fee (?:waiver|discount|reduction|remission))\b/i.test(head),
    award_in_body: /\b(scholarships?|burs(?:ary|aries)|stipends?|tuition (?:waiver|discount)|fee (?:waiver|discount|reduction|remission))\b/i.test(text),
    value: /(?:[$£€]\s?\d|\b(?:AUD|NZD|CAD|USD)\s?\d|\b\d{1,3}\s?%|\bfull tuition\b|\btuition fees? (?:covered|paid)\b)/i.test(text),
    eligibility: /\b(eligib\w*|who can apply|criteria|you must|applicants? must|open to)\b/i.test(text),
    application: /\b(how to apply|apply (?:now|by|online)|applications? (?:open|close)|closing date|deadline|automatic(?:ally)? considered)\b/i.test(text),
    audience: /\b(international (?:students?|applicants?)|domestic (?:students?|applicants?)|citizens?|permanent residents?|student visa)\b/i.test(text),
  };
  return { score: Object.values(parts).filter(Boolean).length, parts };
}

export type GateInput = {
  lane: Lane; html: string; data?: string | null; url: string; manifest?: Partial<ArtifactManifest> | null;
  raw_bytes?: Uint8Array | null;                    // the decompressed bytes of the copy (openCopy): when given, the content hash is taken from them
  computed_sha?: string | null;                     // otherwise the caller's own SHA-256 of those bytes
  manifest_require?: readonly ManifestField[];      // MANIFEST_REQUIRED (default) or OPENED_COPY_REQUIRED
  prompt_key: string; model: string; schema_key: string;
  // Every other source the read sends, so the fingerprint is the whole request input. scholarship_ai sends a bundle: the page and, when it links
  // to one, its eligibility or terms page (read directly). linked_sha256 is the SHA-256 of the linked text sent (the answer's bundle.linked_sha256);
  // null or absent = no linked page ("none"). context: the request's other inputs (provider, country, currency, a recovery item's award name ...).
  linked_sha256?: string | null;
  context?: Record<string, unknown> | null;
  seen_fingerprints?: Set<string> | null;           // fingerprints already answered (F4 content cache); the caller supplies them
};
// key-sorted JSON, so the same context always hashes the same
const stableJson = (v: unknown): string => v === null || typeof v !== "object" ? JSON.stringify(v ?? null)
  : Array.isArray(v) ? `[${v.map(stableJson).join(",")}]`
  : `{${Object.keys(v as Record<string, unknown>).sort().map((k) => `${JSON.stringify(k)}:${stableJson((v as Record<string, unknown>)[k])}`).join(",")}}`;
// The read's input hash. It covers every part of what the read sends: the stored copy's content hash (over its bytes), the exact text the gate
// selected, the linked page's hash or "none", and the request context. A change to any one of them is a different input, so duplicate_input can
// only hit when the whole input is the same (it never hits because the main page alone is unchanged).
export async function inputSha256(p: { page_sha256: string; sent_sha256: string; linked_sha256?: string | null; context?: Record<string, unknown> | null }): Promise<string> {
  return sha256Hex([`page:${p.page_sha256}`, `sent:${p.sent_sha256}`, `linked:${p.linked_sha256 || "none"}`, `ctx:${p.context ? stableJson(p.context) : "none"}`].join("␟"));
}
export async function admit(g: GateInput, s: GateSettings = {}): Promise<Decision> {
  const reasons: Decision["reasons"] = [], signals: Record<string, unknown> = {};
  const minMain = s.min_main_chars ?? 300, schMin = s.sch_min_score ?? 2;
  const computed = g.raw_bytes ? await contentSha256(g.raw_bytes) : (g.computed_sha ?? null);
  if (g.manifest) {
    const mc = checkManifest(g.raw_bytes ? { ...g.manifest, content_bytes: g.raw_bytes.length } : g.manifest, computed, { require: g.manifest_require }); signals.manifest = mc;
    if (!mc.ok) reasons.push({ code: mc.problems.includes("page_not_ok") && mc.problems.length === 1 ? "page_not_ok" : "manifest_invalid", detail: mc.problems.join(",") });
  }
  const main = mainText(g.html), head = `${titleOf(g.html)} ${h1Of(g.html)}`;
  signals.main_chars = main.length;
  if (SOFT_BLOCK.test(g.html.slice(0, 20000)) && main.length < 4000) reasons.push({ code: "soft_block", detail: "challenge or access-denied page" });
  if (SOFT_404.test(head) || (main.length < 1500 && SOFT_404.test(main.slice(0, 600)))) reasons.push({ code: "soft_not_found", detail: `page says it is not found: ${head.slice(0, 80)}` });
  if (main.length < minMain) reasons.push({ code: "thin_page", detail: `${main.length} characters of main text, under ${minMain}` });

  const { seg } = segment(g.html, g.data ?? null, [g.lane]);
  const sent = seg.text[g.lane] || "";
  signals.segment = seg.by_lane[g.lane];
  const leak = leakCheck(sent); signals.leak = leak;
  if (!leak.clean) reasons.push({ code: "prompt_leak", detail: `markup ${leak.markup}, base64 ${leak.base64}, data URI ${leak.data_uri}, JSON ${leak.json_blob}` });
  if (s.budget_chars && sent.length > s.budget_chars) reasons.push({ code: "over_budget_split", detail: `${sent.length} characters over the read's ${s.budget_chars}: split or park with this reason, never cut` });

  if (g.lane === "aer") {
    // the selected text decides; the whole page is recorded beside it, so a signal only outside the selection shows as a possible selector miss
    const p = { entry: preflight("entry_requirements", sent), english: preflight("english", sent), entry_full: preflight("entry_requirements", main), english_full: preflight("english", main) };
    signals.preflight = p;
    // high recall only (§11 F3): "unknown" is admitted; only no signal on BOTH fields is a candidate, and only in shadow until measured
    if (p.entry === "no_signal" && p.english === "no_signal") reasons.push({ code: "aer_no_signal", detail: "no entry-requirement or English signal in the selected text" });
  }
  if (g.lane === "scholarship") {
    const sc = scholarshipScore(g.html, main); signals.scholarship = sc;
    if (isListingPage(g.html, g.url, titleOf(g.html) || null)) reasons.push({ code: "scholarship_listing", detail: "a listing of awards: route to listing traversal, not to a single-award read" });
    if (sc.score < schMin) reasons.push({ code: "scholarship_low_signal", detail: `score ${sc.score} of 6, under ${schMin}` });
  }
  if (g.lane === "tuition_fees" && !hasFeeAmount(sent) && !hasFeeAmount(main)) reasons.push({ code: "fees_no_amount", detail: "no currency amount on the page (the fee reader's own rule)" });

  // page hash: the bytes when given (exact), else the caller's hash of the bytes, else the page re-encoded (only a caller that holds no bytes)
  const page_sha256 = computed && HEX64.test(computed) ? computed : await sha256Hex(g.html);
  const sent_sha256 = await sha256Hex(sent);
  const linked_sha256 = g.linked_sha256 ? String(g.linked_sha256) : null;
  const input_sha256 = await inputSha256({ page_sha256, sent_sha256, linked_sha256, context: g.context ?? null });
  signals.input = { page_sha256, sent_sha256, linked_sha256: linked_sha256 || "none", context: g.context ? stableJson(g.context).slice(0, 400) : null };
  const fingerprint = await sha256Hex([ADMISSION_GATE, input_sha256, g.lane, g.prompt_key, g.model, g.schema_key].join("␟"));
  if (g.seen_fingerprints?.has(fingerprint)) reasons.push({ code: "duplicate_input", detail: "the same input (page, linked page and context), prompt, model and schema were already answered: reuse that answer" });

  const would: Decision["would"] = reasons.length === 0 ? "admit" : reasons.every((r) => PARK.has(r.code)) ? "park" : "reject";
  const enforced = reasons.filter((r) => s.enforce?.[r.code] === true && !MEASURE_ONLY.has(r.code) && (!PARK.has(r.code) || s.park_routed === true));
  const decision: Decision["decision"] = enforced.length === 0 ? "admit" : enforced.every((r) => PARK.has(r.code)) ? "park" : "reject";
  return { gate: ADMISSION_GATE, lane: g.lane, decision, shadow: enforced.length === 0 && reasons.length > 0, would, reasons, signals,
    sent_chars: sent.length, tokens_saved_estimate: would === "admit" ? 0 : Math.round(sent.length / 4), input_sha256, fingerprint };
}

// ---------- 4. Stage C: the record a decision leaves (written beside the read, never instead of it) ----------
// public.svc_pre_ai_admission_record_v1(p_rows jsonb) → pipeline.pre_ai_admission_decisions. A rejected read is never silent: it carries its reason
// codes, the estimated tokens it saved and the evidence it was judged on, and its item goes to state 'rejected_admission' only when enforced.
export function decisionRow(d: Decision, ctx: { lane_item: string; item_id: string | number; evidence_id: string | null; storage_path: string | null; worker: string }) {
  return { gate: d.gate, lane: d.lane, lane_item: ctx.lane_item, item_id: String(ctx.item_id), evidence_id: ctx.evidence_id, storage_path: ctx.storage_path,
    decision: d.decision, would: d.would, shadow: d.shadow, reason_codes: d.reasons.map((r) => r.code), reasons: d.reasons,
    sent_chars: d.sent_chars, tokens_saved_estimate: d.tokens_saved_estimate, input_sha256: d.input_sha256, fingerprint: d.fingerprint,
    signals: d.signals, worker: ctx.worker.slice(0, 60) };
}
