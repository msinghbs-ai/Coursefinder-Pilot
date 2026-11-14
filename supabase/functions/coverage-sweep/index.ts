import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { feeAiParsed, feeAiRequest, hasFeeAmount, noNul } from "./fees.ts";
import { answerLimit, errorCost, readAnswer, readError, type ReadType } from "./answer.ts";
import { createClient } from "npm:@supabase/supabase-js@2.57.4";
import { clean, currencyFor, domainFitsName, english, fee, h1Of, htmlToText, identity, intakeEvidence, intakes, keepUrl, pageDataItems, robotsAllows, siteNameMatch, staleCalendarUrl, titleOf } from "./extract.ts";
// v0.17.32: same normalising as extract.ts siteNorm (kept here so the shared extract.ts, used by other functions, is unchanged)
const siteNorm = (s: string) => clean(s).normalize("NFD").replace(/[\u0300-\u036f]/g, "").toLowerCase().replace(/&/g, " and ").replace(/[\u2019']/g, "").replace(/[^a-z0-9]+/g, " ").replace(/\bthe\b/g, " ").replace(/\s+/g, " ").trim();
import { ADD_TESTS_PARSER, ADDED_TESTS, calendarStarts, englishPolicy, POLICY_PARSER } from "./policy.ts";
import { CALENDAR_PARSER_DATES, CALENDAR_READER, calendarAiParsed, calendarAiRequest, calendarSafe, calendarSlices } from "./calendar.ts";
import { PAGE_ID_CONTRACT, pageIdChecks, pageIdInput, pageIdRequest } from "./pageid.ts";
import { cascadeFetch, sentModel, takeAiTrace } from "./cascade.ts";
import { callRecord, pageHtml, readOutcome, scrapeBody, searchBody, searchCandidates, searchResults } from "./firecrawl.ts";
import { applyAdapter, inspectPage, jsonAt, jsonFind, jsonShape, pageJson, patternValues, viewApplies, withView } from "./adapters.ts";
import { CENTRAL_SEARCH, ENTRY_SEARCH, centralCandidates, entryCandidates, weakKinds } from "./central.ts";
import { ENTRY_PROMPT_VERSION, ENTRY_TABLE_BASIS, NAMED_NOTE, PDF_NOTE, entryCellList, entryCompleteness, entryCountryAliases, entryDropNoMinimum, entryGlobalQualification, entrySubjectRows, entryManifestDetail, entryMatrixParsed, entryMatrixRequest, entryNoAnswerWhy, entryNonCountryShape, entrySlices, entryTables, entryUnscaledColumns, entryQualificationCountries } from "./entry.ts";
import { OPS_DIAGNOSE_CONTRACT, opsDiagnoseAnswer, opsDiagnoseLimit, opsDiagnoseRequest, opsDiagnoseUsable } from "./ops-diagnose.ts";
import { linkSearchGroups, linkSearchShareOn } from "./link-share.ts";
import type { EntryBandLine, EntryCountryRef, EntryLineSet, EntryManifest } from "./entry.ts";
import { ENTRY_CELL_READER, entryCellRead } from "./entry-cells.ts";
import { ENTRY_GRID_READER, entryGridHeadingList, entryGridRead } from "./entry-grid.ts";
import { pdfGrids2 } from "./pdf-grid.ts";
import { COURSE_ENTRY_PROMPT_VERSION, courseEntryAnswer, courseEntryMerge, courseEntryPlan, courseEntryRequest, courseEntrySliceRows, courseEntryUser } from "./course-entry.ts";
import type { CourseSliceOutcome } from "./course-entry.ts";
import { AER_V2_MODE, AER_V3_CONTRACT, aerV2Answer, aerV2Refs, aerV2Request, aerV2Sha256, aerV2User, aerV2Verify, aerV3Blocks, aerV3Request, aerV3User, aerV3Verify } from "./aer-v2.ts";
import { PDF_METHOD, pdfPages, pdfTables } from "./pdf.ts";
import type { PdfResult } from "./pdf.ts";
import { getDocumentProxy, getResolvedPDFJS } from "npm:unpdf@0.12.1";
import { adapterOutput, builderRequest, jsonLeaves, mainJsonScript, proposalAdapter, textBlocks } from "./builder.ts";
import { adapterRecords, referenceRecords } from "../_shared/cf247-register-zip.ts";
import { htmlAdapterRecords, nzqaReferenceRecords } from "../_shared/cf247-register-html.ts";
import { prismsReferenceRecords, qiltReferenceRecords, xlsxAdapterRecords } from "../_shared/cf247-register-xlsx.ts";
import { itemsAdapterRecords, itemsText } from "../_shared/cf247-register-items.ts";
import * as caRef from "../_shared/cf247-register-ca-ref.ts";
import { admissionCheck, awardScope, baseHost, keepScholarshipUrl, onSite, mainText, matchScholarshipPage, nameOnPage, normUrl, pageHeadings, providerTokens, scholarshipCriteria, scholarshipFacts, scholarshipListing } from "./scholarship.ts";
import { imageSize, logoCandidates, sniffMime, svgSafe } from "./logo.ts";
import { eligibilityLinks, eligibilityOutcome, eligibilityProof, linkedPageNote } from "./eligibility.ts";
import { RECOVERY_VARIANT, SCH_EXTRACT_CONTRACT, awardSection, checkScholarshipDetail, directReadUsable, mergeRecoveryParts, quoteSource, scholarshipExtractPartRequest, scholarshipExtractRequest, type BundlePart } from "./sch-extract.ts";
import { awardSections, mapOutcome, nextPage, pagingState, redirectOutcome, sectionCode, sectionHtml, statedTotal } from "./catalogue.ts";
import { COURSE_TEXT_FIELDS, cdescRequest, cdescResults, cdescSpans, cdescUser, courseTextAnswer, courseTextAnswerLimit, courseTextLength, courseTextPage, courseTextRequest, courseTextResults, courseTextUser, COURSE_TEXT_PROMPT_VERSION, CDESC_PROMPT_VERSION } from "./course-text.ts";
import { leanText, observation, sha256Hex } from "./lean-input.ts";
import { BLOCK_INPUT, LEAN_SECTIONS, SECTION_DEFAULTS, blockPlain, holds, selectSections } from "./lean-sections.ts";
import { DESCRIPTION_ANSWER_KEY, DESCRIPTION_PROMPT_VERSION, promptRequest, promptSentences, DESCRIPTION_WORKER_PROTOCOL, aboutLinks, aboutPageCheck, descriptionAnswer, descriptionClaimCheck, descriptionCostQuote, descriptionPageText, descriptionIdentitySeen, descriptionRequest, descriptionSourceIdentity, type IdentityTrace, ownHost, providerDescriptionSentences } from "./description.ts";
const SCH_VERSION = "scholarship-sweep-v0.7.3"; // v0.7.3 (11 Oct 2026, Platform Admin bugs 11/10-6): a "while places last" condition is not an ended scholarship; an amount the student pays (deposit, bond, fee) is never the award and a "valued at" amount counts; courses listed after "one of the following courses" are read. v0.7.2 (11 Oct 2026): course titles end at bullets (•, ⦁) and at the next capitalised word or sentence. v0.7.1 (11 Oct 2026): courses named after "excluding" are exclusions; course titles keep their bracketed specialisation; numeric dates read in the provider country's day/month order; date proofs start at their label. v0.7.0 (11 Oct 2026): application open and close dates (with rounds), study start, courses the page names, and the sentence behind each level and field. v0.6.3 (11 Oct 2026): academic-result percentages (CWA, WAM, ATAR) are not award values; the value text is a whole sentence. v0.6.2: Firecrawl cap and reserve read from Layer 2 settings; v0.6.1: // v0.6.1: numeric character references in titles decoded; // v0.6.0 (Decision 250): amounts in the provider country's currency; NZ and Canadian domestic wording
// v0.5.4 (2 Oct 2026, Decision 212 check): a listed value ("Residency Australian Citizen, New Zealand Citizen, International
// Student") includes international students.
// v0.5.3: "Overseas students are eligible to apply" includes international students.
// v0.5.2 (2 Oct 2026, second hand-check, 14 domestic-only readings): "... New Zealand citizen or International student" and
// "both domestic (...) and international students" include international students.
// v0.5.1 (2 Oct 2026, first 30 hand-checked): the eligibility section ends at the next part of the page (how to apply,
// related scholarships); "key details" lines only as label + values; international as a stated requirement, not a menu
// link; "not eligible ... if you: are an Australian citizen" read as an exclusion.
// v0.5.0 (2 Oct 2026, Decision 211): eligibility criteria (student type, study stage, full-time, ATAR/GPA/WAM minimum,
// gender, nationality, applying without an application) and award scope (one-off, first year, per year, per year for the
// course, whole course; what it pays for) are read from the eligibility and benefit wording.
// v0.4.6 (step-2 hand-check): amounts in another currency (Swinburne "$5,000 USD") or stated as a maximum ("up to
// A$7,496", "up to AUD$20,000") are not a single AUD value; the eligibility section is a heading-like "Eligibility"
// (not "eligible countries") and when it states no level the page start is used.
// v0.4.5 (step-2 hand-check): an admitted title must be a scholarship's own name - ending with the scholarship word or a
// qualifier; page furniture, student stories, recaps, application forms and generic plural titles are not admitted.
// v0.4.4 (step-2 hand-check): articles, information pages and faculty listings are not single scholarships; links held
// as escaped HTML count as listing links; a re-read of an admitted page checks the admission rules again (a page that
// no longer meets them is withdrawn by the database, never published).
// v0.4.3 (step-1 hand-check): conditions about other scholarships covering full tuition are not the value; "up to N%"
// is a maximum (not applied); "Value $N" is a stated amount; stipend amounts kept; one amount in the scholarship's name
// that the page states is the value; a discovered page must be about a scholarship (UWA research-project page) and a
// web-search match must be a scholarship address or title.
// v0.4.2 (hand-check of the first admitted pages): full tuition is a single value only when no other percentage is
// stated; levels ignore excluded levels ("excluding Master by Research or PhD") and earlier study ("completed an
// undergraduate degree").
// v0.4.1: listing pages counted from the page content only (menus and side panels removed); supporting pages
// (terms and conditions, FAQs, how to apply, recipients, news) are not scholarships.
// v0.4.0 (scholarship discovery): the reader confirms the page names the scholarship (title, og:title, <h1>, or the whole
// name in one of the first <h2>s) before anything is applied - otherwise read_status "name_mismatch"; Firecrawl for
// scholarship work has its own credit cap (purposes sch_map, sch_search, sch_scrape); v0.6.2: the cap and reserve are Layer 2 settings.

// CF-247 complete coverage sweep (Platform Admin direction 29 Sep 2026). Nonce-only. Nothing is written to the
// catalogue: discovery lists a provider's course-like pages, reading keeps each bound course page as evidence and
// records tuition, English and intake candidates for a separately approved admission rule.
//   mode discover: Firecrawl map per provider website (1 credit per call), inside the monthly budget guard.
//   mode read:     direct fetch (robots.txt respected); Firecrawl scrape only when the site refuses or the page is
//                  script-only, inside the budget guard; identity = CRICOS course code on the page or exact title.
const VERSION = "coverage-sweep-v0.5.6"; // extractor version (unchanged by v0.6.0 worker modes)
// v0.21.5: the page bases Firecrawl may read (found by CRICOS code, listed on the university's own site, or entered by a person)
// v0.38.1 (22 Oct 2026, NZ course list pages): a page the AI page match chose from the university's own site addresses (its course list or
// site map) is listed on the university's own site, so it may be read through the scraper when the direct read is blocked (Otago, Lincoln, AUT).
const FC_TRUSTED_BASIS = ["cricos_search", "cricos_code", "cricos_code_on_page", "nzqa_code", "adapter_code", "title_match", "cms_path_public", "manual", "firecrawl_upgrade", "ai_match", "programme_list"]; // v0.45.0: a page bound by its NZ or CA code is as trusted as one bound by a CRICOS code
const WORKER = "coverage-sweep-worker-v0.92.0"; // v0.92.0 (14 Nov 2026, CF-247 Lean AI Input Phase 1b step 2, shadow selection: each observed course-page read also records what the section selector would send, beside what is sent; no request, prompt, model, value or admission change) // was v0.91.0 // v0.91.0 (14 Nov 2026, numbered after #1128 v0.90.0, CF-247 Lean AI Input Phase 1b step 1 recall matcher fix, Platform Admin 14 Nov 2026 13:25): mode lean_sections_eval matches each labelled value against the blocks' words without their "[B<n> @<offset>]" labels (lean-sections.ts blockPlain, selectSections plain), so a quote that runs across adjacent blocks is found; the selected-chars measure stays the labelled text a reader would be sent. Measurement only; no other mode changes. // was v0.90.0 // v0.90.0 (14 Nov 2026, CF-247 merge of #1128 AI models and services with #1136 Lean AI Input Phase 1b step 1; both were numbered v0.89.0): both releases together, nothing else. #1136 adds the offline section selector and makes no AI call; every model call still goes through cascade.ts on its own service route (#1128). No request, prompt, model choice, skip, value, admission, setting or ceiling changes.
// was v0.89.0 (#1136) // v0.89.0 (14 Nov 2026, numbered after #1137 v0.88.0, CF-247 Lean AI Input Phase 1b step 1, Platform Admin 14 Nov 2026 11:37; admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md): new mode lean_sections_eval, the offline recall check of the section selector (lean-sections.ts lean-sections-v1, selecting a field's sections from the platform's one [B#] block form, aer-v2.ts aerV3Blocks / BLOCK_INPUT lean-blocks-v1, the same blocks the AER v2 reader sees; no block format of its own) on labelled stored pages handed over by public.svc_lean_sections_eval_next_v1, recorded with public.svc_lean_sections_eval_record_v1. Stored copies only: no AI, no Firecrawl, no live fetch, nothing admitted. No other mode changes.
// was v0.89.0 (#1128 merge) // v0.89.0 (14 Nov 2026, CF-247 merge of #1128 AI models and services with #1137 AER v2 prompt v3; both were numbered v0.88.0): mode aer_v2_shadow builds the v3 request over numbered lean-md-v1 blocks (#1137) and sends it through cascade.ts on the entry_requirements_v2_shadow route (#1128); the version's answer contract, routing and params come from the version, the model and its cascade from the route. No request, prompt, model choice, skip, value, admission, setting or ceiling changes.
// was v0.88.0 (#1137) // v0.88.0 (14 Nov 2026, CF-247 AER v2 prompt v3, Platform Admin 14 Nov 2026 item 2): mode aer_v2_shadow reads a prompt version whose answer contract is aer-v2-answer-v3 over the whole stored page as numbered lean-md-v1 blocks (aer-v2.ts aerV3Blocks: "[B<n> @<source_at>]", headings, list items, table rows with their column headers; never cut), with the version's pinned provider routing and require_parameters (aerV3Request), and checks each record with the v3 verifier (aerV3Verify: exact_quote inside its cited block and holding the minimum; lead_in_quote separate, before it, within reading.aer_v3_lead_in_max_blocks and no heading between). Versions with the v1 contract read exactly as before.
// was v0.88.0 (#1128 merge) // v0.88.0 (14 Nov 2026, CF-247 merge of #1128 AI models and services with #1131 Lean AI Input Phase 1): both releases together. Every model call still goes through cascade.ts on its own service route (#1128), and mode enrich_ai still observes every course-page read in shadow (#1131); the observation of a course description names the course_description route model the read is sent to. No request, prompt, model choice, skip, value, admission, setting or ceiling changes.
// was v0.87.0 // v0.87.0 (13 Nov 2026, numbered after #1128 v0.85.0 and v0.86.0, CF-247 Lean AI Input Phase 1, Platform Admin 13 Nov 2026 22:51; admin docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4): mode enrich_ai observes every course-page read in shadow (lean-input.ts lean-md-v1): source text length, characters sent, whether and where the text was cut, a high-recall preflight on the text sent and on the whole page, the sent-input SHA-256 and a content/prompt/model/schema fingerprint, recorded through public.svc_ai_input_observe_v1 (reading.input_observe_on). No request, prompt, model, skip, value or admission changes.
// was v0.86.0 // v0.86.0 (13 Nov 2026, CF-247 Platform Admin review 22:10): every model call attempt is kept (service, model, attempt, outcome, failure kind, tokens, cost) and sent to svc_ai_model_answered_v1 at the end of the call; the six single-model calls go through cascade.ts for that record only (one model, the call as it was); no prompt changed.
// was v0.85.0 // v0.85.0 (13 Nov 2026, CF-247 AI spend control, Platform Admin 19:14 "Service based Model with cascading"): no model is named in the worker (AI_MATCH_MODEL and PAGE_ID_MODELS are gone; course-page matching takes its model from public.svc_coverage_ai_match_next); the description, the entry requirements and the other course fields each use their own route (w.routes); calls with a cascade (cascade.ts: course fields, fees, central pages, scholarship re-check, course-page matching, entry requirements v2) try the handed-out models in order and move on only on a technical failure, never on what a model answered, and only while the call's time budget lasts; the model that answered is recorded. Prompts and prompt versions are unchanged.
// was v0.84.0 // v0.84.0 (13 Nov 2026, CF-247 operating model 3.3.2, Platform Admin 12 Nov 2026 21:07 and 13 Nov 15:31): a provider that is not on the Firecrawl target list is not refused when an open on-demand request covers the spend (svc_fc_on_demand_covers_v1, asked once per provider and purpose a call); the database rule (svc_fc_spend) then decides and records the use against the request. // was v0.83.0 (13 Nov 2026, CF-247 F-SCH long-page recovery, Platform Admin S2-Scholarship directive 13 Nov 2026 §2): a scholarship_ai item marked recovery sectioned-v1 (queued by security.scholarship_detail_recovery_queue_v1 for active scholarships whose whole-page version 3 reading was cut or unanswered) reads the award's own section of the stored page (sch-extract.ts awardSection, reading.sch_recovery_section_chars) and at most reading.sch_recovery_linked_chars of its linked terms page, in two smaller strict-schema calls (part A identity, eligibility, availability and the version 2 keys; part B benefits, payment, application, duration, summary) merged into the one version 3 answer and checked exactly as before; the section offsets and hashes are kept in the answer bundle and both calls' cost on the extraction. Other items read as before. // was v0.82.0 // v0.82.0 (12 Nov 2026, CF-247 Website API v3 build brief WP-2.1, O14; Platform Admin 12 Nov 2026 22:37): the English policy parser (policy.ts provider-policy-v0.3.1) reads OET (numeric score only, 200 to 500 in steps of 10; a letter grade is never turned into a number) and CELPIP (level 4 to 12); the add-tests job reads each approved policy's stored page once more for them (no Firecrawl, no AI). Nothing else changed. // v0.81.0 (12 Nov 2026, CF-247 F-INT, Platform Admin 12 Nov 2026 20:57 "fix calendar readers"): calendar reader calendar-v2.4 (calendar.ts sectionMonth). A month-grid calendar (the Griffith 2027 Academic Calendar PDF) prints the month once as a heading and each row as "1 Commencement of Trimester 1"; such a start takes its month from the month-only heading above its row only when the reader reported that month, the row begins with the day, the quote is on the page once and no other month heading lies between. The reader version change re-reads stored calendars through the existing calendar-reread (no Firecrawl); every reading still goes through the calendar qualifier and approval. No setting, migration or database rule changes. // was v0.80.1 // v0.80.1 (12 Nov 2026, CF-247 AER source recovery): the refused-PDF Firecrawl fetch spends from the reads share (purpose fc_read, one page read) instead of the central discovery share, which the discovery campaign uses up each day (Macquarie refused as credits_refused / share on 12 Nov). // was v0.80.0 // v0.80.0 (12 Nov 2026, CF-247 AER source recovery, Platform Admin 20:23): a PDF the provider's server refuses is fetched once through Firecrawl (reading.entry_pdf_firecrawl_on) and its text stored as evidence and read as text (Macquarie). // was v0.79.0 // v0.79.0 (13 Nov 2026, CF-247 Decision 276 AER v2 step 1, Platform Admin 12 Nov 2026 17:20; admin docs/platform/AER-DESIGN-V2-PROPOSAL.md v0.3 §3.3, §3.4, §3.9, §9): new mode aer_v2_shadow reads stored official course pages (the evidence copy bound in pipeline.coverage_course_pages; no Firecrawl, no live fetch) with the versioned trial prompt the database hands over (pipeline.aer_prompt_versions, aer-v2-course-v1, its sha-256 checked before any call, one pinned model per version) and checks every record with the deterministic verifier (aer-v2.ts: each quote on the stored page in the canonical flat form, the minimum printed in its own quote and a number only when printed in it, the applicant country an ISO code of ref.countries, a qualification code in ref.aer_qualifications); results go to public.svc_aer_v2_shadow_record only (shadow: nothing admitted, no catalogue table, no Layer 4 item). The stored-copy loader of enrich_ai is shared (readEvidenceCopy), unchanged. Nothing else changes. // was v0.78.0 // v0.78.0 (12 Nov 2026, CF-247 F-SCH.01 post-activation review): mode scholarship_eligibility accepts an international proof only when, after course titles with "(International)" are taken out, the sentence also carries an eligibility cue, is not programme-wide wording, not a search control, and (when it is about paying or entering) names eligibility (eligibility.ts eligibilityProof); the first live run acted on a course title, a site banner, fee instructions and a menu tag. Mode scholarship_ai gives a version 3 call 90 s (SCH_V3_TIMEOUT_MS; 16 of 52 v0.77.1 reads were cut by the 60 s abort mid-answer) and starts such a call only in the first 20 s of the worker call. Nothing else changes. // was v0.77.1 // v0.77.1 (12 Nov 2026, F-SCH redesign R1 first cohort): the version 3 extraction asks OpenRouter for the pinned model's fastest provider (provider sort throughput; the model is unchanged): 125 of the first 231 version 3 reads on the default provider stopped at about 60 s with no answer. Nothing else changes. // was v0.77.0 // v0.77.0 (12 Nov 2026, CF-247 F-SCH production redesign, Platform Admin directive 12 Nov 2026 16:12): (1) scholarship pages are read directly first (robots.txt respected, no credit) and through Firecrawl only when the direct copy is refused, blocked or not usable evidence (sch-extract.ts directReadUsable); a rendered listing catalogue keeps the scraper first; (2) mode scholarship_ai reads prompt version 3 items with the one versioned extraction contract sch-extract-v3 over one evidence bundle (the page and its linked eligibility or terms page on the same site, read directly): the version 2 keys are unchanged at the top level and the new `detail` fields are each checked against the bundle (checkScholarshipDetail) before the database may fill an empty canonical field. Version 2 items read as before. // was v0.76.0 // v0.76.0 (12 Nov 2026, CF-247 F-SCH.01 shadow review): mode scholarship_eligibility accepts an international proof only when "international" describes who may apply (eligibility.ts eligibilityProof: international students or applicants, the (international) tag, domestic and international, overseas students, student visa, non-residents); 2 of 5 proofs in the first 200 shadow reads were course names ("Master of International Business"). Nothing else changes. // was v0.75.0 // v0.75.0 (12 Nov 2026, CF-247 F-SCH.01 scholarship eligibility reader): new mode scholarship_eligibility reads a scholarship page refused only for "international not stated" again with the re-check question (stored copy first) and, when the page is silent, at most sch_elig.links_max pages it links to for its eligibility or conditions on the same site (eligibility.ts); each sentence must be on the page it came from and name international or domestic students; answers go to public.svc_scholarship_eligibility_record and the database acts on them (shadow until sch_elig.apply_on). Nothing else changes. // was v0.74.1 // v0.74.1 (12 Nov 2026, CF-247 F-AER.08 production verification): a call reads at most reading.entry_pdf_per_call stored PDFs (UNSW's grid read was stopped by the call's CPU limit after Sydney and UQ in the same call); a further PDF returns to the queue without spending a try. // was v0.74.0 // v0.74.0 (12 Nov 2026, CF-247 F-AER.10 reusable reader fixes, Platform Admin mandate 12 Nov 2026 09:23): a heading + cell quote is proven by its parts, in order and close together (reading.entry_quote_parts_on, reading.entry_quote_window_chars); a band given with its rank label keeps the printed number (reading.entry_band_label_words); a row with no country whose qualification is a country's own framework is that country's row (reading.entry_qualification_countries, AQF=AU) (entry.ts). // was v0.73.0 // v0.73.0 (12 Nov 2026, CF-247 F-AER.08, Platform Admin 11 Nov 2026 decisions 1 and 2): with reading.entry_grid_reader_on, a stored PDF whose tables have no drawn rules but print an aligned course-by-qualification grid (UNSW, Sydney, UQ) is proven by alignment (pdf-grid.ts, fail closed: each value in exactly one column) and read cell by cell without the model (entry-grid.ts): each column heading is a country, an education board, an international qualification, a course fact or unknown (governed list reading.entry_grid_headings); each cell gives one row for its course with the minimum as printed and the CRICOS code of the course's row; the rows go through entryMatrixParsed unchanged and the database links each course (catalogue.entry_course_links). // was v0.72.1 // v0.72.1 (12 Nov 2026, CF-247 F-CDESC first-cycle check of #1047): a page claim backs every sentence sharing enough of its meaningful words (settings enrich.course_description_claim_reach_*), an unreached sentence takes its closest page claim, quotes are page text only (course-text.ts cdescValue). // was v0.72.0 // v0.72.0 (12 Nov 2026, CF-247 F-CDESC, Platform Admin 11 Nov 2026, Admin PR #430 COURSE-DESCRIPTION-PRODUCTION-DESIGN.md): the course description is written by its own call with the pinned prompt cdesc-source-grounded-v1 over the stored page's numbered source spans, each claim citing its spans (course-text.ts cdesc*); the deadline keeps course-text-v2 in its own call; the D4 length re-ask is retired. // was v0.71.0 // v0.71.0 (11 Nov 2026, CF-247 F-AER.07 PDF cell reader, Platform Admin 11 Nov 2026 16:20 and the qualification-first decision item 5): with reading.entry_cell_reader_on, a stored PDF entry table that pdfTables gives one line per cell (row label by study-level columns) is read cell by cell without the model (entry-cells.ts): the row label is a country, an education board naming one country (Indian School Certificate -> IN) or an international qualification (IB, GAC); each cell gives one row per board that prints its own minimum, with the minimum, its scale and the qualification as printed, and the cell words up to that minimum as the quote. The rows go through entryMatrixParsed unchanged (quote, grade, value, scale, qualification-first) and are recorded as before; a page of any other shape goes to the model as before. // was v0.70.0 // v0.70.0 (12 Nov 2026, CF-247 F-AER.03 qualification-first, Platform Admin decision 11 Nov 2026 item 2): the entry matrix reader keeps a row that names no ISO country of education when its qualification is a recognised international one (public.svc_aer_qualifications_v1: IB, European Baccalaureate, A Levels, Cambridge International, Pearson Edexcel, GAC, AP, NCUK and the others), with its qualification code and applicability (global only when the country heading is an every-country word, reading.entry_global_scope_tokens, or the quote prints "all countries", "any country", "worldwide" or "regardless of country"; otherwise unresolved). Such a row passes every check a country row passes (quote on the page, grade and value in the quote, scale, band) and is sent as qualification_rows; the database records it beside the matrix for the person's decision (svc_entry_matrix_record). Other rows with no country are dropped as before (unknown_country, or unknown_qualification for an every-country heading with an unrecognised qualification). Nothing else changed. // was v0.69.1 // v0.69.1 (11 Nov 2026, CF-247 F-PDESC): a prompt passage is checked against the page in one canonical form (description.ts passageCanonical: tag spacing before punctuation, quote and dash shapes, NFKC); letters, digits and numbers stay exact. // was v0.69.0 // v0.69.0 (11 Nov 2026, CF-247 F-PDESC, migration 20261112011000, release 20261112010000; first deployed with it): provider descriptions use the prompt the lease hands over (w.prompt, kept in pipeline.provider_description_prompts and edited on Models & services › AI & OpenRouter), stamp its version on each read, accept several page passages per sentence, and spend an on-demand read's Firecrawl as purpose provider_description_on_demand (Fill description). Without w.prompt the built-in prompt v2 is used as before.
// was v0.68.0 // v0.68.0 (11 Nov 2026, CF-247 F-INT, RMIT Rule B switch-on): an adapter's intakes reading keeps the page's own words around the months (adapters.ts patternValues words, patternWordsTail: the end of the whole match, up to 180 characters), e.g. "adapter pattern: ... Next intake: February, July", where it kept only "adapter pattern: February". The intake planner's offering check needs the intake statement and held 445 RMIT rows for the missing wording. The months read are unchanged; the extractor version is unchanged; the existing adapter_apply re-reads the stored pages (no Firecrawl). No setting, no AI. // was v0.67.0 // v0.67.0 (11 Nov 2026, CF-247 F-INT, measured after 20261111110000): the calendar re-read took 60 documents, not the 100 set in batch.calendar_reread, because the worker capped the call at a fixed 60 (G2: the run size is the setting). The cap is now 100, the setting's maximum, as a guard against a malformed call only. No other change. // was v0.66.0 // v0.66.0 (11 Nov 2026, CF-247 F-INT, Decisions 270 and 270a, first live result): calendar reader calendar-v2.3. A teaching start resolved by its table column stands for its whole row, so the other year columns of that row become starts too (same quote, same column rule, printed weekday must agree); under v2.2 the model reported only the 2026 column of Monash summary-dates, leaving no 2027 start. The reader version change re-reads stored copies through the existing calendar-reread (no Firecrawl). No setting, migration or database rule changes. // was v0.65.0 // v0.65.0 (11 Nov 2026, CF-247 F-INT, Decisions 270 and 270a): calendar reader calendar-v2.2 (calendar.ts). A start printed without a year may take it from its table column (the row above whose cell over the date's column is one year), from a range heading over unlabelled columns only with weekday and academic-period evidence, or from the address when no section gives one and nothing on the page names another year; a weekday printed against the date must agree; a year printed in a row of several years must be in the date's own cell. The central_ai calendar read passes the document address to the reader. The reader version change makes the existing hourly calendar-reread (svc_calendar_reread_next_v2, p_reader) read the stored copies again with no Firecrawl; every reading still goes through the calendar qualifier and approval. No setting, migration or database rule changes. // was v0.64.0 // v0.64.0 (11 Nov 2026, CF-247 F-AER.01, Platform Admin 11 Nov 2026 05:42 "find the issue with AER ... missing providers ... build readers where required"): mode central_find runs one targeted entry-requirements search of a provider's own website (Firecrawl map with search ENTRY_SEARCH, purpose central_entry_search) for a provider AER source discovery asked about (public.svc_aer_entry_search_wanted), when the whole-site map is refused or found no entry page scoring 4 or more, and records it with public.svc_central_entry_record (only the entry suggestions are replaced). The database decides each spend (svc_fc_spend: own interval aer.source_discover_recheck_days, central share, month limit). central.ts: a top-level entry or admission requirements page of a small provider scores 4.5 (it scored 2.3 and was never suggested). Nothing else changed: weakKinds, the whole-site map, every other mode. // was v0.63.0 // v0.63.0 (10 Nov 2026, CF-247 F-PDESC, Platform Admin follow-up 10 Nov 2026): (1) a catalogue name that is a LIST now derives a later entity as a label when it is the full name of a bare short first entity ("Holmesglen, Holmesglen Institute"), with every safeguard of the first-entity label; (2) a failed identity proof also records, in checks.identity.seen.proof, the labels and aliases it used, the headings it read, the cause of the strict refusal and where the registry proof refused (diagnostics only, no result depends on it); The reader behaviour stamp is now provider-description-source-guard-v5 so earlier identity holds are re-tested once on their stored page. Nothing else changed. // was v0.62.0 // v0.62.0 (10 Nov 2026, CF-247 F-PDESC, Platform Admin order 10 Nov 2026 12:07, observability only): when the provider-description identity proof FAILS, the worker also records what the proof was given, in checks.identity.seen (description.ts descriptionIdentitySeen: the first <title>, up to three <h1>, og:site_name, the size of the raw HTML and of the visible text, and whether the page is a script shell with almost no visible text). 199 reads are held provider_name_not_proved (the official /about pages of Swinburne, Collarts, Alphacrucis, Ara, Whitecliffe and Auckland Institute of Studies among them) and the database could not say why. Which pages pass or fail is NOT changed: the strict proof, the registry proof, the sub-unit rule, the own-host rule and every rule after them are the earlier text; no AI, no Firecrawl, no setting. // was v0.61.0 // v0.61.0 (10 Nov 2026, CF-247 F-PDESC delivery, Platform Admin operating model v1.5): the provider reader no longer loses a whole invocation when one record call fails. It posted every result of the invocation to svc_provider_description_record in ONE call at the end; that call failed twice with "canceling statement due to statement timeout" (the API role allows 8 s; 2026-11-09 23:06 and 2026-11-10 01:16 UTC), and a failed call rolls back the ai_calls, the cost (so no ledger row) and the settle of the reservation of every item, which left 73 reservations that nothing settled. Now each item is posted in its own call (its settle is its own transaction), a failed item is tried once more, and an item that still fails is named in the answer (record_errors, HTTP 500) after the others were recorded. A reservation that is still left is settled by the database (migration 20261110140000, security.provider_description_settle_abandoned_v1, called by the fire). Not changed: the lease, the reservation, the AI call, the prompt, the identity proof, the quote proof, the reader behaviour stamp (provider-description-source-guard-v4), the database rules. No setting, no new AI or Firecrawl call. // was v0.60.0 // v0.60.0 (10 Nov 2026, CF-247 F-PDESC delivery, Platform Admin operating model v1.5: one basic-to-enriched provider admission): of 94 AI provider reads 2 were admitted. The model copied its quote into the sentence (verbatim_passage 51) or added a point the quote does not state (unsupported_* 17), and one such sentence held a whole proposal whose other sentences were supported (the University of Sydney read c8dcd88c: five sentences, every quote on the page, held for one sentence at support 0.44). (1) description.ts DESCRIPTION_SYSTEM: one short paraphrase per quote, in the quote's own key words, nothing added, the shortest exact quote, and the copy limit (setting pdesc.verbatim_span_max_chars, sent by the lease) stated to the model by copyNote. (2) The worker no longer holds the whole answer for a copied sentence: every sentence goes to the database, whose validator (migration 20261110110000, drop_failing) leaves out a sentence that fails any sentence rule and keeps the sentences that pass every one; the dropped sentences and why are kept in checks.dropped. Not changed: the identity proof, the quote-on-page proof, the machine word policy, the manual locks, rejection memory, the AI reservation and ceilings, the database rules themselves. The reader behaviour stamp is provider-description-source-guard-v4 so that held reads are offered again once. v0.59.15 (10 Nov 2026, CF-247 F-PDESC, Platform Admin directive 9-10 Nov 2026, University of Sydney and UTS held by provider-description-source-guard-v2): the provider-description identity proof reads a heading as the page shows it and no longer takes a bare institution word in a sentence for another institution's name. (1) description.ts decodeHeadingEntities: numeric and common named HTML entities in the title, h1 and og/application-name content are decoded before the proof (UTS "About UTS &#x2013; University of Technology Sydney" left the stray word "x2013" and was refused as naming something else). (2) description.ts namesAnotherInstitution: an h1 or title segment names another institution only when an institution word (university, college, polytechnic, institute) follows a capitalised non-plain word ("Western Sydney University") or is followed by "of" and a capitalised word ("University of Melbourne"); a sentence such as "...equal opportunities when it comes to education and employment in our university." (The University of Sydney's About page) names nobody. Segments with no case to read keep the old rule, and the sub-unit words (campus, faculty, school) are refused as before. Not changed: the own-host rule, the catalogue-name or registry-abbreviation match with no extra words, the strict proof, the About-page rule, the manual locks, the database validation, the claim checks. The reader behaviour stamp is provider-description-source-guard-v3, so the identity holds of the earlier readers are offered once more on their stored page by the existing re-offer (20261109185000). No migration, no setting, no AI or Firecrawl in the change itself. // was v0.59.14 // v0.59.14 (9 Nov 2026, CF-247 F-PDESC, Platform Admin Directive 3): a provider-description quote the model joined from separate passages with an ellipsis is proven fragment by fragment (description.ts providerDescriptionSentences: each fragment on the page by the whole-quote rule, at least pdesc.min_quote_chars each, in the page's order, at least two), only when the switch reading.provider_quote_fragments_on is on (ships off, no migration in this change); a quote whole on the page is proven as before and a failed fragment is quote_not_on_page as before. The identity proof, the claim checks, the manual locks and the database validation are unchanged. No AI, no Firecrawl. // was v0.59.13 // v0.59.13 (9 Nov 2026, CF-247 F-PDESC, Platform Admin Directive 3 Blocker B): the provider-description identity proof also accepts registry-proved evidence (description.ts descriptionSourceIdentity with the lease's own verified hosts, descriptionIdentityAliases): the page is on the provider's own verified host and the title, an h1, og:site_name or og:title is exactly the catalogue name or a registry abbreviation of it, and no heading names another institution, an offshore branch, a college, faculty, school or campus. The strict proof runs first and is unchanged; the About-page rule, the sub-unit rule, the manual locks and the database validation are unchanged. No AI, no Firecrawl, no setting, no migration. // was v0.59.12 // v0.59.12 (9 Nov 2026, CF-247 F-PDESC, Platform Admin data population mandate 9 Nov 2026 section 2): the provider-description identity proof also accepts the catalogue name without an abbreviation-only parenthetical and the first entity of a ; or , list (description.ts descriptionIdentityLabels), so names such as "University of Technology Sydney (UTS)" can be proved on the university's own page; every other identity check is unchanged (the label must be the whole title or h1, a different institution or a sub-unit heading is still refused). No AI, no Firecrawl, no setting. // was v0.59.11 // v0.59.11 (8 Nov 2026, CF-247 AER reader quality, Platform Admin directive 8 Nov 2026): a course quote the model joined from separate passages with an ellipsis is proven fragment by fragment (each on the page, in order; switch reading.course_quote_fragments_on, ships off), its stored length is the setting enrich.course_entry_quote_chars and a quote kept short of what the model gave is recorded on the row and counted in the read's coverage (quotes_cut), a requirement read twice is one row (as the database counts it), the entry matrix reader resolves governed country aliases (reading.entry_country_aliases, switch reading.entry_country_aliases_on, ships off) and can keep a row whose grade is printed when only its number has no printed basis (reading.entry_value_null_on, ships off). Every other check unchanged; no AI, no Firecrawl. // was v0.59.10 // v0.59.10 (6 Nov 2026, CF-247 English requirements, Platform Admin 6 Nov 09:44 §3 D5): mode provider_facts_add_tests also reads stored English pages again with the current policy parser (provider-policy-v0.3.0: faculty and course-group tables returned as group rules) for the documents svc_provider_policy_reparse_next lists, no Firecrawl and no AI, sized by reparse_limit (batch.policy_reparse); the add-tests reading stays keyed on provider-policy-v0.2.5 (ADD_TESTS_PARSER) because its rules did not change.
// Previous feature worker v0.59.9: approved one-reask course descriptions retained in this combined English worker.
// was v0.59.8 // v0.59.8 (5 Nov 2026, CF-247 final intake recovery, migration 20261105040000): calendar reader calendar-v2.1 (the year of a start from its own section: heading, title or year tabs; a wrong-section year rejected); mode calendar_reread reads again what an earlier reader read (svc_calendar_reread_next_v2 / _record_v2 with the reader version) and hands stale editions to the existing reads within the credit budget (svc_calendar_refresh_v1).
// was v0.59.7 // v0.59.7 (5 Nov 2026, CF-247 intake recovery, migration 20261105020000): academic calendars read by calendar-v2 (dated starts with meaning, deadlines with who they apply to, scope, slices, notes from earlier findings; calendar.ts) and mode calendar_reread (stored calendars again: the dated parser first, the AI queue only when the parser cannot read it safely).
// was v0.59.6 // v0.59.6 (3 Nov 2026, CF-247 IQ-00111 P0 fee integrity, migration 20261104140000): fee_ai asks the model for each fee row's units_kind (units or credit points), the page's own full_time_load, course_years and whole_course, and names the kind the country load counts (fee_country_profiles.units_are); the database makes the yearly figure from them and holds an unclear one (security.fee_reader_yearly_v1, fees.units_load_fix_on) and keeps page fees out while a fee hold or fee-check exclusion is active (fees.respect_holds_on); nothing else changes.
// was v0.59.5 // v0.59.5 (3 Nov 2026, CF-247 P0 autonomous operations, workstream B worker release for the other workstreams' interface requests, Integration Controller 18:20): new mode ops_diagnose (ops-diagnose.ts; workstream A contract ops-diagnose-v1: AI-assisted diagnosis through svc_ops_diagnosis_next and svc_ops_diagnosis_record, pinned model, existing OpenRouter path, each request answered exactly once, {error} on failure); enrich_ai keeps its answers first (svc_enrich_ai_stash_v1, workstream D) and records them as before; the entry matrix reader keeps the model's value, grade and scale in every dropped entry and, each behind a reading.* setting that ships off, reads a printed range as its lower bound, merges subject-equivalence rows into one subject-prerequisite row and stops holding a global-qualification page that says it applies in any country (entry.ts; workstream C); link_search answers each distinct query once and reuses an earlier answer for the same query (link-share.ts, reading.link_search_share_on, ships off; workstream F).
// was v0.59.4 // v0.59.4 (3 Nov 2026, CF-247 Workstream C, Platform Admin direction 3 Nov 2026 09:32, acceptance report item 1): enrich_ai reads course description and application deadline (Enrich fields fields description and deadline) from the course's stored page in one call per course (course-text.ts, prompt course-text-v1, the central model, answer limit reading.answer_tokens.course_text); every quote is checked against the page; nothing is fetched or cut here; the database admits, holds or sends to Layer 4 (security.enrich_course_text_record_v1); every other read is unchanged.
// was v0.59.3 // v0.59.3 (3 Nov 2026, CF-247 Workstream F, hidden failures; Platform Admin direction 3 Nov 2026 09:32 §5): nz_cop reports what each call did (read: files read, failed: files that failed), so the run ledger counts its work; it was recorded as 0 items on every call and looked as if it had never succeeded; nothing else changes.
// was v0.59.1 // v0.59.1 (3 Nov 2026, CF-247 Workstream D, intake wording): the page reader (extract.ts) never keeps a month the page excludes ("excluding January & December", "except June and December") as an intake; nothing else changes.
// was v0.59.0 // v0.59.0 (3 Nov 2026, CF-247 Scholarship Coverage Recovery, mandate 17:41 and direction 23:24): scholarship discovery maps every source a provider has (F4), a refused map is deferred, not empty (F3); listing pages are read page by page until the pagination ends, complete or partial (F6), and their items, including the awards of an umbrella page, become candidates (F5); a page that now opens elsewhere is moved or redirected away (F7); the all-time scholarship cap is retired into the daily share (F8); scholarship run sizes and the render wait are settings (F10).
// was v0.58.0 // v0.58.0 (2 Nov 2026, CF-247 P1 pilot finding 16:16): provider_description reads only the provider's own About or Overview page: the home page's links and the central page finder's suggestions pass the page rule (description.ts aboutPageCheck, the same as security.provider_description_page_v1; lists from the lease: refused news, events, research, staff, faculty and school pages and staff or intranet subdomains; the About name first in the path; the main site host first); the model is told the sentence and character limits the validation applies (prompt provider-description-v2). No other mode changes.
// was v0.57.0 // v0.57.0 (2 Nov 2026, CF-247 missing-field enrichment P1, Platform Admin 2 Nov 2026 10:28; approved 14:50): new mode provider_description (description.ts): a provider's stored About / Overview copy first, otherwise the About link of its home page on its own hosts, read directly (robots.txt respected; Firecrawl only when the site refuses, within the Firecrawl budget); the pinned Enrich fields model writes 2 to 5 sentences, each with the page's exact words, every quote checked against the page; svc_provider_description_record validates and proposes to Layer 4. No other mode changes.
// was v0.56.0 // v0.56.0 (2 Nov 2026, Platform Admin 11:10 §2, intake dates): the calendar parser (policy.ts calendarStarts, calendar-dates-v1) also keeps each start's printed day and year and the period's "applications close" date or rolling wording; months, years and quotes are unchanged. v0.55.0 (31 Oct 2026, StudySearch decision D13): read mode honours direct_only from svc_coverage_read_next (re-read pilot pages are read directly only, never through Firecrawl). v0.54.1: // v0.54.1 (30 Oct 2026, CF-247 decision W31, course-page identity): the labelled NZQA number rule in extract.ts identity() applies to New Zealand pages (and callers that give no country) only, never another known country (College of the North Atlantic, Canada, had 53 pages proved as nzqa_code); nothing else changes.
// was v0.54.0 // v0.54.0 (30 Oct 2026, CF-247 decisions W30 and W32; W32, reader answer limits): every AI read's answer limit is a setting (reading.answer_tokens.<read>, answer.ts; defaults are the values fixed in the code before, and the fee reader, which sent none, gets 32,000); an answer that reached its limit (finish_reason length, or not JSON at the limit) is held_partial: output_truncated on the existing failure path and never parsed or proposed; the cost of every call is recorded also when the read fails (Enrich fields, scholarship pages, central pages, fee pages); an empty answer to a scholarship re-check or a course page match fails named instead of being read as "{}".
// was v0.53.1 // v0.53.1 (30 Oct 2026, CF-247 decision W30, enrichment reliability): adapter_capture reports items (sample pages) and failed (pages with no capture) and adapter_propose reports its one proposal, so the per-call ledger and the hourly health report no longer read a working capture as 0 of 0; nothing else changes.
// was v0.53.0 // v0.53.0 (29 Oct 2026, CF-247 AER decision W29, course-level reading of long pages in bounded slices): a course page's entry requirements are read in contiguous slices of the stored text (enrich.course_entry_slice_chars, overlap enrich.course_entry_slice_overlap_chars, at most enrich.course_entry_max_slices, enrich.course_entry_slice_concurrency at a time), each answer limited by enrich.course_entry_max_tokens instead of a fixed 2,000 tokens; a cut, empty or unreadable answer fails its slice, named (output_truncated, no_answer, unreadable_answer), and any slice not read whole holds the whole read (held_partial), as does a page longer than entry.course_page_chars (never cut silently); rows keep their quote on their slice, are joined in page order and a row read twice in an overlap is kept once; the calls' cost is recorded on a failed read too; a one-slice page is asked exactly as before. // v0.52.0 (29 Oct 2026, AER reader corrections for Federation, Otago Polytechnic, Wollongong and UWA, Platform Admin mandate 28 Oct 23:22 and decision 29 Oct 09:57): a printed cell quoted with the structure that names it is on the page (a table's header line with one of its rows, a PDF row's first cell with one other cell of the row), a band given with its column header's words ("ATAR 70") is the printed cell only when the whole row is quoted, and a table with no header row carries the label printed just above it on each line; every gate unchanged. // v0.51.0 (29 Oct 2026, AER programme Step B acceptance for Western Sydney and Victoria University): a page's slices are read entry.matrix_slice_concurrency at a time (1 keeps the old one-after-another order) and joined in slice order, so a long table fits the call's time; a reply cut while it streamed is named instead of taken as an empty answer; a PDF table of five or more columns (a requirement per column) gives each data cell on its own line with its row's first cell, so a requirement can be quoted whole; every gate unchanged. // v0.50.2 (29 Oct 2026, AER programme reads): an entry page the site refuses to a direct read is kept from Firecrawl as its own HTML (rawHtml), not markdown, so its tables are read row by row and quoted against the same lines as a direct read (AUT read 0 rows; Wintec, Lincoln and Otago Polytechnic lost rows as quote_not_on_page against markdown tables); an entry-matrix read whose model call answers with no text names why (the provider error or finish reason OpenRouter returns, and the slice), so the hold is recorded with its exact reason (Victoria University, Western Sydney and Manukau were recorded only as "the model returned no answer"); nothing else changes. // v0.50.1 (29 Oct 2026, AER programme Wave H reads): an HTML table whose data cells are all bare numbers (a rank-to-score or score-to-ATAR conversion) gives each data cell named by its column header, so its row lines can be quoted whole (ANU and UWA rows were dropped as quote_too_short or quote_not_on_page); the read is told so; tables with worded cells are unchanged. // v0.50.0 (29 Oct 2026, AER programme Steps B and C, Platform Admin consolidated mandate 28 Oct 23:22): Step C: a page whose requirements the browser draws (entry.render_hosts) is read once rendered through Firecrawl (rawHtml, entry.render_wait_ms), robots.txt respected, within the budget check, and read like any page; no minimum on the rendered page gives no rows (contact provider). Step B: PDF entry matrices. A PDF source is fetched directly (robots.txt respected, never through Firecrawl, size cap entry.pdf_max_bytes) and stored whole; before any AI read its tables are rebuilt from the PDF's own drawn rules (pdf.ts, ruled-cells-v1): every text item must sit inside one column and between two row rules, each cell is named by its column header, and anything not proven holds the whole document (held_unparsed, with the page and text), for every provider. // v0.49.2 (29 Oct 2026, AER programme Wave H): the entry-matrix read takes its slice size and answer length from settings (entry.matrix_slice_chars, entry.matrix_max_tokens) and names an answer cut off at its length limit (output_truncated) instead of failing on the cut-off JSON. // v0.49.1 (28 Oct 2026, Track C Step B): the entry-requirements read uses the whole stored page text (navigation, header and footer left out), not only its <main> element, so it does not depend on where a page places its entry section. // v0.49.0 (28 Oct 2026, Platform Admin 20:36, Track C Step B B1): enrich_ai reads a course's academic entry requirements (field entry_requirements) from its stored course page with the pinned entry model (entry.matrix_model), one call per course with its own prompt; each row keeps its exact quote and is dropped when the quote is not on the page; a band only when the page prints one (never from an ATAR); English tests are not asked; the database proposes the rows for a person in Layer 4. // v0.48.8 (27 Oct 2026, Platform Admin 14:35, AER PR A): the source-table manifest skips a header row printed again inside a table body (Singapore); the completeness guard breaks a tie between two columns that differ only by a one-character word using every word (Sri Lanka, Thailand, UK), and leaves a remaining tie unresolved; a column of bare numbers on a page that prints no scale is held as a source hold before any AI read (Norway). // v0.48.7 (27 Oct 2026, Platform Admin 05:46, D4): a one-slice page with a readable band table is read with its published cells listed from the manifest in printed order (one row each: repeated values, merged case-by-case cells and printed columns kept); a row whose quoted line publishes no minimum is dropped (no_minimum_published); the guard is unchanged. // v0.48.6 (27 Oct 2026, Platform Admin 05:46, D5): the source-table manifest recognises a grading or calculation footnote row before any width check, and reads a data row whose trailing cells were left out of the markup with those cells blank unless a merged cell from above spans them (then unparsed); a wider data row stays unparsed. // v0.48.5 (27 Oct 2026, Platform Admin 05:46): read-only mode entry_inspect returns stored entry-matrix pages' h1, title and table markup for the D5/D4 test fixtures (no AI, no fetch, no write). // v0.48.4 (27 Oct 2026, Platform Admin 04:58, RMIT D1-D3): a band given as the page's own "Not applicable" is no band where the quoted line prints none (D1); a table that is not one country's (requirement-type columns, or a heading naming no country of the reference list) is held unparsed before any AI read, terminal (D2). // v0.48.3 (26 Oct 2026, Platform Admin 23:16, completeness guard): entry_ai builds a manifest of every minimum the stored page's band tables publish and compares the whole read with it; for a provider under entry.completeness_providers a read that omits or misplaces any entry, or keeps a row it cannot explain (a cell-only quote among them), is held whole (proposed nothing, kept in the run history, retried within entry.matrix_attempts); a page whose tables cannot be read so is held before any AI read. // v0.48.2 (26 Oct 2026, AER v1.1 RMIT re-read): entry_ai checks each row's benchmark band against the band the quoted table line prints in its "Australian standard" column; a row whose quote shows a band it did not give is dropped (band_missing), and the band kept is the one printed. // v0.48.1 (26 Oct 2026, AER v1.1 first runs): entry_ai gives a stored HTML page with each table row as one line and a merged or blank row label carried down (RMIT band ladders: 21 of 22 rows were dropped as quote_not_on_page); quotes are checked against that same text. // v0.48.0 (CF-247 Track C, entry requirements step A, drafted 25 Oct 2026; merge queue #694 → SP-1 → Track C; extraction runs after Track B release 1): mode entry_ai reads providers' entry-requirements pages (stored copy first; direct read with robots.txt respected; Firecrawl only when refused) and reads each new stored version with the pinned model entry.matrix_model into quoted rows; the database proposes them and a person admits them in Layer 4. Nothing runs while entry.matrix_enabled is 0. // v0.47.0 (CF-247 SP-1, speed programme): every Firecrawl refusal has a name (target_list_refused, credits_reserve, scholarship_share, no_firecrawl_key, credits_refused) and refusals decided in the worker are recorded by name (svc_fc_refusal_note_v1); "budget" is no longer used for a target-list refusal; discovery also maps the extra course domains a person added for a provider. // v0.46.0 (24 Oct 2026, R1 — Platform Admin 09:55 "R1, for real this time"): every call reports its outcome (what it processed, how much succeeded and failed, where it landed, its time) to the per-mode ledger (svc_worker_report_v1, Q3); a course data file (.json address) that answers with the course page itself is read as that page instead of being refused as not JSON (the University of Sydney companion files, Q4). // v0.45.0 (24 Oct 2026, Platform Admin 07:32 "cricos is only applicable for au and no other country"): identity rule identity-v0.6.0: the cricos_code proof is given only to Australian pages; a New Zealand page proved by its own programme code is labelled nzqa_code and a Canadian page by its catalogue code adapter_code; other countries rely on the title rules. Mismatched pages are re-verified once under the new rule. // v0.44.0 v0.44.0 (23 Oct 2026, Platform Admin 23:13 "Go", read lane capacity): mode read takes up to 200 pages a call (the Settings maximum of Read course pages; it was capped at 60 in the worker, so the setting had no effect above 60) and fetches reading.pages_at_once pages at the same time (1 to 32; it was 8, fixed here). // v0.43.0 v0.43.0 (23 Oct 2026, Platform Admin 19:27 "Lets test openrouter where it goes bottleneck, and make that settings configurable in ui"): enrich_ai and fee_ai count every OpenRouter call (answered, 429, 5xx, other, timed out) with its time and return the summary; enrich_ai reads as many pages at once as the database sends (enrich.ai_pages_at_once, at most 12); fee_ai up to 16 pages at once (fees.concurrency). v0.42.4 // v0.42.4 (23 Oct 2026, Auckland diplomas: campus list empty): a campus the AI lists from a name given as a list (["City","South Auckland"]) keeps that name, as the database matches by containment. v0.42.3 // v0.42.3 (23 Oct 2026, Read with AI on the Auckland diplomas: campus, duration and delivery "not stated"): enrich_ai also reads a page's labelled data items held outside its main text (University of Auckland catalogue: Campus, Duration full time, Delivery mode, Study mode), given first as "Label: value". v0.42.2 // v0.42.2 (23 Oct 2026, Platform Admin 12:52 "Still no city"): campus and duration may be read from a short data label on the page (University of Auckland catalogue: ["City","South Auckland"]). v0.42.1 // v0.42.1 (23 Oct 2026, first AI reader run on NZ): intakes may be the semesters, trimesters or terms a page names (the database maps them through the approved university calendar); refusals for English and intakes say why. v0.42.0 // v0.42.0 (23 Oct 2026, Platform Admin 10:25 "cross check the gaps and accommodate the ai reader"): enrich_ai also reads the IELTS requirement and the start months from the stored course page (each quoted, the quote must name IELTS with a score, or a month), and gives each campus city its region from the country's list. v0.41.1 // v0.41.1 (23 Oct 2026, Platform Admin 09:03 "what maximum system can handle"): fee_ai reads up to 40 pages a call, as many at once as the job asks (fees.concurrency, at most 8). v0.41.0 // v0.41.0 (23 Oct 2026, Platform Admin "Through the AI fee reader"): mode fee_ai also reads a course's own page (stored HTML read as text), told it is one course's page; the course list is that course. v0.40.9 // v0.40.9 (23 Oct 2026): the newer-version link is found inside escaped markup too (Auckland catalogue read at 08:05 still gave the 2026 fee). v0.40.8 (23 Oct 2026, University of Auckland catalogue audit): a course page that links to itself with a later year is read // v0.40.8 (23 Oct 2026, University of Auckland catalogue audit): a course page that links to itself with a later year is read at that newest version; page text keeps values carried as escaped markup; a fee amount's own label decides its audience (extractor). v0.40.7 (23 Oct 2026): the source finder learns up to three course folders per university (UNSW kept only its postgraduate site map). v0.40.6 (23 Oct 2026): programme page headings and titles have null characters removed before they are recorded. v0.40.5 (23 Oct 2026): source_find, programme_discover and course_list_read report their work as items, done and read, the keys the idle guard counts (the guard paused source-find after the test runs, whose replies it read as empty). v0.40.4 (23 Oct 2026, test-run Firecrawl check): course list and programme list pages read through the scraper are recorded as list_scrape (1 credit, a plain page) instead of fcx_course_list, which the spend check priced as an AI-extraction scrape (5 credits), so they no longer count five-fold against the daily budget. v0.40.3 (23 Oct 2026, test run on 34 universities: 24 found): a source with at least as many course addresses as known pages is kept even when stale known pages lower its recall; with no known pages it needs twice the minimum; list pages the Firecrawl map names (find-a-course, course-search, ...) are tried first, then the course folder with and without its first part; the scraper gets 45 seconds for a heavy list page. v0.40.2 (23 Oct 2026, second test run): the source finder waits at most 10 seconds for a robots.txt or site map and skips the site maps of a host that does not answer direct reads; the finder works in steps carried over between runs (map, map_search, sitemap, lists), one step per university per call, so no step uses up the call; the course address pattern allows the depths the known pages have; known pages are taken at the address they were read at. v0.40.1 (23 Oct 2026, first source finder test run): the finder looks at every host a Firecrawl map returns (a university's study site such as admission.umontreal.ca), maps again searched for the course words when the first map gives too few, and leaves a university it ran out of time on for the next run instead of recording nothing found. v0.40.0 (22 Oct 2026, Platform Admin 23:46 "Platform needs to independently read website"): mode source_find finds a university's own course source with no person: it learns the address pattern of its course pages from those already found (or the largest course-named folder of its site map), reads robots.txt and its site maps, keeps a site map that gives enough course addresses and holds enough of the known pages, otherwise tries the course folder and the usual list addresses, and reports every try with its counts. v0.39.0 (22 Oct 2026, Platform Admin 22:55 and 23:09, courses from the university's own programme list): mode programme_discover reads a university's programme site map (following the index files its child pattern picks) or list page and records the programme page addresses that fit its pattern; mode programme_read reads each programme page directly (the scraper only when blocked) for its heading, title and final address, and the database maps the credential the heading names to a study level. A page bound from a programme list may be read through the scraper. A course list may be a site map with an address pattern (link_pattern; index files followed by child_pattern), for course finders that are search apps. v0.38.1 (22 Oct 2026): pages chosen by the AI page match from the university's own site may be read through the scraper when blocked. v0.38.0 (22 Oct 2026, Platform Admin "Widen to colleges, level required"): mode credential_read reads the credential a college course page states (for example "Credential: Ontario College Diploma") from the stored page, with the patterns the database gives; the database maps it to a study level. v0.37.2 (22 Oct 2026, Waikato): a course list whose next-page buttons have no links is followed by the page number in its address (page=2, 3, ...) while each page adds course links, up to course_list.max_pages. v0.37.1 (22 Oct 2026, first live course list read, Waikato): course links are those under the list page's own folder; too few of them means the scraper reads the page (a list drawn by the browser), and only they are kept when there are enough. v0.37.0 (22 Oct 2026, Platform Admin "Course list page per provider"): mode course_list_read reads a provider's own course list page (direct, then the scraper when too few links), follows its next pages, and records every course link with its link text for the page matchers. v0.36.2 (22 Oct 2026, Platform Admin "Yes: fees and English" for Sydney): the direct reader reads an address ending in .json (a course data file) as JSON text; companion pages use it for the University of Sydney's .coredata.json. v0.36.1 (22 Oct 2026, Platform Admin "proceed with AUT fee fix"): the fee reader is told that an amount printed for a number of points ("$19,929.84 (for 60 points)") is the fee for those points, not per point, and returns units_covered; the database works the yearly figure out from it. v0.36.0 (22 Oct 2026, NZ enrichment review, Platform Admin "Quick wins: 1, 3, 6, 8"): an Enrich fields answer whose quote was not on the page is asked once more with a note (then skipped); the fee reader removes null characters from page text and answers (two reads were refused by the database) and records a page with no money amount as no rows without an AI call; a course page found by a search that needed a browser is read through Firecrawl once when the database says so (render_ok, pages.render_countries). v0.35.0 (21 Oct 2026, Platform Admin 20:02 "Build fee reader for nz unis ... compatible to ca and upcoming countries ... collect and feed error to build and evolve data reader"): mode fee_ai reads stored fee pages with the pinned central-page model into rows as published (qualification, subject, amount or range, currency, unit, audience, fee year, quote) matched to the provider's courses; the country's rules, the provider's reading notes and its open findings go with every read; rows whose quote or amount is not on the page are dropped and counted; the database admits above the confidence setting or sends to Layer 4. v0.34.2 (21 Oct 2026, Platform Admin "Keep two, fix reader"): Enrich fields asks for delivery with the two meanings told apart: blended when each student mixes campus and online in one course (hours or a share each way, online with block or onsite weeks), on_campus_and_online when the page offers a choice of modes, on_campus when online is only for domestic students. v0.34.1 (20 Oct 2026, first nz_cop results: all eight universities lacked the signatory sentence): nz_cop keeps each provider's NZQA type, whether the page says it is not a signatory, and the words around "Code"; a missing sentence no longer means No. v0.34.0 (20 Oct 2026, Platform Admin "NZQA Code signatory"): mode nz_cop reads the stored NZQA provider pages (Layer 1 batch files) and records whether each New Zealand provider is a signatory to the Code of Practice for international students; the database sets the international-enrolment flag. v0.33.1 (19 Oct 2026, first re-check results): a re-check sentence that is on the page but does not name international students counts as "international students not mentioned". v0.33.0 (19 Oct 2026, Platform Admin "AI re-check, then finish"): mode scholarship_recheck asks the first model of the scholarship chain who may apply and the value of a held scholarship page, each with its sentence; the sentences are checked on the page and the result is kept on the held item as a recommendation (nothing published or rejected). v0.32.0 (19 Oct 2026, Platform Admin "store them efficiently without bloating the DB"): a course page re-read whose text is the same as the copy in use (hash of the page text, scripts and spacing left out) keeps that copy: nothing is stored again and no new evidence record is made; the text hash is kept with each new copy. v0.31.0 (18 Oct 2026, bug 18/10-01): mode site_check reads the home page of an address asked for in the Adapter builder (1.1 Check website / Change website) and records what it shows. v0.30.1 (18 Oct 2026): seven modes nothing ran in 30 days removed (directory_capture, fc_extract_qualify, id_qualify, openrouter_key, page_codes, reference_capture, site_hint_verify). v0.30.0 (18 Oct 2026, Decision 267): adapters read majors (pattern field, every match kept) for Build adapter; the builder proposes a majors pattern. v0.29.0 (18 Oct 2026, Decision 265): mode companion_read reads a page beside the course page (Melbourne entry requirements) and keeps the values its patterns find. v0.28.0 (17 Oct 2026, Decision 264): adapters read english_level (the English level a course page names, such as "Band 2"); the database writes that level's scores from the approved policy. v0.27.2 (17 Oct 2026, Decision 262): policy parser v0.2.5 (a section for courses with alternative English requirements gives no default). v0.27.1 (17 Oct 2026, R18 first run): policy parser v0.2.4 ("105 Overall ; 110 Speaking" is 105 overall); add-tests sends only the tests learnt after approval (ADDED_TESTS, today DET). v0.27.0 (17 Oct 2026, CF-247 R18): policy parser v0.2.3 reads the Duolingo English Test; mode provider_facts_add_tests reads approved English policy pages again from their stored copies and the database adds tests learnt since approval where the page's IELTS for the level matches. v0.26.0 (15 Oct 2026, flag unit): mode flag_check reads held providers' home pages directly (no Firecrawl, no AI) and releases those that answer. v0.25.2 (15 Oct 2026): a white (reverse) logo is never used; the provider is flagged for an upload instead. v0.25.1 (15 Oct 2026, first runs): a logo is named by its file or label, not its folder (a campus photo was taken); JPEGs and white logos rank low; the size check uses the longer side (wide wordmarks were refused); mask icons last. v0.25.0 (15 Oct 2026, Platform Admin: "make it background Job to find and attached"): mode logo_find takes a provider's logo from its own home page (header logo, declared logo, SVG icon, touch icon), checks the bytes, size and SVG content, stores it and records it; not found is flagged. v0.24.0 (15 Oct 2026, v2.15.279, Platform Admin "Research degrees need a research default"): the central English policy reader also reports the requirement for research masters and doctorates, with its quote; it is used only where the page states it. v0.23.2 (14 Oct 2026, v2.15.276 O7): a duration quote about the fee basis is not admitted. v0.23.1 (14 Oct 2026, v2.15.275 hotfix): null characters removed before an Enrich fields result is recorded. v0.23.0 (14 Oct 2026, v2.15.275): Enrich fields page text and titles per call read from settings. v0.22.2 (14 Oct 2026): international needs a quote about the course's students or fees. v0.22.1 (14 Oct 2026): enrich_ai reads stored copies that are gzip or plain. v0.22.0 (14 Oct 2026, CF-247 v2.15.273): mode enrich_ai for the Enrich fields job (stored pages, titles, campus lists, addresses). v0.21.7 (13 Oct 2026, CF-247 v2.15.269): Firecrawl proxy, site map sizes and search result counts read from settings (svc_worker_settings_v1). v0.21.6 (13 Oct 2026, Platform Admin: "learn and establish how best to find the uni official website ... use training.gov.au or ASQA, CRICOS/RTO code, flag the exceptions"): find_site looks an Australian provider up on the official registers first (training.gov.au, then the TEQSA National Register) and accepts the website the register lists only when its home page shows the provider's CRICOS code or its address fits the provider's name; then the CRICOS-code search as before; the RTO code found is kept in the evidence. v0.21.5 (12 Oct 2026, Platform Admin 23:54: "use Firecrawl for pages found by CRICOS code or listed by the uni"): a course page is read through Firecrawl only when it was found by its CRICOS code (cricos_search, cricos_code, cricos_code_on_page), is listed on the university's own site (title_match, cms_path_public), or was entered by a person (manual); pages found by a title or web search (title_search, firecrawl_search, serper_search, ai_match and the rest) are read directly only (Firecrawl read 99.7% correct pages for CRICOS-code finds and 87% for listed pages, but 48% for title searches and 24% for Firecrawl searches). v0.21.4 (12 Oct 2026, Platform Admin 21:47, Firecrawl daily budget of 15,000): every Firecrawl spend goes through svc_fc_spend, which keeps to the day's share by purpose and the day's billed total and to the per-university caps (scholarships 150 credits in 30 days, central pages again after 30 days, course search stopped after 30 searches with no correct page); a refused spend is not made. Firecrawl runs and adapter sample pages stop when their share is used. v0.21.3 (12 Oct 2026, Platform Admin 21:21, Firecrawl credits): a found course page is read directly first and through Firecrawl only when the direct read is blocked or needs a browser; every Firecrawl scrape uses the basic proxy (no automatic stealth retry). v0.21.2 (12 Oct 2026, Platform Admin 20:00: "use the mechanism that has been successful with Firecrawl in finding course pages, not direct HTTP"): a course page the search found (Firecrawl search) is read through Firecrawl too, rendered, the same scraper that found it; a direct read only when the scraper cannot be used. v0.21.1 (12 Oct 2026, bug 12/10-01): mode openrouter_balance reads the OpenRouter balance (credits) for the AI limits, now that the Layer 3 route guard that read it is retired. v0.21.0 (12 Oct 2026, Platform Admin status review, fix 3): mode central_ai reads a university's stored English language policy or academic calendar page with a pinned model; every score and month must be in a quote that is on the page; the result is recorded as a proposal a person approves (never applied here). v0.20.3 (12 Oct 2026, Platform Admin status review): an audience quote that names another country or region ("students from Papua New Guinea", "citizens of the People's Republic of China") or says "not a domestic student" proves international; the university's own country (and Australia/New Zealand for each other) does not. v0.20.2 (11 Oct 2026): an audience quote must itself name international (or domestic) students. v0.20.1 (11 Oct 2026): the AI value check uses only the numbers of the answer's value kind; an empty or cut-off answer is named. v0.20.0 (11 Oct 2026, Platform Admin bugs 11/10-6): mode scholarship_ai reads each queued scholarship page with a pinned AI model and checks every quote against the page. v0.19.3 (11 Oct 2026): extractor v0.7.3. v0.19.2 (11 Oct 2026, Platform Admin bugs 11/10-5): every scholarship candidate page read keeps a stored copy, refused and too-thin pages too. v0.19.1 (11 Oct 2026): a provider home page that refuses a direct read is checked through the scraper when its website is verified. v0.19.0 (11 Oct 2026, Platform Admin bugs 11/10-2): find_site searches every provider without a website (not only Firecrawl targets), by name for New Zealand, Australia without a CRICOS code and any other country; mode central_find (Firecrawl map, key dates, international fees and English requirements suggested); an adapter proposal cut off at its length limit is asked again once with a larger limit, and tokens are recorded. v0.18.2 (11 Oct 2026): extractor v0.7.2. v0.18.1 (11 Oct 2026): extractor v0.7.1. v0.18.0 (11 Oct 2026, Platform Admin): scholarship pages, listing pages, candidates and site maps are read through the scraper only (no direct read, no fallback, robots.txt not consulted for scholarship pages); a page waits when the scraper cannot be used; the register (Study Australia) search phase is retired; extractor v0.7.0. v0.17.42 (11 Oct 2026): scholarship reads are recorded at most two at a time (six at once hit the 8-second limit). v0.17.41 (11 Oct 2026): a scholarship read whose record hits the database time limit is retried once, then left for the next run, instead of failing the whole call. v0.17.40 (11 Oct 2026, Platform Admin "always use the scraper for scholarships"): scholarship pages and listing pages are read through Firecrawl first (rendered rawHtml, as course pages with a view are read) while the Layer 2 setting read_via_scraper is on, for any provider, within the scholarship credit cap; a direct read is the fallback. v0.17.39 (11 Oct 2026): a listing heading takes the first provider link under it. v0.17.38 (11 Oct 2026): listing reader leaves out questions, calls to action, brochures and sentence headings. v0.17.37 (11 Oct 2026): mode scholarship_listing (provider listing pages for the coverage check). v0.17.36 (11 Oct 2026): scholarship reader v0.6.3. v0.17.35 (10 Oct 2026): contact_page keeps only email addresses on the provider's own domain (not a library or helpdesk service) and skips library, vet hospital, clinic, ethics, philanthropy, partnership, facilities and research mailboxes. v0.17.34 (10 Oct 2026): contact_page skips media, security, feedback and similar mailboxes and prefers the main contact page; cricos_peo reads the CRICOS institution page by provider code directly (no search). v0.17.33 (10 Oct 2026, Platform Admin Fix 2): modes contact_page (public phone and email from the provider's own site, direct reads) and cricos_peo (Principal Executive Officer from the CRICOS website, internal only). v0.17.32 (10 Oct 2026, Platform Admin Feature 1): an AU site found by the CRICOS-code search is accepted only when the code is on its home page, or on a deeper page of a site whose address fits the provider's name; a course directory's profile page no longer passes. v0.17.31 (8 Oct 2026): CRICOS v2 replays read each location set in a call of its own after the records. v0.17.30 (8 Oct 2026): the CRICOS adapter joins and reads only the records of the slice (version 2 ran out of worker resources reading all of them every call). v0.17.29 (8 Oct 2026): text_items also reads bundles of stored pages, lists, lookups and nested objects (ALIS, EPBC). v0.17.28 (8 Oct 2026): text_items fields are read in dependency order (jsonb does not keep key order; Conestoga read 0). v0.17.27 (8 Oct 2026): a key repeated within one call is saved as key#2, key#3 (both engines number repeats in file order), so one save never updates the same row twice. v0.17.26 (8 Oct 2026): register_replay reads Canadian catalogues stored as one page or JSON file (text_items) against copies of their Layer 1 readers. v0.17.25 (8 Oct 2026): CRICOS replays also compare provider addresses and campus and course locations when the spec has them. v0.17.24 (8 Oct 2026): a replay run is leased to one call and released when the call ends. v0.17.23 (8 Oct 2026): the QILT reference follows qilt-au-etl v0.3.1 (upper bound stored). v0.17.22 (8 Oct 2026): register_replay also reads statistics published as Excel workbooks (PRISMS SA4, QILT national report tables), one stored workbook a call. v0.17.21 (8 Oct 2026): register_replay also reads registers published as web pages (NZQA): a run lists its stored batch files and three are read a call. v0.17.20 (8 Oct 2026): register_replay works in slices of 4,000 records a call (the whole archive in one call exceeded the edge resource limit). v0.17.19: mode register_replay reads a stored register archive with the register adapter and with the current Layer 1 code. v0.17.18: mode page_codes lists the CRICOS-shaped codes on stored pages for Rule 6. v0.17.17: retention_files also removes unreferenced evidence files.
// was v0.17.15 // v0.17.15 (8 Oct 2026): adding a sample keeps pages already captured; the proposal reads every sample (up to 10).
// was v0.17.14 // v0.17.14 (7 Oct 2026): adapter proposal answer up to 4000 tokens; a cut-off answer says so in plain words. // v0.17.13 (decision D2, opt-in per adapter, reading): numeric and capitalised start dates read as months, 34 to 44 weeks is one academic year. // v0.17.12: an adapter reads the fields of a page already confirmed (bound by hand), "Sept" is September. // v0.17.11: "wks" read as weeks, years not rounded before dividing. // v0.17.10: annual from a whole-course total for courses under a year. // v0.17.9: course years from months, weeks, semesters or trimesters; other_requirements read for review. v0.17.8: entry_requirement read for review (Coverage › Universities). v0.17.7: annual fee from a whole-course fee and full-time years (fee_total, course_years); exit awards read (exit_awards). v0.17.6: a search page rendered before keeps the Firecrawl fallback (rendered_before). v0.17.5: page_view.url_pattern (the view only for the pages it names). v0.17.4: international view of the course page (adapter page_view: Firecrawl render of the address with the view applied, e.g. La Trobe studentType=int), and a page bound by hand that the adapter confirms keeps the adapter's identity. v0.17.3: term_months (term names in the intakes reading become the university's published months). v0.17.2: page-data list filter [field=value] (Macquarie fees by fee type), a page-data fee counts as the adapter's reading. v0.17.1: {code} in adapter patterns (the course's own code), so pages covering several courses are read per course. v0.17.0: visual adapter builder (adapter_capture, adapter_propose), Firecrawl search results kept in the evidence bucket, adapter fee year. v0.16.2: adapter months read as printed (capitalised). v0.16.1: Apply reads stored pages one after another within the processor-time limit of a call and carries on in the next call. v0.16.0: adapter text patterns (intakes, fee, IELTS, campus, mode, duration, level), "pick" first or last match, extra fields shown for testing, adapter readings marked (intakes_by, fee_by, english_by). v0.15.1: adapters used by the reader and Read pages (page data read from a plain fetch), runs keep under the 120-second call wait. v0.15.0: university adapters (adapter_preview, adapter_apply) on stored pages, no Firecrawl credits. v0.14.1: raw HTML by default (keeps the page title), fc_probe to test read options on chosen pages. v0.14.0 (Decision 253): Firecrawl use cases (fc_run), target universities only, every run call logged; v0.13.5: calendar parser v0.2.2 (section rows)
// v0.10.1 (2 Oct 2026, 22:11 direction): modes openrouter_key, reference_capture (Hipo), site_hint_verify; univ.cc directory hints.
// v0.10.0 (2 Oct 2026): mode ai_match, the map-first link matcher (a pinned model picks a course's page from its stored site map).
// v0.9.5 (2 Oct 2026, Decision 227): English policy and academic calendar documents are read and parsed (policy.ts,
// deterministic) into proposals a Platform Admin approves; modes provider_facts_inspect and provider_facts_parse work on
// the stored copies (no Firecrawl credit).
// v0.9.4 / extractor v0.5.6 (2 Oct 2026, Decision 224): amounts that are not tuition (bursaries, scholarships, loan caps,
// health cover, salaries, deposits, payment limits, other fees) are left out; in a "Session fee / Course fee" table the
// first amount is one session and the second the whole course.
// v0.9.3 / extractor v0.5.5 (2 Oct 2026, Decision 223): a fee's audience follows the page's own domestic or international
// view marker before it ("This content is for domestic students", "Local Student Fee"); course totals ("Total Indicative
// Course Fees", "Estimated total course cost") are totals; re-extraction reads each page in its country's currency.
// v0.9.2 (2 Oct 2026, Decision 220): Canada. find_site finds a Canadian provider's own site by name (search in Canada),
// accepted only on a .ca site whose home page names the provider or prints its DLI number; course pages are read in CAD
// and stored under layer2/CA/. A provider with no code to check is never accepted on an empty pattern.
// v0.9.1 (2 Oct 2026, Decision 217): New Zealand pages are proven by a labelled NZQA number or by the NZQA title with the
// same level ("title_level"), their fees are read in NZD, and they are stored under layer2/NZ/.
// v0.9.0 (Decision 211): mode scholarship_reextract adds eligibility criteria and award scope to stored scholarship pages.
// v0.8.0: mode scholarship_discover (provider scholarship pages from site maps, Firecrawl map/search fallbacks, matching
// held Study Australia-only scholarships, reading unheld pages at Australian universities for admission as new
// unpublished scholarships; Firecrawl only for pages the site refuses, keeping a reserve (Layer 2 setting) for step 1) and mode scholarship_inspect (read only: stored or live page headings and text for hand checks).
// v0.5.2: discovery drops requirement, scholarship and applying pages (pilot: RMIT inherent-requirements pages).
// v0.5.1: PTE/TOEFL only when stated as overall or directly after the test name.
// v0.5.0: English overall only when stated as overall or in a score table; minimum band after the overall; fee basis
// total/annual from the amount's own wording ("(2027 total)", "total indicative fee"); mode reextract re-runs the
// extractor over stored pages read by an older version (no fetch).
// v0.4.0: mode find_site - providers with no website: web search (Firecrawl, 2 credits), accepted only when the
// home page prints the provider's CRICOS provider code; directories and registers skipped.
// v0.3.2: a script-only page read directly while the Firecrawl reserve is reached is "needs_render" (retried after the
// budget resets), never an identity mismatch.
// v0.6.3 (1 Oct 2026, Decision 179 CRUD): an official page entered by hand is trusted as the course's page (identity "manual").
// v0.6.2 (1 Oct 2026, course link recipes): a priority page read directly that does not show the course's CRICOS code
// is rendered once through Firecrawl before it is called an identity mismatch (script-rendered handbooks).
// v0.6.1 (30 Sep 2026, Platform Admin: maximum data for top universities): the Firecrawl fallback also covers ambiguous
// pages of the 100 largest providers (read_next marks them priority); identity is still the CRICOS code on the page.
// v0.3.1: Firecrawl fallback only for bound pages; ambiguous pages are read directly only (low yield).
// v0.3.0: ambiguous course pages are read too and accepted only with the CRICOS course code on the page; month
// names in intakes must be capitalised.
// v0.2.0: discovery reads the site's own XML site maps first (free), from the final address after redirects; Firecrawl
// map runs when the site maps give fewer course pages than 60% of the provider's courses, and a second map focused on
// "course" only when still short (at most 2 credits per provider). Binding runs separately (cron coverage-bind).
const UA = "Mozilla/5.0 (compatible; CourseFinder-Pilot/coverage-0.1; +https://coursefinder-pilot.techm.workers.dev)";
// Map-first link matcher (v0.10.0): structured output; it chooses a page, it never admits a value. v0.85.0: its model is handed out by
// public.svc_coverage_ai_match_next from the route course_matching (it was a constant here); no model is named in the worker any more.
// third-party directories that may be captured as hints (Platform Admin 2 Oct 2026: Hotcourses for Canada and NZ)
const DIRECTORY_HOSTS: Record<string, string> = { hotcourses: "www.hotcoursesabroad.com", univcc: "univ.cc" };
// reference lists read as a whole file (Platform Admin 2 Oct 2026, 22:11); MIT-licensed
const REFERENCE_FILES: Record<string, string> = { hipo: "https://raw.githubusercontent.com/Hipo/university-domains-list/master/world_universities_and_domains.json" };
// AI page-identity candidates (qualification only): the models of the route page_identity (v0.85.0; the list was a constant here and was not used)
// identity rule version used by mode reidentify (extract.ts identity(); v0.5.7 = national code before the title)
const IDENTITY_RULE = "identity-v0.6.0"; // 24 Oct 2026: CRICOS proofs are Australian only; NZ and CA codes carry their own labels
const AI_MATCH_PROFILE ="openrouter-intake-l3c-qwen3-30b-a3b-2507-v1"; // credential source only; its contract is not used here
export const AI_MATCH_SYSTEM = `You match a course from a government register to its own page on the education provider's website. You get the course (title, level, code) and a numbered list of candidate pages from the provider's site (address, and page title when known).
Pick the one page that is this course's own page: the page for this exact qualification at this level.
Do not pick: a list, search or faculty page; a subject-area page; a page for a different level, major, specialisation, campus-only variant or double degree; a page about entry requirements, fees, careers, news, events, research or applying.
A closely named qualification is a different course (for example "Bachelor of X (Honours)" when the course is "Bachelor of X", or "Bachelor of X/Bachelor of Y" when the course is "Bachelor of X"). A register title may add "(International)" or a short code in brackets; the provider's page may leave these out.
If no candidate is clearly this course's own page, answer 0. Answer JSON only: reason first, then choice (the candidate number, or 0).`;
export function aiMatchRequest(it: { title: string; code: string | null; level: string | null; provider: string; candidates: { url: string; title: string }[]; model?: string }, maxTokens = 300) {  // v0.54.0 (W32): the answer limit is a setting (answer.ts); the default is the value fixed here before
  const list = it.candidates.map((x, i) => `${i + 1}. ${x.url}${x.title ? ` | ${x.title}` : ""}`).join("\n");
  return {
    model: String(it.model || ""), temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "page_choice", strict: true, schema: { type: "object", additionalProperties: false, required: ["reason", "choice"],
      properties: { reason: { type: "string" }, choice: { type: "integer", minimum: 0, maximum: it.candidates.length } } } } },
    messages: [{ role: "system", content: AI_MATCH_SYSTEM },
      { role: "user", content: `Course: ${it.title}\nLevel: ${it.level || "not given"}\nCode: ${it.code || "none"}\nProvider: ${it.provider}\nCandidates:\n${list}` }],
  };
}
// v0.20.0 (bugs 11/10-6): the scholarship page answer. Every field is required (strict); a fact the page does not state is "not_stated".
const SCH_AI_LEVELS = ["undergraduate", "postgraduate_coursework", "postgraduate_research", "vet", "english", "pathway"];
const numOrNull = { type: ["number", "null"] }, strOrNull = { type: ["string", "null"] };
export function scholarshipAiRequest(model: string, prompt: string, p: { provider: string; url: string; title: string; h1: string; text: string }, maxTokens = 3000) {  // v0.54.0 (W32): the answer limit is a setting (answer.ts); the default is the value fixed here before
  return {
    model, temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "scholarship_page", strict: true, schema: { type: "object", additionalProperties: false,
      required: ["is_scholarship", "single_scholarship", "not_scholarship_reason", "name", "name_quote", "audience", "audience_quote", "offered", "offered_quote", "value", "levels", "levels_quote", "courses", "open_date", "close_date", "dates_quote"],
      properties: {
        is_scholarship: { type: "boolean" }, single_scholarship: { type: "boolean" }, not_scholarship_reason: strOrNull,
        name: strOrNull, name_quote: { type: "string" },
        audience: { type: "string", enum: ["international", "both", "domestic", "not_stated"] }, audience_quote: { type: "string" },
        offered: { type: "string", enum: ["yes", "no", "not_stated"] }, offered_quote: { type: "string" },
        value: { type: "object", additionalProperties: false, required: ["kind", "percentage", "amount", "currency", "tiers", "quote"], properties: {
          kind: { type: "string", enum: ["percentage", "fixed_amount", "tiers", "full_tuition", "non_monetary", "not_stated"] }, percentage: numOrNull, amount: numOrNull, currency: strOrNull,
          tiers: { type: "array", items: { type: "object", additionalProperties: false, required: ["label", "percentage", "amount"], properties: { label: { type: "string" }, percentage: numOrNull, amount: numOrNull } } },
          quote: { type: "string" } } },
        levels: { type: "array", items: { type: "string", enum: SCH_AI_LEVELS } }, levels_quote: { type: "string" },
        courses: { type: "array", items: { type: "string" } },
        open_date: strOrNull, close_date: strOrNull, dates_quote: { type: "string" } } } } },
    messages: [{ role: "system", content: prompt },
      { role: "user", content: `University: ${p.provider || "unknown"}\nPage address: ${p.url}\nPage title: ${p.title}\nMain heading: ${p.h1}\n\nPage text:\n${p.text}` }],
  };
}
const INTL_WORDS = /\b(international|overseas|offshore|student visa|subclass 500|non[- ]?residents?|foreign|non[- ]?domestic|not (?:be )?an? domestic student)\b/i;
const DOM_WORDS = /\b(domestic|citizens?|citizenship|permanent residen\w*|aboriginal|torres strait|humanitarian)\b/i;
// v0.20.3: countries and regions whose naming in an audience quote proves the scholarship is for students from outside the university's
// country. The university's own country, and Australia and New Zealand for each other (trans-Tasman students count as domestic in places), do not.
const COUNTRY_NAMES: Record<string, string> = { AF: "Afghanistan", AL: "Albania", DZ: "Algeria", AR: "Argentina", AM: "Armenia", AU: "Australia", AT: "Austria", AZ: "Azerbaijan",
  BH: "Bahrain", BD: "Bangladesh", BY: "Belarus", BE: "Belgium", BT: "Bhutan", BO: "Bolivia", BA: "Bosnia", BW: "Botswana", BR: "Brazil", BN: "Brunei", BG: "Bulgaria",
  KH: "Cambodia", CM: "Cameroon", CA: "Canada", CL: "Chile", CN: "China", CO: "Colombia", CK: "Cook Islands", CR: "Costa Rica", HR: "Croatia", CU: "Cuba", CY: "Cyprus",
  CZ: "Czech", DK: "Denmark", DO: "Dominican Republic", EC: "Ecuador", EG: "Egypt", SV: "El Salvador", EE: "Estonia", ET: "Ethiopia", FJ: "Fiji", FI: "Finland",
  FR: "France", DE: "Germany", GH: "Ghana", GR: "Greece", GT: "Guatemala", HK: "Hong Kong", HU: "Hungary", IS: "Iceland", IN: "India", ID: "Indonesia", IR: "Iran",
  IQ: "Iraq", IE: "Ireland", IL: "Israel", IT: "Italy", JM: "Jamaica", JP: "Japan", JO: "Jordan", KZ: "Kazakhstan", KE: "Kenya", KI: "Kiribati", KR: "Korea", KW: "Kuwait",
  KG: "Kyrgyz", LA: "Laos", LV: "Latvia", LB: "Lebanon", LT: "Lithuania", LU: "Luxembourg", MO: "Macau", MY: "Malaysia", MV: "Maldives", MT: "Malta", MH: "Marshall Islands",
  MU: "Mauritius", MX: "Mexico", FM: "Micronesia", MN: "Mongolia", ME: "Montenegro", MA: "Morocco", MZ: "Mozambique", MM: "Myanmar", NA: "Namibia", NR: "Nauru", NP: "Nepal",
  NL: "Netherlands", NZ: "New Zealand", NG: "Nigeria", NU: "Niue", NO: "Norway", OM: "Oman", PK: "Pakistan", PW: "Palau", PS: "Palestine", PA: "Panama", PG: "Papua New Guinea",
  PY: "Paraguay", PE: "Peru", PH: "Philippines", PL: "Poland", PT: "Portugal", QA: "Qatar", RO: "Romania", RU: "Russia", RW: "Rwanda", WS: "Samoa", SA: "Saudi Arabia",
  SN: "Senegal", RS: "Serbia", SG: "Singapore", SK: "Slovakia", SI: "Slovenia", SB: "Solomon Islands", ZA: "South Africa", ES: "Spain", LK: "Sri Lanka", SD: "Sudan",
  SE: "Sweden", CH: "Switzerland", SY: "Syria", TW: "Taiwan", TJ: "Tajikistan", TZ: "Tanzania", TH: "Thailand", TL: "Timor-Leste", TO: "Tonga", TT: "Trinidad",
  TN: "Tunisia", TR: "Turkey", TV: "Tuvalu", UG: "Uganda", UA: "Ukraine", AE: "United Arab Emirates", GB: "United Kingdom", US: "United States", UY: "Uruguay", UZ: "Uzbekistan",
  VU: "Vanuatu", VE: "Venezuela", VN: "Vietnam", YE: "Yemen", ZM: "Zambia", ZW: "Zimbabwe" };
const COUNTRY_ALIASES: Record<string, string[]> = { CN: ["People's Republic of China", "PRC", "Chinese"], VN: ["Viet Nam", "Vietnamese"], IN: ["Indian national", "Indian citizen"],
  ID: ["Indonesian"], PG: ["PNG"], KR: ["Korean"], JP: ["Japanese"], MY: ["Malaysian"], TH: ["Thai"], PH: ["Filipino"], NP: ["Nepalese", "Nepali"], LK: ["Sri Lankan"],
  BD: ["Bangladeshi"], PK: ["Pakistani"], TL: ["East Timor"], GB: ["UK", "British"], US: ["USA", "American"], CA: ["Canadian"], AU: ["Australian"], NZ: ["New Zealander", "Aotearoa"] };
// v0.77.0: each country's name and recorded aliases, for the version 3 nationality check (sch-extract.ts checkScholarshipDetail)
const NAT_NAMES: Record<string, string[]> = Object.fromEntries(Object.entries(COUNTRY_NAMES).map(([k, n]) => [k, [n, ...(COUNTRY_ALIASES[k] || [])]]));
const REGIONS = ["Africa", "African", "Latin America", "South America", "Southeast Asia", "South-East Asia", "South Asia", "Middle East", "Pacific Island", "Pacific nation", "ASEAN", "Europe", "European Union", "Caribbean"];
const esc = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
export function foreignNamed(quote: string, home: string | null) {
  const h = String(home || "").toUpperCase(), excluded = new Set([h, ...(h === "AU" ? ["NZ"] : h === "NZ" ? ["AU"] : [])]);
  if (!h) return false;
  const words = [...Object.entries(COUNTRY_NAMES).filter(([k]) => !excluded.has(k)).flatMap(([k, n]) => [n, ...(COUNTRY_ALIASES[k] || [])]), ...REGIONS];
  return new RegExp(`(^|[^A-Za-z])(${words.map(esc).join("|")})([^A-Za-z]|$)`).test(String(quote || "").replace(/[\u2018\u2019]/g, "'"));
}
// Each quote must be on the page (letters and digits compared, case and spacing ignored; "..." may join parts of one quote)
const flat = (s: string) => String(s || "").toLowerCase().normalize("NFKD").replace(/[^a-z0-9]+/g, "");
// v0.43.0 (23 Oct 2026, Platform Admin 19:27 "Lets test openrouter where it goes bottleneck"): every OpenRouter call of a worker call is
// counted (answered, rate-limited 429, server error, other error, timed out) with its time, and the summary is returned with the call,
// so the database and the Task manager show where OpenRouter starts to push back.
// v0.22.1: stored copies are gzip (course pages) or plain (contact page snapshots); read either. v0.79.0: one loader for enrich_ai and aer_v2_shadow
// deno-lint-ignore no-explicit-any
async function readEvidenceCopy(c: any, path: string): Promise<string> {
  const { data, error } = await c.storage.from("evidence").download(path); if (error || !data) throw Error(error?.message || "missing");
  const buf = new Uint8Array(await data.arrayBuffer());
  if (buf[0] === 0x1f && buf[1] === 0x8b) return await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
  return new TextDecoder().decode(buf);
}
function orStats() {
  const ms: number[] = []; const c = { calls: 0, ok: 0, http429: 0, http5xx: 0, other: 0, timeout: 0 };
  return {
    async fetch(url: string, init: RequestInit): Promise<Response> {
      const t = Date.now(); c.calls++;
      try {
        const r = await fetch(url, init); ms.push(Date.now() - t);
        if (r.ok) c.ok++; else if (r.status === 429) c.http429++; else if (r.status >= 500) c.http5xx++; else c.other++;
        return r;
      } catch (e) { ms.push(Date.now() - t); if (e instanceof Error && /timed? ?out|abort/i.test(e.name + e.message)) c.timeout++; else c.other++; throw e }
    },
    summary() { const s = [...ms].sort((a, b) => a - b); const q = (p: number) => s.length ? s[Math.min(s.length - 1, Math.floor(p * s.length))] : 0; return { ...c, ms_p50: q(0.5), ms_p95: q(0.95), ms_max: s.length ? s[s.length - 1] : 0 } },
  };
}
// v0.33.0: the narrow re-check of a held scholarship page (who may apply, value), with the exact sentence for each
export function scholarshipRecheckRequest(model: string, p: { name: string; provider: string; url: string; title: string; h1: string; text: string }, maxTokens = 800) {  // v0.54.0 (W32): the answer limit is a setting (answer.ts); the default is the value fixed here before
  return {
    model, temperature: 0, max_tokens: maxTokens, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "scholarship_recheck", strict: true, schema: { type: "object", additionalProperties: false,
      required: ["audience", "audience_quote", "value_stated", "value_quote"],
      properties: { audience: { type: "string", enum: ["international", "both", "domestic", "not_stated"] }, audience_quote: { type: "string" },
                    value_stated: { type: "boolean" }, value_quote: { type: "string" } } } } },
    messages: [
      { role: "system", content: "You check one scholarship page for a course search site for international students. Answer only from the page text. Copy sentences exactly as they appear on the page; do not shorten or rephrase them." },
      { role: "user", content: `Scholarship: ${p.name || "(as named on the page)"}\nUniversity: ${p.provider}\nPage: ${p.url}\nTitle: ${p.title}\nHeading: ${p.h1}\n\n1. Who may apply? "international" if the page says international students (or overseas, student visa holders) may apply; "domestic" if it is only for citizens, permanent residents, domestic or humanitarian visa holders; "both" if it says both; "not_stated" if the page does not say. Copy the one sentence that says it into audience_quote ("" if not stated).\n2. Does the page state what the scholarship is worth (an amount, a percentage or full tuition)? Copy that sentence into value_quote ("" if not stated).\n\nPage text:\n${p.text}` },
    ],
  };
}
export function judgeScholarshipRecheck(a: any, page: string) {
  const P = flat(page);
  const on = (q: string) => { const parts = String(q || "").split(/\s*(?:\.\.\.|…)\s*/).map(flat).filter((x) => x.length >= 6); return parts.length > 0 && parts.every((x) => P.includes(x)) };
  const aq = String(a?.audience_quote || ""), vq = String(a?.value_quote || "");
  const audienceProven = a?.audience !== "not_stated" && on(aq) && (["international", "both"].includes(a?.audience) ? INTL_WORDS.test(aq) : a?.audience === "domestic" ? DOM_WORDS.test(aq) : false);
  const valueProven = !!a?.value_stated && on(vq) && /\d|full tuition|tuition fees? (?:waiver|in full)|100 ?%/i.test(vq);
  const intl = audienceProven && ["international", "both"].includes(a?.audience);
  // v0.33.1: a sentence that is on the page but does not name international students (asylum seeker, housing, school-leaver awards) is
  // read as "international students not mentioned", the same as no sentence at all
  const notNamed = a?.audience === "not_stated" || (["international", "both"].includes(a?.audience) && on(aq) && !INTL_WORDS.test(aq));
  const recommendation = audienceProven && a?.audience === "domestic" ? "not_for_international"
    : intl && valueProven ? "international_check_and_publish"
    : intl ? "international_value_unclear"
    : notNamed ? "audience_not_stated" : "unsettled";
  const why = recommendation === "not_for_international" ? "The page says it is for domestic students only; do not publish."
    : recommendation === "international_check_and_publish" ? "The page names international students and states the value; check and publish."
    : recommendation === "international_value_unclear" ? "The page names international students but the value is not stated clearly; check the value before publishing."
    : recommendation === "audience_not_stated" ? "The page does not say international students may apply; do not publish unless you know otherwise."
    : "The re-check could not prove who it is for; decide from the page.";
  return { recommendation, why, audience: a?.audience ?? null, audience_quote: aq.slice(0, 600), audience_proven: audienceProven, value_quote: vq.slice(0, 600), value_proven: valueProven };
}
export function checkScholarshipAnswer(a: any, page: string, home: string | null = null) {
  const P = flat(page);
  const on = (q: string) => { const parts = String(q || "").split(/\s*(?:\.\.\.|…)\s*/).map(flat).filter((x) => x.length >= 6); return parts.length > 0 && parts.every((x) => P.includes(x)) };
  // only the numbers the value's kind uses are checked (a model may also fill fields the kind does not use; they are not applied):
  // a percentage or an amount must be in the value quote; each tier's number must be somewhere on the page
  const isNum = (x: any) => typeof x === "number" && isFinite(x), digits = (n: number) => [String(n).replace(/\.0+$/, ""), String(Math.round(n))];
  const inText = (n: number, t: string) => digits(n).some((d) => t.includes(d));
  const v = a?.value || {}, vq = flat(v.quote);
  const valueOk = on(v.quote) && (v.kind === "percentage" ? isNum(v.percentage) && inText(v.percentage, vq)
    : v.kind === "fixed_amount" ? isNum(v.amount) && inText(v.amount, vq)
    : v.kind === "tiers" ? ((v.tiers || []) as any[]).length > 0 && ((v.tiers || []) as any[]).every((t) => [t?.percentage, t?.amount].some(isNum) && [t?.percentage, t?.amount].filter(isNum).every((n: number) => inText(n, P)))
    : false);
  return {
    name: !!a?.name && (P.includes(flat(a.name)) || on(a.name_quote)),
    // v0.20.2 (11 Oct 2026): the quote must itself say who it is for (a quote that is only on the page proved nothing: "open to both
    // full-time and part-time students" was read as international and domestic); international or both needs international wording,
    // domestic needs domestic wording
    audience: a?.audience !== "not_stated" && on(a?.audience_quote) && (["international", "both"].includes(a?.audience) ? (INTL_WORDS.test(String(a?.audience_quote || "")) || foreignNamed(a?.audience_quote, home))
      : a?.audience === "domestic" ? DOM_WORDS.test(String(a?.audience_quote || "")) : false),
    offered: a?.offered !== "not_stated" && on(a?.offered_quote),
    value: v.kind === "full_tuition" ? on(v.quote) : valueOk,
    levels: (a?.levels || []).length > 0 && on(a?.levels_quote),
    courses_found: ((a?.courses || []) as string[]).filter((x) => flat(x).length >= 6 && P.includes(flat(x))).slice(0, 80),
    courses_not_found: ((a?.courses || []) as string[]).filter((x) => !(flat(x).length >= 6 && P.includes(flat(x)))).slice(0, 40),
    dates: !!(a?.open_date || a?.close_date) && on(a?.dates_quote),
  };
}
// v0.21.0 (12 Oct 2026, fix 3): a university's central page (English language policy or academic calendar) read with a pinned model when
// the rule parser found nothing. The answer has the rule parser's shape so the same approval applies; nothing is applied here.
const CENTRAL_AI_PROMPT: Record<string, string> = {
  english_policy: "You read one university web page about English language requirements for admission. Report the default IELTS Academic requirement for international applicants to undergraduate coursework, to postgraduate coursework and to higher degree by research (research masters and doctorates) courses, as stated on the page. Give the overall score and, if stated, the minimum score in each band. For each, copy one exact sentence or table row from the page that contains the scores (quote). Use null for a level the page does not state, and never infer a score from another test or another page. If the page gives scores only by course or faculty, set by_course to true and leave the levels null.",
  intake_calendar: "You read one university web page with academic dates. Report the month each study period (Semester 1, Semester 2, Trimester 1, Term 3 and similar) starts, with the year if stated, and copy the exact row or sentence from the page that gives that start date (quote). Leave out exams, census dates, holidays and end dates. Return an empty list if the page gives no start dates.",
};
export function centralAiRequest(model: string, kind: string, p: { provider: string; url: string; text: string }, maxTokens = 1500) {  // v0.54.0 (W32): the answer limit is a setting (answer.ts); the default is the value fixed here before
  const lvl = { type: ["object", "null"], additionalProperties: false, required: ["ielts_overall", "ielts_min_band", "quote"],
    properties: { ielts_overall: { type: ["number", "null"] }, ielts_min_band: { type: ["number", "null"] }, quote: { type: "string" } } };
  const schema = kind === "english_policy"
    ? { type: "object", additionalProperties: false, required: ["undergraduate", "postgraduate", "research", "by_course"], properties: { undergraduate: lvl, postgraduate: lvl, research: lvl, by_course: { type: "boolean" } } }
    : { type: "object", additionalProperties: false, required: ["periods"], properties: { periods: { type: "array", items: { type: "object", additionalProperties: false, required: ["period", "month", "year", "quote"],
        properties: { period: { type: "string" }, month: { type: "integer" }, year: { type: ["integer", "null"] }, quote: { type: "string" } } } } } };
  return { model, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: kind, strict: true, schema } },
    messages: [{ role: "system", content: CENTRAL_AI_PROMPT[kind] }, { role: "user", content: `University: ${p.provider}\nPage address: ${p.url}\n\nPage text:\n${p.text}` }] };
}
const MONTHS_RE = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"];
// the answer, in the rule parser's shape, keeping only what its quote proves
export function centralAiParsed(kind: string, a: any, page: string, parser: string) {
  const P = flat(page), on = (q: string) => flat(q).length >= 6 && P.includes(flat(q));
  const has = (n: number, q: string) => [String(n), String(n).replace(/\.0$/, ""), n.toFixed(1)].some((d) => String(q || "").includes(d));
  if (kind === "english_policy") {
    const out: Record<string, unknown[]> = {}, dropped: string[] = [];
    for (const lv of ["undergraduate", "postgraduate", "research"]) {
      const x = a?.[lv]; if (!x || typeof x.ielts_overall !== "number") continue;
      if (!on(x.quote) || !has(x.ielts_overall, x.quote)) { dropped.push(lv); continue }
      const band = typeof x.ielts_min_band === "number" && has(x.ielts_min_band, x.quote) ? x.ielts_min_band : null;
      out[lv] = [{ test_code: "IELTS", overall_score: x.ielts_overall, component_scores: band == null ? {} : { reading: band, writing: band, speaking: band, listening: band }, quote: String(x.quote).slice(0, 400) }];
    }
    const style = Object.keys(out).length ? "level_default" : a?.by_course ? "course_specific" : "none";
    return { parser, style, defaults: out, exceptions: [], named: [], caveats: ["read_by_ai", ...(dropped.length ? ["unproven_" + dropped.join("_")] : [])], signals: a?.by_course ? ["course_specific"] : [], conflicts: [] };
  }
  const found: Record<string, { months: Set<number>; years: Set<number>; quotes: string[] }> = {};
  for (const x of (a?.periods || []) as any[]) {
    const m = Number(x?.month); if (!(m >= 1 && m <= 12) || !on(x?.quote) || !String(x.quote).toLowerCase().includes(MONTHS_RE[m - 1])) continue;
    const key = String(x.period || "").toLowerCase().replace(/\s+/g, " ").trim().slice(0, 40); if (!key) continue;
    const f = found[key] ||= { months: new Set(), years: new Set(), quotes: [] };
    f.months.add(m); if (Number.isInteger(x.year)) f.years.add(x.year); if (f.quotes.length < 3) f.quotes.push(String(x.quote).slice(0, 300));
  }
  return { parser, periods: Object.entries(found).map(([period, f]) => ({ period, months: [...f.months].sort((p, q) => p - q), years: [...f.years].sort(), quotes: f.quotes })) };
}
const BUDGET_MS = 110_000;
// v0.78.0: a version 3 scholarship extraction answers a long structured object; 16 of 52 reads after v0.77.1 were cut by the 60 s abort while the
// answer was arriving (read as "no choices"). fixed: API time-out of one version 3 call; such a call starts only in the first 20 s of a worker call
const SCH_V3_TIMEOUT_MS = 90_000;
const j = (b: unknown, s = 200) => new Response(JSON.stringify(b), { status: s, headers: { "content-type": "application/json" } });

// v0.32.0: the page text compared between reads (spacing left out; htmlToText already leaves out scripts and styles)
const normText = (t: string) => String(t || "").replace(/\s+/g, " ").trim();
async function sha256(b: Uint8Array) { return [...new Uint8Array(await crypto.subtle.digest("SHA-256", b))].map((x) => x.toString(16).padStart(2, "0")).join("") }
async function gzip(s: string | Uint8Array) { const cs = new CompressionStream("gzip"); const w = cs.writable.getWriter(); w.write(typeof s === "string" ? new TextEncoder().encode(s) : s); w.close(); return new Uint8Array(await new Response(cs.readable).arrayBuffer()) }
// v0.40.8: the newest year of the same page that the page links to (a parameter named for the year with a later 4-digit year,
// every other parameter of the page's own address unchanged); null when there is none
export function newestVersionUrl(html: string, url: string): string | null {
  let base: URL; try { base = new URL(url) } catch { return null }
  const yearKey = (k: string) => /year/i.test(k), loose = (k: string) => /(year|term|clear|session|semester)/i.test(k);
  const ownYear = [...base.searchParams].filter(([k, v]) => yearKey(k) && /^20\d\d$/.test(v)).map(([, v]) => Number(v))[0] ?? new Date().getUTCFullYear();
  let best: { url: string; year: number } | null = null;
  // v0.40.9: the "newer version" link may sit inside escaped markup (&lt;a href=&quot;...&quot;&gt;) or a page item, so entities and
  // escaped slashes are undone first and every same-path address with a query is looked at, not only href attributes
  let doc = html;
  for (let i = 0; i < 2; i++) doc = doc.replace(/&quot;|&#34;|&#x22;/gi, '"').replace(/&#x2F;|&#47;/gi, "/").replace(/&amp;/gi, "&").replace(/\\\//g, "/").replace(/\\u0026/gi, "&");
  for (const m of doc.matchAll(/(?:https?:\/\/[^\s"'<>\\]+)?\/[^\s"'<>\\?]*\?[^\s"'<>\\#]+/gi)) {
    let u: URL; try { u = new URL(m[0], base) } catch { continue }
    if (u.origin !== base.origin || u.pathname !== base.pathname) continue;
    const yr = [...u.searchParams].filter(([k, v]) => yearKey(k) && /^20\d\d$/.test(v)).map(([, v]) => Number(v))[0];
    if (!yr || yr <= ownYear) continue;
    if ([...base.searchParams].some(([k, v]) => !loose(k) && u.searchParams.get(k) !== v)) continue;
    if (!best || yr > best.year) best = { url: u.toString(), year: yr };
  }
  return best?.url || null;
}
async function pool<T>(items: T[], n: number, f: (x: T) => Promise<void>) { let i = 0; await Promise.all(Array.from({ length: Math.min(n, items.length) }, async () => { while (i < items.length) await f(items[i++]) })) }


async function fetchText(url: string, ms = 15000) {
  const r = await fetch(url, { headers: { "user-agent": UA, accept: "application/xml,text/xml,text/plain,*/*" }, redirect: "follow", signal: AbortSignal.timeout(ms) });
  if (!r.ok) return "";
  if (/\.gz($|\?)/i.test(url) || /gzip/i.test(r.headers.get("content-type") || "")) {
    try { return await new Response(r.body!.pipeThrough(new DecompressionStream("gzip"))).text() } catch { return "" }
  }
  return await r.text();
}
const coursePri = (u: string) => /course|program|study|handbook|degree|qualification/i.test(u) ? 0 : /page|post/i.test(u) ? 1 : 2;
const scholarshipPri = (u: string) => /scholar|award|bursar|grant/i.test(u) ? 0 : /study|international|page|content/i.test(u) ? 1 : 2;
async function siteMapUrls(origin: string, deadline: number, pri: (u: string) => number = coursePri) {
  const robots = await fetchText(origin + "/robots.txt", 8000).catch(() => "");
  const queue = [...robots.matchAll(/^\s*sitemap:\s*(\S+)/gim)].map((m) => m[1]);
  if (!queue.length) queue.push(origin + "/sitemap.xml", origin + "/sitemap_index.xml");
  const seen = new Set<string>(), urls = new Set<string>();
  let files = 0;
  while (queue.length && files < 60 && urls.size < 60000 && Date.now() < deadline) {
    const sm = queue.shift()!; if (seen.has(sm)) continue; seen.add(sm); files++;
    const xml = await fetchText(sm).catch(() => "");
    const locs = [...xml.matchAll(/<loc>\s*(?:<!\[CDATA\[)?\s*([^<\]\s]+)/gi)].map((m) => m[1].replace(/&amp;/g, "&"));
    if (/<sitemapindex/i.test(xml)) {
      queue.push(...locs.sort((a, b) => pri(a) - pri(b)));
      queue.sort((a, b) => pri(a) - pri(b));
    } else for (const l of locs) urls.add(l);
  }
  return { urls: [...urls], files };
}

// 1 Oct 2026 (Decision 205): fee schedules. A fee row is kept only when the same row carries exactly one course code
// in CRICOS form (6 digits and a check character) and an amount; the basis comes from the column heading (or the line's
// own wording outside tables). Nothing is inferred across rows. The document year is the fee year most often named.
const FEE_CODE = /\b(\d{6}[0-9A-Z])\b/g;
const FEE_HEAD = /fee|tuition|cost|price|aud|\$/i;
const FEE_MONEY = /\$\s?(\d{1,3}(?:,\d{3})+|\d{4,6})(?:\.\d{2})?/g;
function feeBasis(label: string) {
  const l = label.toLowerCase();
  if (/total|whole|full course|entire|course fee \(total\)/.test(l)) return "total_indicative";
  if (/semester/.test(l)) return "per_semester";
  if (/trimester/.test(l)) return "per_trimester";
  if (/annual|per year|yearly|p\.a\.|per annum|eftsl|full[- ]time|1st year|first year|\b20\d\d\b/.test(l)) return "annual";
  return "";
}
function feeDocYear(text: string) {
  const n = new Map<number, number>();
  for (const m of text.matchAll(/\b(202[5-9])\b/g)) n.set(+m[1], (n.get(+m[1]) || 0) + 1);
  return [...n.entries()].sort((a, b) => b[1] - a[1] || b[0] - a[0])[0]?.[0] ?? null;
}
// Fee schedule documents linked from a fee page (usually PDFs): links on the provider's own site whose text or address
// mentions fees or tuition. Newest year first, at most 4.
export function feeLinks(md: string, pageUrl: string) {
  let base: URL; try { base = new URL(pageUrl) } catch { return [] }
  const root = base.hostname.replace(/^www\./, "").split(".").slice(-3).join(".");
  const out = new Map<string, number>();
  for (const m of md.matchAll(/\[([^\]]{0,200})\]\((\S+?)(?:\s+"[^"]*")?\)/g)) {
    let u: URL; try { u = new URL(m[2], base) } catch { continue }
    if (!/^https?:$/.test(u.protocol) || !(u.hostname === root || u.hostname.endsWith("." + root))) continue;
    const text = `${m[1]} ${decodeURIComponent(u.pathname)}`;
    if (!/\.pdf$/i.test(u.pathname) || !/fee|tuition/i.test(text) || /domestic|csp|commonwealth|refund|policy|procedure|form/i.test(text)) continue;
    u.hash = "";
    const y = Math.max(0, ...[...text.matchAll(/\b(202[5-9])\b/g)].map((x) => +x[1]));
    out.set(u.toString(), Math.max(out.get(u.toString()) ?? 0, y));
  }
  return [...out.entries()].sort((a, b) => b[1] - a[1]).slice(0, 4).map(([url, year]) => ({ url, year: year || null }));
}
export function parseFeeRows(md: string) {
  const year = feeDocYear(md);
  const out: { course_code: string; amount: number; basis: string; fee_year: number | null; column_label: string; row_text: string }[] = [];
  // lastFee: the last heading row that named a fee basis. A schedule split across pages (PDFs) continues in tables whose
  // first row is a course row, not a heading; such a table takes lastFee when it has the same number of columns.
  let header: string[] = [], lastFee: string[] = [], tableRows = 0;
  for (const raw of md.split("\n")) {
    const line = raw.trim();
    if (!line) { header = []; continue }
    const codes = [...new Set([...line.matchAll(FEE_CODE)].map((m) => m[1]))];
    if (line.startsWith("|")) {
      const cells = line.split("|").slice(1, -1).map((x) => x.trim());
      if (cells.every((x) => /^:?-{2,}:?$/.test(x) || x === "")) continue;
      const money = cells.map((x) => [...x.matchAll(FEE_MONEY)].map((m) => Number(m[1].replace(/,/g, ""))));
      if (!codes.length && money.every((m) => !m.length)) {
        // a section row inside a table ("| FACULTY OF HEALTH |  |  |") does not replace a heading row that named fees
        if (!header.some((x) => FEE_HEAD.test(x))) header = cells;
        if (cells.some((x) => feeBasis(x))) lastFee = cells;
        continue;
      }
      tableRows++;
      if (codes.length !== 1) continue;
      const head = header.some((x) => FEE_HEAD.test(x)) ? header : (lastFee.length === cells.length ? lastFee : []);
      money.forEach((ms, i) => {
        if (ms.length !== 1) return;
        const label = head[i] || "";
        const basis = feeBasis(label);
        if (!basis) return;
        out.push({ course_code: codes[0], amount: ms[0], basis, fee_year: (label.match(/\b(202[5-9])\b/) ? +label.match(/\b(202[5-9])\b/)![1] : year), column_label: label.slice(0, 120), row_text: line.slice(0, 500) });
      });
    } else if (codes.length === 1) {
      const ms = [...line.matchAll(FEE_MONEY)].map((m) => Number(m[1].replace(/,/g, "")));
      const basis = feeBasis(line);
      if (ms.length === 1 && basis) out.push({ course_code: codes[0], amount: ms[0], basis, fee_year: year, column_label: "", row_text: line.slice(0, 500) });
    }
  }
  const seen = new Set<string>();
  const rows = out.filter((r) => r.amount >= 1000 && r.amount <= 200000 && !seen.has(`${r.course_code}|${r.amount}|${r.basis}`) && (seen.add(`${r.course_code}|${r.amount}|${r.basis}`), true));
  return { rows, summary: { fee_year: year, table_rows: tableRows, codes_seen: new Set([...md.matchAll(FEE_CODE)].map((m) => m[1])).size, rows: rows.length } };
}

// v0.46.0 (R1 Q3, 24 Oct 2026): every call ends with one ledger row (public.svc_worker_report_v1): the mode, the HTTP status, the
// call time and the answer body, from which the database counts items, successes and failures and keeps the tally. A call with no mode
// (a refused nonce, a non-POST) is not a worker call and writes nothing. The report never changes the answer: it is sent after it is built
// and any failure to write it is ignored.
Deno.serve(async (req) => {
  const tStart = Date.now();
  const modeOf = await req.clone().json().then((b) => String(b?.mode || "")).catch(() => "");
  const res = await handle(req);
  try {  // round 4: every model call attempt of this call is kept (pipeline.ai_invocations); the trace never fails a call
    const attempts = takeAiTrace();
    if (attempts.length) {
      const ct = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
      await ct.rpc("svc_ai_model_answered_v1", { p_source: null, p_source_id: null, p_model: null, p_attempts: attempts, p_worker: WORKER });
    }
  } catch { /* the trace never fails a call */ }
  if (modeOf) {
    try {
      const body = await res.clone().json().catch(() => null);
      if (body && typeof body === "object") {
        const cr = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
        await cr.rpc("svc_worker_report_v1", { p_mode: modeOf, p_status: res.status, p_ms: Date.now() - tStart, p_body: body, p_worker: WORKER });
      }
    } catch { /* the ledger never fails a call */ }
  }
  return res;
});

async function handle(req: Request): Promise<Response> {
  const t0 = Date.now();
  if (req.method !== "POST") return j({ error: "POST required", workerVersion: VERSION }, 405);
  const c = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, { auth: { persistSession: false } });
  const rpc = async (fn: string, args: Record<string, unknown>) => { const { data, error } = await c.rpc(fn, args); if (error) throw Error(`${fn}: ${error.message}`); return data };
  try {
    const nonce = (req.headers.get("x-cf-run-nonce") || "").trim();
    const { data: ok } = nonce ? await c.rpc("svc_pilot_consume_nonce", { p_function: "coverage-sweep", p_nonce: nonce }) : { data: false };
    if (!ok) return j({ error: "valid one-time Pilot nonce required", workerVersion: VERSION }, 401);
    const body = await req.json().catch(() => ({}));
    const mode = String(body.mode || "");
    const fc = await rpc("svc_coverage_firecrawl", {});
    let fcRemaining = fc?.budget_status?.allowed === false ? 0 : Math.max(0, Number(fc?.budget_status?.remaining_units ?? 0) - Number(fc?.budget_status?.stop_at_remaining_units ?? 0));
    const fcHeaders = { authorization: `Bearer ${fc?.secret}`, "content-type": "application/json" };
    // v0.21.7 (CF-247 v2.15.269, Platform Admin 13 Oct 2026: "Bring all controls to UI ... in future it's not getting hard coded"): the proxy, site
    // map sizes and search result counts are settings (Toolsets & limits › Firecrawl), read once per call. The second argument is only used if the
    // setting cannot be read.
    const ws: Record<string, unknown> = (await rpc("svc_worker_settings_v1", {}).catch(() => ({}))) || {};
    const wsNum = (k: string, d: number) => { const n = Number(ws[k]); return Number.isFinite(n) && n > 0 ? n : d; };
    // v0.92.0 (CF-247 Lean AI Input Phase 1b step 2, G2): the section selector's sizes are settings (Settings › Pipeline settings, Enrich fields),
    // the same for the offline recall check and the shadow beside live reads; SECTION_DEFAULTS is used only if a setting cannot be read.
    const SEC_OPT = { section_max_chars: wsNum("reading.section_max_chars", SECTION_DEFAULTS.section_max_chars),
      neighbour_max_chars: wsNum("reading.section_neighbour_chars", SECTION_DEFAULTS.neighbour_max_chars), intro_blocks: wsNum("reading.section_intro_blocks", SECTION_DEFAULTS.intro_blocks) };
    // an on/off setting: 0 is off (wsNum treats 0 as unset, so switches are read directly)
    const wsOn = (k: string, d: 0 | 1) => { const n = Number(ws[k] ?? d); return Number.isFinite(n) ? n > 0 : d > 0; };
    const wsProxy = String(ws.read_proxy ?? "basic").toLowerCase();
    const FC_PROXY = ["basic", "auto", "stealth", "enhanced"].includes(wsProxy) ? wsProxy : "basic";
    // v0.6.2 (Decision 251): scholarship work (purposes sch_*) stays inside its own cap; the cap and the reserve kept for
    // re-reading held scholarships' pages are Layer 2 settings read each run. If they cannot be read, nothing is spent.
    const schBudget = mode.startsWith("scholarship") ? await rpc("svc_scholarship_fc_budget", {}).catch(() => null) : null;
    let schLeft = schBudget && Number.isFinite(Number(schBudget.cap)) ? Math.max(0, Number(schBudget.cap) - Number(schBudget.used ?? schBudget.cap)) : 0;
    // v0.58.0 (F8): with the all-time scholarship cap off (pipeline scholarship.lifetime_cap_on, default off) the database returns used + the
    // daily scholarship share as the ceiling, so the daily share in svc_fc_spend is the only scholarship limit; nothing is unlimited.
    const schReserve = schBudget && Number.isFinite(Number(schBudget.reserve)) ? Number(schBudget.reserve) : Number.POSITIVE_INFINITY;
    // v0.14.0 (Decision 253): when the setting is on, Firecrawl is used only for target universities.
    const targets = await rpc("svc_fc_targets", {}).catch(() => null);
    const targetOnly = targets ? targets.target_only !== false : true;
    const targetIds = new Set<string>((targets?.ids || []).map(String));
    const isTarget = (providerId: string | null) => !targetOnly || (!!providerId && targetIds.has(providerId));
    // v0.15.1: switched-on university adapters, by provider (pipeline.uni_adapters, set in the UI)
    const adapters: Record<string, any> = ["read", "fc_run"].includes(mode) ? (await rpc("svc_uni_adapters", {}).catch(() => null)) || {} : {};
    // v0.47.0 (SP-1, S4-3 mislabel fix): every refusal has a name. A refusal decided here (not a target, no key, the account reserve, the
    // scholarship share) is recorded by name in the Firecrawl refusals (svc_fc_refusal_note_v1); the database records its own reasons in
    // svc_fc_spend, which the worker reports as credits_refused. "budget" is never used for a target-list refusal again.
    const noteRefusal = (purpose: string, providerId: string | null, why: string) => rpc("svc_fc_refusal_note_v1", { p_purpose: purpose, p_provider_id: providerId, p_reason: why }).catch(() => null);
    const odCover = new Map<string, Promise<boolean>>();
    const onDemandCovers = (providerId: string | null, purpose: string): Promise<boolean> => {
      if (!providerId) return Promise.resolve(false);
      const k = providerId + "|" + purpose;
      if (!odCover.has(k)) odCover.set(k, rpc("svc_fc_on_demand_covers_v1", { p_provider: providerId, p_purpose: purpose }).then((x: unknown) => x === true).catch(() => false));
      return odCover.get(k)!;
    };
    const useFcWhy = async (purpose: string, providerId: string | null, url: string, anyProvider = false): Promise<{ ok: boolean; why: string | null }> => {
      if (!fc?.secret) { await noteRefusal(purpose, providerId, "no_firecrawl_key"); return { ok: false, why: "no_firecrawl_key" } }
      // v0.84.0 (operating model 3.3.2): the target list holds scheduled work only; an open on-demand request covering this spend is decided in svc_fc_spend
      if (!anyProvider && !isTarget(providerId) && !(await onDemandCovers(providerId, purpose))) { await noteRefusal(purpose, providerId, "target_list_refused"); return { ok: false, why: "target_list_refused" } }
      const units = /search$/.test(purpose) ? 2 : /^fcx_/.test(purpose) ? 5 : 1; // v0.13.0: a JSON-format scrape costs 5 credits
      if (fcRemaining < units) { await noteRefusal(purpose, providerId, "credits_reserve"); return { ok: false, why: "credits_reserve" } }
      if (purpose.startsWith("sch_") && schLeft < units) { await noteRefusal(purpose, providerId, "scholarship_share"); return { ok: false, why: "scholarship_share" } }
      // v0.21.4: the daily budget and per-university caps are checked in the database, which records the use (or its own refusal reason)
      if (!(await rpc("svc_fc_spend", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }))) return { ok: false, why: "credits_refused" };
      if (purpose.startsWith("sch_")) schLeft -= units;
      fcRemaining -= units; return { ok: true, why: null };
    };
    const useFc = async (purpose: string, providerId: string | null, url: string, anyProvider = false) => (await useFcWhy(purpose, providerId, url, anyProvider)).ok;
    const robots = new Map<string, Promise<string>>();
    const robotsFor = (u: URL) => { if (!robots.has(u.origin)) robots.set(u.origin, fetch(u.origin + "/robots.txt", { headers: { "user-agent": UA }, signal: AbortSignal.timeout(8000) }).then((r) => r.ok ? r.text() : "").catch(() => "")); return robots.get(u.origin)! };
    // direct page read (robots.txt respected); no Firecrawl
    const readDirect = async (url: string) => {
      let status = "fetch_failed", http: number | null = null, html = "", finalUrl = url;
      try {
        const u = new URL(url);
        if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { status: "robots_disallowed", http, html, finalUrl };
        // v0.36.2 (22 Oct 2026, Sydney course data file): an address ending in .json is a page-data file and is read as JSON text
        const isJson = /\.json$/i.test(u.pathname);
        const r = await fetch(u, { headers: { "user-agent": UA, accept: isJson ? "application/json" : "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
        http = r.status; finalUrl = r.url || url;
        // v0.46.0 (R1 Q4): a data-file address may answer with the page itself (Sydney's .coredata.json files: HTML, 200); that answer is read as the page
        if (r.ok && (isJson ? /json|html/i : /html/i).test(r.headers.get("content-type") || (isJson ? "json" : "html"))) html = await r.text(); else await r.body?.cancel();
        status = html && mainText(html).length >= 300 ? "read" : html ? "too_thin" : http === 404 || http === 410 ? "gone" : [401, 403, 406, 429].includes(http) ? "blocked" : r.ok ? "not_html" : "fetch_failed";
      } catch { status = "fetch_failed" }
      return { status, http, html, finalUrl };
    };
    // v0.40.0 (Platform Admin 22 Oct 2026 23:53 "use the ai or firecrawl to fasten up the process"): one Firecrawl map lists a site's
    // addresses with their page titles (1 credit, sub-sites included); within the daily budget
    const fcMap = async (url: string, providerId: string | null, search: string | null = null) => {
      if (!(await useFc("map", providerId, url, true))) return null;
      const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url, limit: wsNum("map_limit_course_site", 30000), sitemap: "include", includeSubdomains: true, ...(search ? { search } : {}) }), signal: AbortSignal.timeout(60000) }).catch(() => null);
      if (!r) return { ok: false, status: 0, links: [] as { url: string; title: string }[] };
      const d = await r.json().catch(() => ({}));
      const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x, title: "" } : { url: String(x?.url || ""), title: String(x?.title || "") }).filter((x: { url: string }) => /^https?:\/\//.test(x.url));
      return { ok: r.ok && d?.success !== false, status: r.status, links };
    };
    // v0.18.0 (Platform Admin, 11 Oct 2026): every scholarship page is read through the scraper only. University sites are treated
    // as gatekept: no direct read, no fallback, and robots.txt is not consulted for scholarship pages (Platform Admin decision).
    // When the scraper cannot be used (credit cap, Firecrawl unavailable) the page waits and is tried again later.
    // v0.77.0 (12 Nov 2026, F-SCH production redesign §6, Platform Admin directive 12 Nov 2026 16:12, superseding the 11 Oct 2026 scraper-only
    // rule): the official page is read directly first (robots.txt respected, no credit); Firecrawl is used only when the direct read is refused,
    // blocked, a client-rendered shell or too thin to be evidence (sch-extract.ts directReadUsable). A page gone (404/410) is gone either way.
    // A rendered catalogue (listing traversal) keeps the scraper first: its items are usually drawn by script, and a thin direct copy would
    // under-count the listing (directFirst false).
    const readSch = async (url: string, providerId: string | null, waitMs: number = wsNum("scholarship.render_wait_ms", 1500), directFirst = true) => {
      const none = (status: string, http: number | null = null) => ({ status, http, html: "", finalUrl: url, via: null as string | null });
      try { new URL(url) } catch { return none("fetch_failed") }
      const dr = directFirst ? await readDirect(url) : { status: "skipped", http: null as number | null, html: "", finalUrl: url };
      if (dr.html && (dr.status === "read" || dr.status === "too_thin")) { const mt = mainText(dr.html); if (directReadUsable(mt.length, mt)) return { status: "read", http: dr.http, html: dr.html, finalUrl: dr.finalUrl, via: "direct" as string | null } }
      if (dr.status === "gone") return { ...none("gone", dr.http), finalUrl: dr.finalUrl };
      if (!(await useFc("sch_scrape", providerId, url, true))) return none("waiting_scraper");
      const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url, formats: ["rawHtml"], onlyMainContent: false, waitFor: waitMs, timeout: 30000 }), signal: AbortSignal.timeout(45000) }).catch(() => null);
      const d = r ? await r.json().catch(() => ({})) : {};
      const code = Number(d?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
      const html = r?.ok && code !== null && code < 400 ? pageHtml(d) : "";
      const finalUrl = String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || url);
      if (html) return { status: mainText(html).length >= 300 ? "read" : "too_thin", http: code, html, finalUrl, via: "firecrawl" as string | null };
      if (code === 404 || code === 410) return { ...none("gone", code), finalUrl };
      if (code && [401, 403, 406, 429].includes(code)) return { ...none("blocked", code), finalUrl };
      return none("scrape_failed", code);
    };
    // v0.58.0 (F5, F7): a scholarship page as the reader keeps it. An address ending "#award-<code>" is one award of an umbrella page: the copy
    // kept is that award's section (the other awards removed, the shared text kept), or "section_missing" when the page no longer lists it.
    // A page that now opens elsewhere is "redirected_away" (the site or catalogue home, a listing or a search page: no longer this
    // scholarship's page); one moved to another detail page is read as usual and the move is recorded by the database from its final address.
    const readSchPage = async (url: string, providerId: string | null) => {
      const pg = await readSch(url, providerId);
      if (pg.status !== "read" && pg.status !== "too_thin") return pg;
      const code = sectionCode(url);
      if (code) {
        const sec = sectionHtml(pg.html, code);
        return sec ? { ...pg, html: sec, finalUrl: url } : { ...pg, status: "section_missing", html: "" };
      }
      if (redirectOutcome(url, pg.finalUrl) === "redirected_away") return { ...pg, status: "redirected_away" };
      return pg;
    };

    if (mode === "discover") {
      const want = Math.min(Number(body.limit || 4), 8);
      const providers: { provider_id: string; website: string; extra_domains?: string[] }[] = await rpc("svc_coverage_discovery_next", { p_limit: want });
      const out: unknown[] = [];
      await pool(providers as any[], 4, async (p: { provider_id: string; website: string; courses: number }) => {
        let site: URL;
        try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: "failed", p_method: "map", p_url_count: 0, p_urls: [], p_error: "invalid website" }); return }
        try {
          // final address after redirects (monash.edu.au -> monash.edu)
          try { const r = await fetch(site, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) }); if (r.url) site = new URL(r.url); await r.body?.cancel() } catch { /* keep the recorded address */ }
          const found = new Map<string, { url: string; title?: string }>();
          const methods: string[] = [];
          const sm = await siteMapUrls(site.origin, Date.now() + 40000).catch(() => ({ urls: [] as string[], files: 0 }));
          if (sm.urls.length) methods.push(`sitemap(${sm.files})`);
          let total = sm.urls.length;
          for (const u of sm.urls) if (keepUrl({ url: u }, site.hostname)) found.set(u, { url: u });
          const target = Math.max(5, Math.ceil(Number(p.courses || 0) * 0.6));
          for (const search of [null, "course"]) {
            if (found.size >= target) break;
            { const g = await useFcWhy("map", p.provider_id, site.origin); if (!g.ok) { methods.push(`map:${g.why}`); break } }
            const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, limit: wsNum("map_limit_course_site", 30000), sitemap: "include", includeSubdomains: true, ...(search ? { search } : {}) }), signal: AbortSignal.timeout(60000) });
            const d = await r.json().catch(() => ({}));
            if (!r.ok || d?.success === false) { methods.push(`map:${r.status}`); break }
            const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title });
            methods.push(search ? `map_search(${links.length})` : `map(${links.length})`); total += links.length;
            for (const u of links) if (u.url && keepUrl(u, site.hostname) && (!found.has(u.url) || u.title)) found.set(u.url, u);
          }
          // v0.47.0 (SP-1): extra course domains a person added for this provider (courses published on another website, e.g. the ITO
          // domains of NZIST work-based learning): one map each (the site's own map first when it has one), addresses kept for that host
          for (const dom of ((p as any).extra_domains || []) as string[]) {
            let ds: URL; try { ds = new URL("https://" + dom) } catch { continue }
            const dsm = await siteMapUrls(ds.origin, Date.now() + 30000).catch(() => ({ urls: [] as string[], files: 0 }));
            let n = 0; for (const u of dsm.urls) if (keepUrl({ url: u }, ds.hostname)) { found.set(u, { url: u }); n++ }
            if (n < 5) {
              const g = await useFcWhy("map", p.provider_id, ds.origin);
              if (!g.ok) { methods.push(`${dom}:map:${g.why}`); continue }
              const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: ds.origin, limit: wsNum("map_limit_course_site", 30000), sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(60000) }).catch(() => null);
              const d = r ? await r.json().catch(() => ({})) : {};
              const links = ((d as any).links || (d as any).data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title });
              for (const u of links) if (u.url && keepUrl(u, ds.hostname) && (!found.has(u.url) || u.title)) { found.set(u.url, u); n++ }
              total += links.length;
            }
            methods.push(`${dom}(${n})`);
          }
          const kept = [...found.values()].slice(0, 12000);
          const status = kept.length ? "mapped" : "failed";
          const rec = await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: status, p_method: methods.join("+") || "none", p_url_count: total, p_urls: kept, p_error: kept.length ? null : "no course-like pages found" });
          out.push({ provider_id: p.provider_id, status, methods, total, kept: rec?.kept });
        } catch (e) {
          await rpc("svc_coverage_discovery_record", { p_provider_id: p.provider_id, p_status: "failed", p_method: "discover", p_url_count: 0, p_urls: [], p_error: e instanceof Error ? e.message : String(e) });
          out.push({ provider_id: p.provider_id, status: "failed", error: e instanceof Error ? e.message : String(e) });
        }
      });
      return j({ ok: true, mode, providers: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }


    // v0.10.0 (2 Oct 2026, Platform Admin 21:18): third-party directory capture, hints only. Only allow-listed directory
    // hosts; robots.txt respected; each page fetched through Firecrawl (scrape, html + links), stored gzipped in the
    // evidence bucket under thirdparty/<site>/<country>/ and recorded with its links. Nothing from a directory is
    // admitted; names, website links and course counts become hints that our own rules verify.
    // directory_capture: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.10.0: AI page-identity check, qualification only (contract cf247-page-identity-v1.0.0). Runs one pinned model on
    // the frozen holdout and records each answer with the deterministic checks. Nothing is admitted or switched on.
    // id_qualify: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.10.1: the OpenRouter key's own limits (weekly, daily, total), read with the governed credential; the key is
    // never returned.
    // v0.13.0 (3 Oct 2026, Platform Admin "Yes, qualify now"): Firecrawl's own AI extraction (JSON format) as a CANDIDATE
    // route for intakes and English. Qualification only: each frozen holdout case is fetched and rendered by Firecrawl,
    // which returns fields against a fixed schema; the answer is scored against the gold value and recorded
    // (svc_fc_extract_result). Nothing is admitted and no cascade changes. Firecrawl does not name its model, so a pass
    // admits it only as a provider-level route (re-tested weekly, paused on a failure), never a model-cascade step.
    // fc_extract_qualify: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.21.1 (bug 12/10-01): the OpenRouter balance, every 15 minutes (job openrouter-balance), recorded for the AI limits and notices
    if (mode === "openrouter_balance") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const r = await fetch("https://openrouter.ai/api/v1/credits", { headers: { authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) });
      const d = (await r.json().catch(() => ({})))?.data || {};
      if (!r.ok || !Number.isFinite(Number(d.total_credits)) || !Number.isFinite(Number(d.total_usage))) return j({ ok: false, mode, http: r.status, error: "no balance in the reply", workerVersion: VERSION, worker: WORKER }, 502);
      const rec = await rpc("svc_openrouter_balance_record", { p_payload: { total_credits: Number(d.total_credits), total_usage: Number(d.total_usage) } });
      return j({ ok: true, mode, ...rec, workerVersion: VERSION, worker: WORKER });
    }
    // openrouter_key: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.10.1: reference lists read as a whole file (Hipo university-domains-list, MIT), stored as evidence, loaded as
    // website hints (Decision 232). Only allow-listed files.
    // reference_capture: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.10.1: website hints (reference lists, directories) are accepted only when our own website rule passes on the
    // home page: AU the CRICOS provider code on the page; CA a .ca site naming the provider or printing its DLI number;
    // NZ a .nz site naming the provider.
    // site_hint_verify: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    // v0.10.0: pages stored as identity mismatches are checked again with the current identity rule from their stored
    // copy (no fetch). A page that now passes is set back to read; the usual admission runs on it.
    if (mode === "reidentify") {
      const rule = IDENTITY_RULE;
      const rows: { course_id: string; evidence_id: string; storage_path: string; url: string; title: string; code: string; country?: string }[] =
        await rpc("svc_coverage_reidentify_next", { p_limit: Math.min(Number(body.limit || 100), 400), p_rule: rule });
      const tally: Record<string, number> = {};
      await pool(rows, 10, async (r) => {
        let basis: string | null = null, cand: unknown = null;
        try {
          if (Date.now() - t0 > BUDGET_MS) return;
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          basis = identity(html, text, r.title, r.code, false, r.country || "");
          if (basis === "field_award" && staleCalendarUrl(r.url)) basis = null;
          if (basis) cand = { final_url: r.url, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(r.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION };
          const st = await rpc("svc_coverage_reidentify_record", { p_course_id: r.course_id, p_evidence_id: r.evidence_id, p_rule: rule, p_identity_basis: basis, p_candidates: cand });
          tally[st] = (tally[st] || 0) + 1;
        } catch { tally.failed = (tally.failed || 0) + 1 }
      });
      return j({ ok: true, mode, rule, rows: rows.length, tally, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "reextract") {
      const rows: { course_id: string; storage_path: string; title: string; code: string; status: string; url: string; country?: string }[] = await rpc("svc_coverage_reextract_next", { p_limit: Math.min(Number(body.limit || 100), 200), p_version: VERSION });
      let done = 0, failed = 0;
      await pool(rows, 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          const cand = { final_url: r.url, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(r.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION };
          await rpc("svc_coverage_candidates_update", { p_course_id: r.course_id, p_candidates: cand }); done++;
        } catch { failed++ }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.6.0 (Decision 163, Option A): tuition found on CRICOS-code pages goes to the qualified Layer 3 model.
    // The stored page is turned into plain text (the qualified interpreter reads text evidence only), saved as its
    // own evidence, and recorded as a Layer 2 run item with a Layer 3 work item. Nothing is admitted here.
    if (mode === "tuition_handoff") {
      const rows: { course_id: string; storage_path: string; url: string }[] = await rpc("svc_coverage_tuition_handoff_next", { p_limit: Math.min(Number(body.limit || 50), 100) });
      let done = 0, failed = 0; const errors: string[] = [];
      await pool(rows, 8, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html);
          if (text.length < 200) throw Error("page text too short");
          const bytes = new TextEncoder().encode(text), hash = await sha256(bytes);
          const path = `coverage-text/${r.course_id}/${hash.slice(0, 32)}.txt`;
          const up = await c.storage.from("evidence").upload(path, bytes, { contentType: "text/plain", upsert: true });
          if (up.error) throw Error("upload: " + up.error.message);
          const res = await rpc("svc_coverage_tuition_handoff_record", { p_course_id: r.course_id, p_storage_path: path, p_content_hash: hash, p_bytes: bytes.length });
          if (res?.queued) done++; else failed++;
        } catch (e) { failed++; if (errors.length < 3) errors.push(e instanceof Error ? e.message : String(e)) }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, errors, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.17.33 (10 Oct 2026, Platform Admin Fix 2, decision "Both, kept separate"): the provider's public phone and email from its own
    // website (home page and contact page, direct reads, robots.txt respected, no Firecrawl). Only an email on the provider's own
    // domain is taken; the database never replaces a value entered by hand.
    // v0.25.0 (15 Oct 2026, Platform Admin: "make it background Job to find and attached"): the provider's logo from its own home page
    // (header logo image, declared logo, SVG icon, touch icon), type checked from the bytes, size checked, SVG only when it is a plain
    // drawing; stored in provider-assets and attached by the database only when the provider still has no logo. Not found is flagged.
    if (mode === "logo_find") {
      const next: { items: { provider_id: string; name: string; website: string; country: string }[]; min_pixels: number } = await rpc("svc_logo_find_next", { p_limit: Math.min(Number(body.limit || 0), 40) });
      const minPx = Number(next?.min_pixels || 0);
      const out: unknown[] = [];
      const privateHost = (h: string) => /^(localhost|127\.|10\.|192\.168\.|169\.254\.|172\.(1[6-9]|2\d|3[01])\.|\[?::1|\[?f[cd])/i.test(h) || h.endsWith(".local");
      const getImage = async (url: string) => {
        const u = new URL(url); if (u.protocol !== "https:" || privateHost(u.hostname)) return { error: "unsafe address" };
        const r = await fetch(u, { headers: { "user-agent": UA, accept: "image/svg+xml,image/png,image/jpeg,image/webp,image/*;q=0.8" }, redirect: "follow", signal: AbortSignal.timeout(15000) }).catch(() => null);
        if (!r) return { error: "fetch failed" };
        if (!r.ok) { await r.body?.cancel(); return { error: `http ${r.status}` } }
        if (r.url && (!r.url.startsWith("https:") || privateHost(new URL(r.url).hostname))) { await r.body?.cancel(); return { error: "unsafe redirect" } }
        const bytes = new Uint8Array(await r.arrayBuffer());
        if (bytes.byteLength < 100 || bytes.byteLength > 5_000_000) return { error: `size ${bytes.byteLength}` }; // fixed: the provider-assets bucket's limit
        const mime = sniffMime(bytes, String(r.headers.get("content-type") || ""));
        if (!mime) return { error: "not an image" };
        let width: number | null = null, height: number | null = null;
        if (mime === "image/svg+xml") { if (!svgSafe(new TextDecoder().decode(bytes))) return { error: "svg not a plain drawing" } }
        else { const d = imageSize(bytes, mime); if (!d) return { error: "size unreadable" }; width = d.width; height = d.height; if (Math.max(width, height) < minPx) return { error: `too small ${width}x${height}` } } // v0.25.1: the longer side (wordmarks are wide)
        return { bytes, mime, width, height, finalUrl: r.url || url };
      };
      await pool(next?.items || [], 4, async (p) => {
        const tried: { url: string; method: string; result: string }[] = [];
        const record = (status: string, reason: string | null, extra: Record<string, unknown> = {}) => rpc("svc_logo_find_record", {
          p_provider_id: p.provider_id, p_status: status, p_reason: reason, p_method: extra.method ?? null, p_storage_path: extra.path ?? null, p_mime_type: extra.mime ?? null,
          p_content_hash: extra.sha ?? null, p_width: extra.width ?? null, p_height: extra.height ?? null, p_source_url: extra.url ?? null, p_page_url: extra.page ?? null,
          p_evidence: { worker: WORKER, tried } });
        try {
          if (Date.now() - t0 > BUDGET_MS) { await record("failed", "run out of time; tried again next run"); return }
          let site: URL; try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await record("not_found", "website address not valid"); return }
          const home = await readDirect(site.origin + "/");
          if (!home.html) { await record("not_found", `home page not read (${home.status}${home.http ? " " + home.http : ""})`, { page: home.finalUrl }); out.push({ provider_id: p.provider_id, status: "not_found" }); return }
          const cands = logoCandidates(home.html, home.finalUrl || site.origin + "/", p.name).slice(0, 4);
          for (const cand of cands) {
            const img = await getImage(cand.url);
            if ("error" in img) { tried.push({ url: cand.url, method: cand.method, result: String(img.error) }); continue }
            const sha = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", img.bytes))).map((x) => x.toString(16).padStart(2, "0")).join("");
            const ext = img.mime === "image/svg+xml" ? "svg" : img.mime === "image/png" ? "png" : img.mime === "image/webp" ? "webp" : "jpg";
            const path = `providers/${p.provider_id}/logo/auto/${sha}.${ext}`;
            const up = await c.storage.from("provider-assets").upload(path, img.bytes, { contentType: img.mime, upsert: true, cacheControl: "31536000" });
            if (up.error) { tried.push({ url: cand.url, method: cand.method, result: "store failed: " + up.error.message }); continue }
            tried.push({ url: cand.url, method: cand.method, result: "stored" });
            const res = await record("found", null, { method: cand.method, path, mime: img.mime, sha, width: img.width, height: img.height, url: img.finalUrl, page: home.finalUrl });
            out.push({ provider_id: p.provider_id, status: res?.status, method: cand.method, url: img.finalUrl }); return;
          }
          await record("not_found", cands.length ? "logo images on the home page could not be used" : "no logo on the home page", { page: home.finalUrl });
          out.push({ provider_id: p.provider_id, status: "not_found", candidates: cands.length });
        } catch (e) { await record("failed", e instanceof Error ? e.message.slice(0, 200) : String(e)).catch(() => null); out.push({ provider_id: p.provider_id, status: "failed" }) }
      });
      return j({ ok: true, mode, providers: out, ms: Date.now() - t0, workerVersion: WORKER });
    }
    // v0.26.0 (15 Oct 2026, Platform Admin: "when comes online we re-join them for enrichment"): the flag unit's free check. A provider held
    // because its website did not answer is read directly (no Firecrawl, no AI); a site that answers is released and re-queued, one that
    // does not waits for the next step of the back-off (Pipeline settings › Flags).
    if (mode === "flag_check") {
      const items: { flag_id: number; provider_id: string; name: string; website: string }[] = await rpc("svc_flag_check_next", { p_limit: Math.min(Number(body.limit || 0), 50) });
      const out: unknown[] = [];
      await pool(items || [], 4, async (it) => {
        let site: URL | null = null; try { site = new URL(/^https?:/i.test(it.website) ? it.website : "https://" + it.website) } catch { site = null }
        if (!site) { await rpc("svc_flag_check_record", { p_flag_id: it.flag_id, p_ok: false, p_http: null, p_status: "bad website address", p_evidence: { website: it.website, worker: WORKER } }); return }
        const home = await readDirect(site.origin + "/");
        const ok = Boolean(home.html) && (home.http ?? 0) < 400;
        await rpc("svc_flag_check_record", { p_flag_id: it.flag_id, p_ok: ok, p_http: home.http, p_status: home.status, p_evidence: { url: home.finalUrl, status: home.status, http: home.http, worker: WORKER } });
        out.push({ provider_id: it.provider_id, ok, status: home.status, http: home.http });
      });
      return j({ ok: true, mode, checked: out.length, providers: out, ms: Date.now() - t0, workerVersion: WORKER });
    }
    if (mode === "contact_page") {
      const provs: { provider_id: string; name: string; website: string; country: string }[] = await rpc("svc_provider_contact_next", { p_limit: Math.min(Number(body.limit || 8), 20) });
      const out: unknown[] = [];
      await pool(provs, 4, async (p) => {
        let site: URL; try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_provider_contact_record", { p_provider_id: p.provider_id, p_phone: null, p_email: null, p_url: null, p_evidence: { error: "bad website" } }); return }
        const pages: { url: string; status: string; http: number | null }[] = [];
        const home = await readDirect(site.origin + "/"); pages.push({ url: site.origin + "/", status: home.status, http: home.http });
        const htmls: { url: string; html: string }[] = home.html ? [{ url: home.finalUrl, html: home.html }] : [];
        const base = home.finalUrl || site.origin + "/";
        const siteHost = (() => { try { return new URL(base).hostname.toLowerCase().replace(/^www\./, "") } catch { return site.hostname.toLowerCase().replace(/^www\./, "") } })();
        // v0.17.34: the main contact page first (short path, "Contact us"); never research, media, careers or agent pages
        const ranked = new Map<string, number>();
        for (const m of (home.html || "").matchAll(/<a\b[^>]*href\s*=\s*["']([^"'#]+)["'][^>]*>([\s\S]{0,200}?)<\/a>/gi)) {
          const text = m[2].replace(/<[^>]+>/g, " ").replace(/\s+/g, " ").trim();
          if (!/contact|enquir/i.test(m[1] + " " + text) || /research|media|news|career|job|alumni|agent|staff|library|donat|partner/i.test(m[1] + " " + text)) continue;
          try {
            const u = new URL(m[1], base); const h = u.hostname.toLowerCase().replace(/^www\./, "");
            if (!/^https?:$/.test(u.protocol) || !(h === siteHost || h.endsWith("." + siteHost))) continue;
            const depth = u.pathname.split("/").filter(Boolean).length;
            const score = (/^\/?(contact(-us)?|enquir\w*)(\.html?|\/)?$/i.test(u.pathname.replace(/^\/en\//, "/")) ? 10 : 0) + (/^contact( us)?$/i.test(text) ? 5 : 0) + (/international|future|study|admission/i.test(u.pathname + " " + text) ? 3 : 0) - depth;
            ranked.set(u.href, Math.max(ranked.get(u.href) ?? -99, score));
          } catch { /* skip */ }
        }
        const contactLinks = [...ranked.entries()].sort((a, b) => b[1] - a[1]).slice(0, 2).map((x) => x[0]);
        for (const cu of contactLinks) { const r = await readDirect(cu); pages.push({ url: cu, status: r.status, http: r.http }); if (r.html) htmls.push({ url: r.finalUrl, html: r.html }) }
        // v0.17.35: an address on another service (vu.libanswers.com for vu.edu.au) is not the provider's own. The name part of the
        // email domain, after its public suffix, must be the site's (waifs.edu.au for waifs.wa.edu.au is still accepted).
        const SUF = /\.((com|net|org|edu|gov|asn|id)\.au|(act|nsw|nt|qld|sa|tas|vic|wa)\.edu\.au|(ac|co|org|net|govt|school)\.nz|com|net|org|edu|ca|nz|au|io|co)$/i;
        const regLabel = (h: string) => h.replace(SUF, "").split(".").pop() || "";
        const ownEmail = (e: string) => { const d = e.split("@")[1]?.toLowerCase() || ""; return d === siteHost || d.endsWith("." + siteHost) || siteHost.endsWith("." + d) || (SUF.test(d) && regLabel(d) === regLabel(siteHost)) };
        const emails = new Map<string, number>(), phones = new Map<string, number>();
        const PREF = /^(info|enquir|admission|international|study|future|student|contact|reception|admin|office|hello|courses|ask)/i;
        // v0.17.34: mailboxes that are never the provider's public enquiry address
        const NEG = /^(media|press|news|security|privacy|feedback|complain|careers?|jobs|hr|recruit(ment)?@|alumni|donat|giving|library|it|helpdesk|service-?desk|research|grants|events|marketing|web(master)?|campus\.assist|accounts?|finance|procurement|noreply|no-reply)/i;
        // v0.17.35: also anywhere in the mailbox name: library, vet hospital, clinic, ethics, philanthropy, partnerships, facilities, research
        const NEG2 = /(librar|vethosp|veterinar|hospital|clinic|ethics|philanthrop|partnership|helpdesk|facilit|research)/i;
        const okBox = (e: string) => !NEG.test(e) && !NEG2.test(e.split("@")[0]);
        for (const { html } of htmls) {
          for (const m of html.matchAll(/mailto:([^"'?\s>]+)/gi)) { const e = decodeURIComponent(m[1]).trim().toLowerCase(); if (/^[^@\s]+@[^@\s]+\.[a-z]{2,}$/.test(e) && ownEmail(e) && okBox(e)) emails.set(e, (emails.get(e) || 0) + 3 + (PREF.test(e) ? 5 : 0)) }
          const text = htmlToText(html);
          for (const m of text.matchAll(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g)) { const e = m[0].toLowerCase(); if (!/\.(png|jpe?g|gif|svg|webp)$/.test(e) && ownEmail(e) && okBox(e)) emails.set(e, (emails.get(e) || 0) + 1 + (PREF.test(e) ? 5 : 0)) }
          for (const m of html.matchAll(/href\s*=\s*["']tel:([^"']+)["']/gi)) { const d = decodeURIComponent(m[1]).replace(/[^\d+]/g, ""); if (d.replace(/\D/g, "").length >= 8) phones.set(d, (phones.get(d) || 0) + 3 - (/^(\+?614|04)/.test(d) ? 2 : 0)) }
          for (const m of text.matchAll(/(?:phone|tel|call|ph)[^0-9+]{0,12}((?:\+?6[14]|\(0\d\)|0\d|1[38]00)[\d\s()-]{6,14}\d)/gi)) { const d = m[1].replace(/[^\d+]/g, ""); if (d.replace(/\D/g, "").length >= 8) phones.set(d, (phones.get(d) || 0) + 1) }
        }
        const best = (m: Map<string, number>) => [...m.entries()].sort((a, b) => b[1] - a[1])[0]?.[0] || null;
        const email = best(emails), phone = best(phones);
        await rpc("svc_provider_contact_record", { p_provider_id: p.provider_id, p_phone: phone, p_email: email, p_url: contactLinks[0] || base,
          p_evidence: { pages, emails: Object.fromEntries(emails), phones: Object.fromEntries(phones), worker: WORKER } });
        out.push({ provider_id: p.provider_id, phone, email });
      });
      return j({ ok: true, mode, providers: out, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.17.33 (Fix 2): the Principal Executive Officer from the CRICOS website, held as an internal regulatory contact (never published).
    // Platform Admin decision "All at once" (10 Oct 2026): Firecrawl is used for every AU provider with a CRICOS code, inside the budget
    // reserve but outside the target-university rule. The page must show the provider's CRICOS code.
    if (mode === "cricos_peo") {
      const provs: { provider_id: string; name: string; cricos: string }[] = await rpc("svc_cricos_peo_next", { p_limit: Math.min(Number(body.limit || 4), 8) });
      const out: unknown[] = [];
      const spend = async (units: number, purpose: string, providerId: string, url: string) => { if (!fc?.secret || fcRemaining < units) return false; if (!(await rpc("svc_fc_spend", { p_units: units, p_purpose: purpose, p_provider_id: providerId, p_url: url }))) return false; fcRemaining -= units; return true };
      const field = (t: string, label: string) => (t.match(new RegExp(label + "\\s*:?[\\s|]*([^\\n|]{0,120}?)\\s*(?:\\n|\\||Title\\s*:|Phone Number\\s*:|Facsimile Number\\s*:|Email Address\\s*:|$)", "i"))?.[1] || "").replace(/[*_\\]/g, "").trim() || null;
      await pool(provs, 2, async (p) => {
        const code = String(p.cricos || "").toUpperCase(), tried: unknown[] = [];
        let found: Record<string, string | null> | null = null, pageUrl: string | null = null;
        // v0.17.34: the CRICOS institution page is addressed by provider code, so no search is needed. A direct read first; Firecrawl
        // (1 credit) only when the direct read does not show the contact.
        try {
          for (const u of [`https://cricos.education.gov.au/Institution/InstitutionDetails.aspx?ProviderCode=${code}`]) {
            let md = "";
            const dr = await fetch(u, { headers: { "user-agent": UA }, signal: AbortSignal.timeout(20000) }).catch(() => null);
            const raw = dr && dr.ok ? await dr.text() : "";
            if (/Principal Executive Officer/i.test(raw)) md = htmlToText(raw).replace(/\s{2,}/g, "\n");
            else if (await spend(1, "peo_scrape", p.provider_id, u)) {
              const sc = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: u, formats: ["markdown"], onlyMainContent: false, timeout: 40000 }), signal: AbortSignal.timeout(55000) });
              const sd = await sc.json().catch(() => ({})); md = String(sd?.data?.markdown || "");
            } else { tried.push({ url: u, budget: true }); break }
            const hasCode = new RegExp("(^|[^0-9A-Z])" + code + "([^0-9A-Z]|$)", "i").test(md) || new RegExp(code, "i").test(raw);
            const i = md.search(/Principal Executive Officer/i);
            tried.push({ url: u, direct: /Principal Executive Officer/i.test(raw), http: dr?.status ?? null, has_code: hasCode, peo: i >= 0 });
            if (i >= 0 && hasCode) { const t = md.slice(i, i + 800); found = { name: field(t, "Name"), title: field(t, "Title"), phone: field(t, "Phone Number"), email: (t.match(/[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/) || [null])[0] }; pageUrl = u; break }
          }
        } catch (e) { tried.push({ error: e instanceof Error ? e.message : String(e) }) }
        await rpc("svc_cricos_peo_record", { p_provider_id: p.provider_id, p_outcome: found ? "found" : tried.some((x: any) => x?.budget) ? "budget" : "not_found", p_name: found?.name ?? null, p_title: found?.title ?? null, p_phone: found?.phone ?? null, p_email: found?.email ?? null, p_url: pageUrl, p_evidence: { code, tried, worker: WORKER } });
        out.push({ provider_id: p.provider_id, status: found ? "found" : "not_found" });
      });
      return j({ ok: true, mode, providers: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.19.0 (11 Oct 2026, Platform Admin Feature 4): central pages found by Firecrawl. One map of the provider's own site
    // (about 1 credit); fixed rules pick the likeliest key-dates, international-fee and English-requirements pages, kept as
    // suggestions for a person to attach (pipeline.provider_central_search).
    if (mode === "central_find") {
      const provs: { provider_id: string; name: string; website: string }[] = await rpc("svc_central_find_next", { p_limit: Math.min(Number(body.limit || 4), 10) });
      const out: unknown[] = [];
      await pool(provs, 2, async (p) => {
        let site: URL; try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_central_find_record", { p_provider_id: p.provider_id, p_found: [], p_evidence: { error: "the website address cannot be read", worker: WORKER } }); out.push({ provider_id: p.provider_id, status: "bad_website" }); return }
        // v0.64.0 (F-AER.01): a provider AER source discovery asked about gets one targeted entry-requirements search of its own website when the whole-site map is
        // refused (its refresh interval is not due) or found no entry page; the database decides whether it is wanted and whether the credit may be spent
        const wantEntry = !!(await rpc("svc_aer_entry_search_wanted", { p_provider_id: p.provider_id }).catch(() => false));
        const entrySearch = async (): Promise<string> => {
          if (!(await useFc("central_entry_search", p.provider_id, site.origin, true))) return "entry_search_refused";
          try {
            const q = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, search: ENTRY_SEARCH, limit: wsNum("map_limit_central_search", 200), sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(45000) });
            const qd = await q.json().catch(() => ({}));
            if (!q.ok || qd?.success === false) { await rpc("svc_central_entry_record", { p_provider_id: p.provider_id, p_found: [], p_evidence: { error: `entry search ${q.status}`, worker: WORKER } }); return "entry_search_failed" }
            const ls = (qd.links || qd.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x?.url, title: x?.title }).filter((x: any) => typeof x.url === "string");
            const ef = entryCandidates(ls, site.hostname);
            await rpc("svc_central_entry_record", { p_provider_id: p.provider_id, p_found: ef, p_evidence: { site: site.origin, search: ENTRY_SEARCH, addresses: ls.length, worker: WORKER } });
            return ef.length ? "entry_found" : "entry_none";
          } catch (e) { await rpc("svc_central_entry_record", { p_provider_id: p.provider_id, p_found: [], p_evidence: { error: e instanceof Error ? e.message : String(e), worker: WORKER } }); return "entry_search_failed" }
        };
        { const g = await useFcWhy("central_map", p.provider_id, site.origin, true);
          if (!g.ok) {
            if (wantEntry) { out.push({ provider_id: p.provider_id, status: await entrySearch() }); return }
            await rpc("svc_central_find_record", { p_provider_id: p.provider_id, p_found: null, p_evidence: { note: `Firecrawl refused: ${g.why}`, refusal: g.why, worker: WORKER } }); out.push({ provider_id: p.provider_id, status: g.why }); return } }
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, limit: wsNum("map_limit_central", 5000), sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(60000) });
          const d = await r.json().catch(() => ({}));
          if (!r.ok || d?.success === false) { await rpc("svc_central_find_record", { p_provider_id: p.provider_id, p_found: [], p_evidence: { error: `map ${r.status}`, worker: WORKER } }); out.push({ provider_id: p.provider_id, status: "map_failed" }); return }
          const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title }).filter((x: any) => typeof x.url === "string");
          let found = centralCandidates(links, site.hostname); const searched: string[] = [];
          // a targeted map (about 1 credit) for each kind the whole-site map found no strong page of
          for (const kind of weakKinds(found)) {
            if (!(await useFc("central_map", p.provider_id, site.origin, true))) break;
            const q = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: site.origin, search: CENTRAL_SEARCH[kind], limit: wsNum("map_limit_central_search", 200), sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(45000) }).catch(() => null);
            const qd = q ? await q.json().catch(() => ({})) : {}; searched.push(`${kind}:${q?.status ?? "error"}`);
            for (const x of (qd.links || qd.data?.links || [])) { const l = typeof x === "string" ? { url: x } : { url: x?.url, title: x?.title }; if (typeof l.url === "string") links.push(l) }
          }
          if (searched.length) found = centralCandidates(links, site.hostname);
          await rpc("svc_central_find_record", { p_provider_id: p.provider_id, p_found: found, p_evidence: { site: site.origin, addresses: links.length, searched, worker: WORKER } });
          // v0.64.0 (F-AER.01): the whole-site map found no entry page a reader would take (score 4 or more): one targeted entry search when AER discovery asked
          const entry = wantEntry && !found.some((c) => c.kind === "entry_requirements" && c.score >= 4) ? await entrySearch() : null;
          out.push({ provider_id: p.provider_id, status: "done", addresses: links.length, found: found.length, ...(entry ? { entry } : {}) });
        } catch (e) { await rpc("svc_central_find_record", { p_provider_id: p.provider_id, p_found: [], p_evidence: { error: e instanceof Error ? e.message : String(e), worker: WORKER } }); out.push({ provider_id: p.provider_id, status: "error" }) }
      });
      return j({ ok: true, mode, providers: out, ms: Date.now() - t0, workerVersion: WORKER });
    }
    // v0.31.0 (18 Oct 2026, bug 18/10-01, Platform Admin 20:35 "validate or change the website in the adapter builder"): Check website and
    // Change website. The address's home page is read now (directly; through the scraper, about 1 credit, only when the site refuses a direct
    // read). What it shows is recorded; the verdict and any change are decided in the database (svc_provider_website_check_record).
    if (mode === "site_check") {
      const items: { id: string; provider_id: string; url: string; name: string; trading: string | null; country: string | null; cricos: string | null; dli: string | null; register_site: string | null }[] =
        await rpc("svc_provider_website_check_next", { p_limit: Math.min(Number(body.limit || 5), 10) });
      const skipDomains: string[] = await rpc("svc_reference_domains", { p_use: "not_provider_site" });
      if (!Array.isArray(skipDomains) || skipDomains.length === 0) return j({ ok: false, mode, error: "reference sources list is empty or unavailable" }, 503);
      const skip = (host: string) => { const h = host.toLowerCase(); return skipDomains.some((d) => d.includes(".") ? (h === d || h.endsWith("." + d)) : new RegExp("(^|\\.)" + d.replace(/[^a-z0-9-]/g, "")).test(h)); };
      const bare = (h: string) => h.toLowerCase().replace(/^www\./, "");
      const out: unknown[] = [];
      await pool(items, 3, async (it) => {
        const res: Record<string, unknown> = { url: it.url, worker: WORKER };
        let origin = "";
        try { origin = new URL(it.url).origin } catch { /* recorded below */ }
        if (!origin) { res.answers = false; res.note = "not a web address"; out.push({ id: it.id, ...(await rpc("svc_provider_website_check_record", { p_id: it.id, p_result: res })) }); return }
        const cc = String(it.country || "AU").toUpperCase(), code = String(it.cricos || "").toUpperCase();
        let html = "", http: number | null = null, finalUrl = origin + "/", via = "direct";
        try {
          const r = await fetch(origin + "/", { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(15000) });
          http = r.status; finalUrl = r.url || finalUrl; html = r.ok ? await r.text() : "";
        } catch (e) { res.fetch_error = e instanceof Error ? e.message.slice(0, 200) : String(e).slice(0, 200) }
        if ((!html || (http !== null && [401, 403, 429, 503].includes(http))) && (await useFc("site_verify", it.provider_id, origin + "/", true))) {
          try {
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: origin + "/", formats: ["rawHtml"], onlyMainContent: false, waitFor: 1500, ...(/^[A-Z]{2}$/.test(cc) ? { location: { country: cc } } : {}) }), signal: AbortSignal.timeout(60000) });
            const d = await r.json().catch(() => ({}));
            const h2 = String(d?.data?.rawHtml || d?.data?.html || "");
            if (h2) { html = h2; via = "scraper"; finalUrl = String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || finalUrl) }
          } catch (e) { res.scraper_error = e instanceof Error ? e.message.slice(0, 200) : String(e).slice(0, 200) }
        }
        let host = bare(new URL(origin).hostname);
        try { host = bare(new URL(finalUrl).hostname); res.final_url = new URL(finalUrl).origin } catch { res.final_url = origin }
        const text = html ? htmlToText(html) : "";
        res.http = http; res.via = via; res.answers = html.length > 500; res.host = host;
        res.redirected = host !== bare(new URL(origin).hostname);
        res.third_party = skip(host);
        res.title = html ? titleOf(html).slice(0, 200) : null;
        res.cricos_code = code.length >= 5 ? code : null;
        res.cricos_on_site = code.length >= 5 && text ? new RegExp("(^|[^0-9A-Z])" + code.split("").join("\\s?") + "([^0-9A-Z]|$)", "i").test(text) : (code.length >= 5 ? false : null);
        res.name_basis = html ? (siteNameMatch(html, text, it.name, it.dli || "", host) || (it.trading ? siteNameMatch(html, text, it.trading, "", host) : null)) : null;
        res.domain_fits = domainFitsName(host, siteNorm(it.name)) || (it.trading ? domainFitsName(host, siteNorm(it.trading)) : false);
        let reg: string | null = null; try { reg = it.register_site ? bare(new URL(it.register_site).hostname) : null } catch { /* none */ }
        res.register_site = it.register_site; res.register_match = reg ? reg === host : null;
        out.push({ id: it.id, ...(await rpc("svc_provider_website_check_record", { p_id: it.id, p_result: res })) });
      });
      return j({ ok: true, mode, items: items.length, checks: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    if (mode === "find_site") {
      const provs: { provider_id: string; name: string; trading: string | null; cricos: string; country?: string; dli?: string }[] = await rpc("svc_coverage_site_next", { p_limit: Math.min(Number(body.limit || 5), 10) });
      const out: unknown[] = [];
      // v0.6.4: sites that are never a university's own website come from Reference sources (use not_provider_site),
      // managed in the admin, instead of a fixed pattern here. No list means no search (fail closed).
      const skipDomains: string[] = await rpc("svc_reference_domains", { p_use: "not_provider_site" });
      if (!Array.isArray(skipDomains) || skipDomains.length === 0) return j({ ok: false, mode, error: "reference sources list is empty or unavailable" }, 503);
      const SKIP = { test: (host: string) => { const h = host.toLowerCase(); return skipDomains.some((d) => d.includes(".") ? (h === d || h.endsWith("." + d)) : new RegExp("(^|\\.)" + d.replace(/[^a-z0-9-]/g, "")).test(h)); } };
      // Decision 220: a Canadian provider's site, found by name. Accepted only on a .ca host (not a directory or
      // register) whose home page names the provider or prints its IRCC DLI number.
      // v0.19.0 (11 Oct 2026, Platform Admin "search every provider without a website"): the same search by name for every
      // country without a register code to check against (New Zealand on a .nz host, Australia without a CRICOS code on a
      // .au host, any other country on any host that is not a directory or register), for every provider, not only targets.
      // v0.19.1 (11 Oct 2026): a home page that refuses a direct read (403, 429, a gatekeeper) is read through the scraper
      // (about 1 credit), so a provider behind a gatekeeper can still be verified (George Brown, georgebrown.ca answered 403).
      const viaScraper = async (providerId: string, url: string, cc: string): Promise<{ html: string; finalUrl: string } | null> => {
        if (!(await useFc("site_verify", providerId, url, true))) return null;
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 1500, ...(/^[A-Z]{2}$/.test(cc) ? { location: { country: cc } } : {}) }), signal: AbortSignal.timeout(60000) });
          const d = await r.json().catch(() => ({}));
          const html = String(d?.data?.rawHtml || d?.data?.html || "");
          return html ? { html, finalUrl: String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || url) } : null;
        } catch { return null }
      };
      const tldOk = (host: string, cc: string) => cc === "CA" ? host.endsWith(".ca") : cc === "NZ" ? host.endsWith(".nz") : cc === "AU" ? host.endsWith(".au") : true;
      const findCanadianSite = async (p: { provider_id: string; name: string; dli?: string }, cc = "CA") => {
        const query = `${p.name} official website`;
        if (!(await useFc("search", p.provider_id, p.name, true))) { await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "Firecrawl budget reserve reached" } }); return { provider_id: p.provider_id, status: "budget" } }
        let accepted: string | null = null, basis: string | null = null; const tried: unknown[] = [];
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query, limit: wsNum("search_results_website", 8), ...(/^[A-Z]{2}$/.test(cc) ? { country: cc } : {}) }), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({}));
          const results = (d?.data?.web || d?.data || []).map((x: any) => ({ url: x.url })).filter((x: any) => typeof x.url === "string");
          const seenHosts = new Set<string>();
          for (const res of results) {
            let u: URL; try { u = new URL(res.url) } catch { continue }
            const host = u.hostname.toLowerCase();
            if (!tldOk(host, cc) || SKIP.test(host) || seenHosts.has(host)) { tried.push({ page: res.url, skipped: true }); continue }
            seenHosts.add(host);
            try {
              const h = await fetch(u.origin + "/", { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) });
              let html = h.ok ? await h.text() : "", via = "direct", hUrl = h.url || u.origin;
              if (!html || [401, 403, 429, 503].includes(h.status)) { const sc = await viaScraper(p.provider_id, u.origin + "/", cc); if (sc) { html = sc.html; hUrl = sc.finalUrl; via = "scraper" } }
              let finalHost = host; try { finalHost = new URL(hUrl).hostname.toLowerCase() } catch { /* keep */ }
              const b = tldOk(finalHost, cc) && !SKIP.test(finalHost) ? siteNameMatch(html, htmlToText(html), p.name, p.dli || "", finalHost) : null;
              tried.push({ page: u.origin + "/", http: h.status, via, basis: b });
              if (b) { accepted = new URL(hUrl).origin; basis = b; break }
            } catch { tried.push({ page: u.origin + "/", error: true }) }
            if (seenHosts.size >= 4) break;
          }
        } catch (e) { tried.push({ error: e instanceof Error ? e.message : String(e) }) }
        await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: accepted, p_evidence: { query, country: cc, tried, accepted, basis, worker: WORKER } });
        return { provider_id: p.provider_id, status: accepted ? "found" : "not_found", website: accepted, basis };
      };
      // v0.21.6: the official registers. Register hosts and links that are never a provider's own website.
      const REGISTERS: { key: string; site: string; page: RegExp }[] = [
        { key: "training_gov_au", site: "training.gov.au", page: /^https?:\/\/(www\.)?training\.gov\.au\/(Organisation|organisation)\/Details\/[0-9A-Za-z]+/ },
        { key: "teqsa", site: "teqsa.gov.au", page: /^https?:\/\/(www\.)?teqsa\.gov\.au\/national-register\/provider\/[^/?#]+/ },
      ];
      const NOT_OWN = /(^|\.)(gov\.au|facebook\.com|linkedin\.com|instagram\.com|twitter\.com|x\.com|youtube\.com|google\.[a-z.]+|apple\.com|microsoft\.com|w3\.org|cloudflare\.com|gstatic\.com|googleapis\.com|addthis\.com|sharethis\.com|abr\.business\.gov\.au)$/i;
      const registerSite = async (p: { provider_id: string; name: string; trading: string | null }, code: string, codeRe: RegExp) => {
        const tried: unknown[] = []; let rto: string | null = null;
        for (const reg of REGISTERS) {
          if (!(await useFc("search", p.provider_id, `"${p.name}" site:${reg.site}`, true))) return { accepted: null, basis: null, register: null, rto, tried, budget: true };
          let regPage: string | null = null;
          try {
            const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: `"${p.name}" site:${reg.site}`, limit: wsNum("search_results_register", 5), country: "AU" }), signal: AbortSignal.timeout(45000) });
            const d = await r.json().catch(() => ({}));
            const urls: string[] = (d?.data?.web || d?.data || []).map((x: any) => String(x?.url || "")).filter(Boolean);
            regPage = urls.find((u) => reg.page.test(u)) || null;
            tried.push({ register: reg.key, results: urls.length, page: regPage });
          } catch (e) { tried.push({ register: reg.key, error: e instanceof Error ? e.message : String(e) }) }
          if (!regPage) continue;
          const m = regPage.match(/Details\/([0-9A-Za-z]+)/); if (reg.key === "training_gov_au" && m) rto = m[1];
          // the register page is rendered by script: read it through the scraper (1 credit), links only
          if (!(await useFc("site_verify", p.provider_id, regPage, true))) return { accepted: null, basis: null, register: reg.key, rto, tried, budget: true };
          let links: string[] = [], text = "";
          try {
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: regPage, formats: ["links", "markdown"], onlyMainContent: true, waitFor: 2500, location: { country: "AU" } }), signal: AbortSignal.timeout(60000) });
            const d = await r.json().catch(() => ({}));
            links = (d?.data?.links || []).map(String); text = String(d?.data?.markdown || "");
          } catch (e) { tried.push({ register: reg.key, page: regPage, error: e instanceof Error ? e.message : String(e) }); continue }
          // the register must be about this provider: its CRICOS code or its name on the page
          const about = codeRe.test(text) || siteNorm(text).includes(siteNorm(p.name)) || (p.trading ? siteNorm(text).includes(siteNorm(p.trading)) : false);
          const hosts: string[] = [];
          for (const l of links) { let u: URL; try { u = new URL(l) } catch { continue } const h = u.hostname.toLowerCase().replace(/^www\./, ""); if (!/^https?:$/.test(u.protocol) || NOT_OWN.test(h) || SKIP.test(h) || hosts.includes(h)) continue; hosts.push(h) }
          tried.push({ register: reg.key, page: regPage, about, listed: hosts.slice(0, 5) });
          if (!about) continue;
          let soleOk: string | null = null;
          for (const h of hosts.slice(0, 3)) {
            const origin = "https://" + h + "/";
            try {
              const res = await fetch(origin, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) });
              let html = res.ok ? await res.text() : "", finalUrl = res.url || origin;
              if (!html || [401, 403, 429, 503].includes(res.status)) { const sc = await viaScraper(p.provider_id, origin, "AU"); if (sc) { html = sc.html; finalUrl = sc.finalUrl } }
              let fh = h; try { fh = new URL(finalUrl).hostname.toLowerCase() } catch { /* keep */ }
              if (SKIP.test(fh)) { tried.push({ register: reg.key, site: origin, refused: "directory" }); continue }
              const codeOn = codeRe.test(htmlToText(html)), fits = domainFitsName(fh, siteNorm(p.name)) || (p.trading ? domainFitsName(fh, siteNorm(p.trading)) : false);
              tried.push({ register: reg.key, site: origin, http: res.status, code_on_home: codeOn, name_fits: fits });
              if (codeOn || fits) return { accepted: new URL(finalUrl).origin, basis: `register_${reg.key}_${codeOn ? "code" : "name"}`, register: reg.key, rto, tried, budget: false };
              if (hosts.length === 1 && html.length > 500 && !SKIP.test(fh)) soleOk = new URL(finalUrl).origin;
            } catch { tried.push({ register: reg.key, site: origin, error: true }) }
          }
          // v0.21.6: the register's page is about this provider (its CRICOS code or name on it) and lists exactly one website, which answers:
          // the register is the official record, so its one listed website is accepted (ANE College: training.gov.au lists ane.edu.au)
          if (soleOk) return { accepted: soleOk, basis: `register_${reg.key}_listed`, register: reg.key, rto, tried, budget: false };
        }
        return { accepted: null, basis: null, register: null, rto, tried, budget: false };
      };
      await pool(provs, 3, async (p) => {
        const cc = String(p.country || "AU").toUpperCase();
        const code = String(p.cricos || "").toUpperCase();
        if (cc !== "AU" || code.length < 5) { out.push(await findCanadianSite(p, cc)); return }
        if (code.length < 5) { await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "no CRICOS provider code to check a site against", worker: WORKER } }); out.push({ provider_id: p.provider_id, status: "no_code" }); return }
        const codeRe = new RegExp("(^|[^0-9A-Z])" + code.split("").join("\\s?") + "([^0-9A-Z]|$)", "i");
        // v0.21.6 (13 Oct 2026, Platform Admin: "learn and establish how best to find the uni official website; directory sites never
        // give the provider website, don't search them for it; use training.gov.au or ASQA, CRICOS/RTO code; flag the exceptions"):
        // the official registers come first. A provider with no website in the CRICOS register is looked up on training.gov.au (the
        // national register of RTOs, which ASQA regulates) and then on the TEQSA National Register (higher education); the website the
        // register lists is accepted only when its home page shows the provider's CRICOS code or its address fits the provider's name.
        // Then the CRICOS-code search as before. Directories are never searched or accepted (svc_fc_spend refuses them too).
        const regFind = await registerSite(p, code, codeRe);
        if (regFind.accepted) {
          await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: regFind.accepted, p_evidence: { register: regFind.register, rto: regFind.rto, tried: regFind.tried, accepted: regFind.accepted, basis: regFind.basis, worker: WORKER } });
          out.push({ provider_id: p.provider_id, status: "found", website: regFind.accepted, basis: regFind.basis }); return;
        }
        if (regFind.budget) { out.push({ provider_id: p.provider_id, status: "budget" }); await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "Firecrawl budget reserve reached", tried: regFind.tried } }); return }
        if (!(await useFc("search", p.provider_id, p.name, true))) { out.push({ provider_id: p.provider_id, status: "budget" }); await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: null, p_evidence: { note: "Firecrawl budget reserve reached" } }); return }
        let accepted: string | null = null; const tried: unknown[] = [...regFind.tried];
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: `${p.name} CRICOS ${code}`, limit: wsNum("search_results_cricos", 8), country: "AU" }), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({}));
          const results = (d?.data?.web || d?.data || []).map((x: any) => ({ url: x.url, title: x.title })).filter((x: any) => typeof x.url === "string");
          const seenHosts = new Set<string>();
          for (const res of results) {
            let u: URL; try { u = new URL(res.url) } catch { continue }
            if (SKIP.test(u.hostname) || seenHosts.has(u.hostname)) continue; seenHosts.add(u.hostname);
            for (const page of [u.origin + "/", res.url]) {
              try {
                const h = await fetch(page, { headers: { "user-agent": UA }, redirect: "follow", signal: AbortSignal.timeout(15000) });
                let html = h.ok ? await h.text() : "";
                if (!html || [401, 403, 429, 503].includes(h.status)) { const sc = await viaScraper(p.provider_id, page, "AU"); if (sc) html = sc.html }
                const found = codeRe.test(htmlToText(html));
                // v0.17.32: the code on the site's home page, or on a deeper page when the address fits the provider's name
                let finalHost = u.hostname.toLowerCase(); try { finalHost = new URL(h.url || page).hostname.toLowerCase() } catch { /* keep */ }
                const home = page === u.origin + "/", fits = domainFitsName(finalHost, siteNorm(p.name)) || (p.trading ? domainFitsName(finalHost, siteNorm(p.trading)) : false)
                const ok = found && (home || fits) && !SKIP.test(finalHost);
                tried.push({ page, http: h.status, code_found: found, home, name_fits: fits });
                if (ok) { accepted = new URL(h.url || page).origin; break }
              } catch { tried.push({ page, error: true }) }
            }
            if (accepted || seenHosts.size >= 4) break;
          }
        } catch (e) { tried.push({ error: e instanceof Error ? e.message : String(e) }) }
        await rpc("svc_coverage_site_record", { p_provider_id: p.provider_id, p_website: accepted, p_evidence: { query: `${p.name} CRICOS ${code}`, tried, accepted, rto: regFind.rto, ...(accepted ? { basis: "cricos_code" } : {}), worker: WORKER } });
        out.push({ provider_id: p.provider_id, status: accepted ? "found" : "not_found", website: accepted });
      });
      return j({ ok: true, mode, providers: out, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    // v0.7.0: scholarship sweep. Each active scholarship's own provider page is read (robots.txt respected; Firecrawl
    // only when a direct read is refused or script-only), kept as gzipped evidence, and deterministic facts are recorded.
    if (mode === "scholarship_read") {
      const items: { scholarship_id: string; url: string; name: string; provider_id: string; currency?: string; url_source?: string; names?: string[] }[] = await rpc("svc_scholarship_read_next", { p_limit: Math.min(Number(body.limit || 20), wsNum("scholarship.read_max", 40)) });
      const tally: Record<string, number> = {}; const applied: unknown[] = [];
      // v0.17.42: pages are read six at a time but recorded at most two at a time (each record rebuilds course links and takes
      // 1-2 seconds; six at once pushed some past the database's 8-second limit)
      let recSlots = 2; const recWait: (() => void)[] = [];
      const recLock = async () => { if (recSlots > 0) { recSlots--; return } await new Promise<void>((ok) => recWait.push(ok)) };
      const recUnlock = () => { const n = recWait.shift(); if (n) n(); else recSlots++ };
      await pool(items, 6, async (it) => {
        // v0.17.40: an item not started in time stays leased and is picked again after the lease (10 minutes)
        if (Date.now() - t0 > BUDGET_MS - 30000) { tally.deferred = (tally.deferred || 0) + 1; return }
        const pg = await readSchPage(it.url, it.provider_id);  // v0.58.0: award sections and redirected-away pages (F5, F7)
        let status = pg.status, http: number | null = pg.http, via: string | null = pg.via, finalUrl = pg.finalUrl || it.url;
        const html = pg.status === "read" ? pg.html : "";
        let path: string | null = null, sha: string | null = null, facts: unknown = null;
        // v0.4.0: the page must name the scholarship before anything from it is used
        const hd = status === "read" ? pageHeadings(html) : null;
        const nc = hd ? { ...nameOnPage(it.name, hd.primary, providerTokens(it.names || []), hd.secondary), headings: hd, extractor: SCH_VERSION } : null;
        if (status === "read" && !nc!.ok) { status = "name_mismatch"; facts = { name_check: nc, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl } }
        // a discovered page must be about a scholarship (a research-project page can carry the same title)
        if (status === "read" && it.url_source === "discovered" && !/(scholarship|stipend|bursary|tuition|\baward|\bgrant|\bprize|fee (?:reduction|remission|discount|waiver))/i.test(mainText(html).slice(0, 8000))) {
          status = "name_mismatch"; facts = { name_check: { ...nc, ok: false, basis: "not_a_scholarship_page" }, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl };
        }
        if (status === "read") {
          const t = titleOf(html) + " " + h1Of(html);
          facts = { ...scholarshipFacts(html, t, it.name, it.currency || "AUD"), page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl, extractor: SCH_VERSION, name_check: nc };
          if (it.url_source === "admitted") { let h = ""; try { h = new URL(it.url).hostname } catch { /* */ } (facts as any).admission = admissionCheck(html, finalUrl, [h, new URL(finalUrl).hostname]) }
          const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
          path = `layer2/AU/scholarships/${it.provider_id}/${it.scholarship_id}/${sha}.html.gz`;
          const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
          if (up.error) { path = null; sha = null }
        }
        // v0.17.41: a record that hits the database time limit is tried once more; if it fails again the page stays leased and
        // is read again after the lease, and the rest of the run carries on (one slow record no longer fails the whole call)
        const recArgs = { p_scholarship_id: it.scholarship_id, p_read_status: status, p_http_status: http, p_fetched_via: via, p_final_url: finalUrl, p_storage_path: path, p_sha256: sha, p_facts: facts };
        let res: any = null;
        await recLock();
        try {
          try { res = await rpc("svc_scholarship_read_record", recArgs) }
          catch { await new Promise((ok) => setTimeout(ok, 1500)); try { res = await rpc("svc_scholarship_read_record", recArgs) } catch { tally.record_failed = (tally.record_failed || 0) + 1; return } }
        } finally { recUnlock() }
        if (res?.changes?.length) applied.push({ scholarship_id: it.scholarship_id, changes: res.changes });
        tally[status] = (tally[status] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, applied, readVia: "scraper", firecrawlRemainingAboveReserve: fcRemaining, scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER, scholarshipExtractor: SCH_VERSION });
    }
    // 1 Oct 2026 (Decision 204): course-link search runs here, a bounded number at a time, instead of through the
    // database's outbound queue (pg_net), which sends in rounds of 200 and waits for the slowest call. Each result is
    // recorded through public.svc_course_link_search_record (same pick, bind and title-search rules as before).
    if (mode === "link_search") {
      const items: { course_id: string; provider_id: string; stage: string; query: string }[] =
        await rpc("svc_course_link_search_next", { p_limit: Math.min(Number(body.limit || 40), 120) });
      let searched = 0, found = 0, failed = 0;
      // v0.59.5 (workstream F; reading.link_search_share_on, ships off): one paid search per distinct query, its answer recorded for every course
      // row with that query; an earlier answer for the same query inside the lookback window is recorded again with no new search (link-share.ts)
      if (linkSearchShareOn(ws)) {
        const groups = linkSearchGroups(items);
        const prior: Record<string, string[]> = (await rpc("svc_course_link_search_prior_v1", { p_queries: groups.map((g) => g.key) }).catch(() => null)) || {};
        let reused = 0, shared = 0;
        const recordAll = async (g: { items: typeof items }, http: number, urls: string[], err: string | null) => {
          for (const it of g.items) if (await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: http, p_urls: urls, p_error: err }) === "found") found++;
        };
        await pool(groups, Math.min(Number(body.concurrency || 6), 10), async (g) => {
          if (Array.isArray(prior[g.key])) { reused += g.items.length; await recordAll(g, 200, prior[g.key].map(String), null); return }
          if (Date.now() - t0 > BUDGET_MS) { await recordAll(g, 0, [], "time budget"); return }
          const g0 = g.items[0];
          { const u = await useFcWhy("course_link_search", g0.provider_id, g.query);
            if (!u.ok) { await recordAll(g, 0, [], u.why === "target_list_refused" ? "target_list_refused" : "credit budget"); return } }
          let http = 0, urls: string[] = [], err: string | null = null;
          try {
            const r = await fetch("https://api.firecrawl.dev/v1/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: g.query, limit: wsNum("search_results_scholarship_search", 5) }), signal: AbortSignal.timeout(45000) });  // fixed: API time-out
            http = r.status;
            const d = await r.json().catch(() => ({}));
            urls = Array.isArray(d?.data) ? d.data.map((x: { url?: string }) => String(x?.url || "")).filter(Boolean) : [];
            if (!r.ok) err = String(d?.error || `HTTP ${r.status}`);
          } catch (e) { err = e instanceof Error ? e.message : String(e) }
          searched++; if (err) failed++; shared += g.items.length - 1;
          await recordAll(g, http, urls, err);
        });
        return j({ ok: true, mode, workerVersion: VERSION, worker: WORKER, picked: items.length, queries: groups.length, searched, reused, shared, found, failed, ms: Date.now() - t0 });
      }
      await pool(items, Math.min(Number(body.concurrency || 6), 10), async (it) => {
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: 0, p_urls: [], p_error: "time budget" }); return }
        { const g = await useFcWhy("course_link_search", it.provider_id, it.query);
          // a real budget stop re-queues without an attempt ("credit budget"); a target-list refusal is named and counted, never looped
          if (!g.ok) { await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: 0, p_urls: [], p_error: g.why === "target_list_refused" ? "target_list_refused" : "credit budget" }); return } }
        let http = 0, urls: string[] = [], err: string | null = null;
        try {
          const r = await fetch("https://api.firecrawl.dev/v1/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: it.query, limit: wsNum("search_results_scholarship_search", 5) }), signal: AbortSignal.timeout(45000) });
          http = r.status;
          const d = await r.json().catch(() => ({}));
          urls = Array.isArray(d?.data) ? d.data.map((x: { url?: string }) => String(x?.url || "")).filter(Boolean) : [];
          if (!r.ok) err = String(d?.error || `HTTP ${r.status}`);
        } catch (e) { err = e instanceof Error ? e.message : String(e) }
        searched++; if (err) failed++;
        if (await rpc("svc_course_link_search_record", { p_course_id: it.course_id, p_http: http, p_urls: urls, p_error: err }) === "found") found++;
      });
      return j({ ok: true, mode, workerVersion: VERSION, picked: items.length, searched, found, failed, ms: Date.now() - t0 });
    }

    // 1 Oct 2026 (Decision 205): institution-level sources. Search each provider's site for its international fee schedule,
    // English language policy and academic calendar; read each document (PDFs included) as evidence; parse fee rows.
    // Nothing is written to the catalogue here: parsed rows become a proposal a person approves.
    // Decision 227: stored provider documents, parsed again without reading the site (no Firecrawl credit).
    // provider_facts_inspect returns the stored text (or the lines that match "lines") and what the parser makes of it;
    // provider_facts_parse records the parser's proposal for each document.
    // v0.27.0 (17 Oct 2026, CF-247 R18): tests the parser has learnt since a university's English policy was approved (first the Duolingo
    // English Test) are added from the policy's own stored page. The database adds a test for a level only where this reading's IELTS for
    // the level equals the approved IELTS, and only to courses that hold that policy's level default. No Firecrawl, no AI. A page that
    // cannot be read is recorded as checked with its error, so it is not tried again until the parser changes.
    // v0.29.0 (Decision 265, Platform Admin 18 Oct 2026 "Yes, build and read"): companion pages. A university may keep a course fact on a page
    // beside the course page (Melbourne: the English level on "Entry and participation requirements"). Due pages are read directly or through the
    // scraper as set for the university (pipeline.uni_adapter_companions), a copy is kept in the evidence bucket and the university's patterns are
    // read on the page text. Nothing is written to courses here: security.english_level_apply_v1 uses the values with the approved policy.
    if (mode === "companion_read") {
      const items: { course_id: string; provider_id: string; url: string; via: string; patterns: Record<string, string>; code: string; country: string }[] =
        await rpc("svc_companion_next", { p_limit: Math.min(Number(body.limit || 40), 200) }) || [];
      const tally: Record<string, number> = {};
      await pool(items, 3, async (it) => {
        let st = "failed", http: number | null = null, html = "", via: string | null = null;
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_companion_record", { p_course_id: it.course_id, p_status: "waiting_scraper", p_http: null, p_via: null, p_path: null, p_sha: null, p_values: null }).catch(() => null); return }
        if (it.via !== "scraper") {
          const d = await readDirect(it.url); st = d.status; http = d.http; via = "direct";
          html = d.html && !/Pardon Our Interruption|Just a moment\.\.\./i.test(d.html) ? d.html : "";
          if (d.html && !html) st = "blocked";
        }
        if (!html && it.via !== "direct") {
          if (await useFc("companion_read", it.provider_id, it.url)) {
            via = "firecrawl";
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 1500, timeout: 30000 }), signal: AbortSignal.timeout(45000) }).catch(() => null);
            const d = r ? await r.json().catch(() => ({})) : {};
            http = Number(d?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
            html = r?.ok && http !== null && http < 400 ? pageHtml(d) : "";
            st = html ? "read" : http === 404 || http === 410 ? "gone" : http && [401, 403, 406, 429].includes(http) ? "blocked" : "failed";
          } else if (!html) st = "waiting_scraper";
        }
        let path: string | null = null, sha: string | null = null; const values: Record<string, string> = {};
        if (html) {
          const text = htmlToText(html);
          if (text.length < 200) st = "too_thin";
          else {
            st = "read";
            sha = await sha256(new TextEncoder().encode(html));
            path = `layer2/${it.country || "XX"}/companion/${it.provider_id}/${it.course_id}/${sha}.html.gz`;
            const up = await c.storage.from("evidence").upload(path, await gzip(html), { contentType: "application/gzip", upsert: true });
            if (up.error) path = null;
            const pv = patternValues({ patterns: it.patterns || {} }, text, it.code || "");
            for (const f of Object.keys(it.patterns || {})) if (pv[f]) values[f] = pv[f].slice(0, 300);
          }
        }
        await rpc("svc_companion_record", { p_course_id: it.course_id, p_status: st, p_http: http, p_via: via, p_path: path, p_sha: sha, p_values: values }).catch(() => null);
        tally[st] = (tally[st] || 0) + 1; if (Object.keys(values).length) tally.with_values = (tally.with_values || 0) + 1;
      });
      return j({ ok: true, mode, workerVersion: WORKER, pages: items.length, tally, ms: Date.now() - t0 });
    }

    // v0.37.0 (22 Oct 2026, Platform Admin 16:30 "Course list page per provider"): a provider's own course list or course finder page, entered
    // by a person, is read for its course links (in any language: the link text is the course name as the site writes it). Read directly
    // first; through the scraper when the direct read finds too few links (pages drawn by the browser). Follows the list's own next pages up
    // to the set number. The database adds the links to the provider's site addresses, where the page matcher and the AI page match use them.
    // v0.38.0 (22 Oct 2026): the credential a course page states, from the stored page (no fetch, no AI). The database gives the rows and
    // the patterns (pipeline.credential_rules, capture group 1 is the credential) and decides the study level from what is found.
    if (mode === "credential_read") {
      const next: { rows: { course_id: string; evidence_id: string; storage_path: string }[]; rules: { id: number; kind: string; regex: string }[] } =
        await rpc("svc_credential_next", { p_limit: Math.min(Number(body.limit || 50), 200) });
      const rules = (next?.rules || []).flatMap((r) => { try { return [{ ...r, re: new RegExp(r.regex, "gi") }] } catch { return [] } });
      let done = 0, failed = 0; const errors: string[] = [];
      await pool(next?.rows || [], 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = htmlToText(html).replace(/\s+/g, " ");
          const found: { rule: number; kind: string; text: string }[] = [];
          for (const rule of rules) {
            rule.re.lastIndex = 0; const seen = new Set<string>();
            for (const m of text.matchAll(rule.re)) {
              const t = String(m[1] || "").trim().slice(0, 120);
              if (t && !seen.has(t.toLowerCase())) { seen.add(t.toLowerCase()); found.push({ rule: rule.id, kind: rule.kind, text: t }) }
              if (seen.size >= 5) break; // fixed: a page lists only a few credentials of its own
            }
          }
          await rpc("svc_credential_record", { p_course_id: r.course_id, p_evidence_id: r.evidence_id, p_found: found }); done++;
        } catch (e) {
          failed++; if (errors.length < 3) errors.push(e instanceof Error ? e.message : String(e));
          await rpc("svc_credential_record", { p_course_id: r.course_id, p_evidence_id: r.evidence_id, p_found: null }).catch(() => null);
        }
      });
      return j({ ok: true, mode, rows: (next?.rows || []).length, done, failed, errors, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "course_list_read") {
      const items: { id: string; provider_id: string; url: string; max_pages: number; min_links: number; link_pattern?: string | null; child_pattern?: string | null; read_via?: string | null }[] =
        await rpc("svc_course_list_next", { p_limit: Math.min(Number(body.limit || 5), 50) }) || [];
      const tally: Record<string, number> = {};
      const linksOf = (html: string, base: string) => {
        const out: { url: string; title: string }[] = []; const seen = new Set<string>();
        let host = ""; try { host = new URL(base).hostname.replace(/^www\./, "") } catch { return out }
        const root = host.split(".").slice(-3).join(".");
        for (const m of html.matchAll(/<a\b[^>]*?href\s*=\s*["']([^"'#]+)[^"']*["'][^>]*>([\s\S]*?)<\/a>/gi)) {
          let u: URL; try { u = new URL(m[1].replace(/&amp;/g, "&"), base) } catch { continue }
          if (!/^https?:$/.test(u.protocol)) continue;
          const h = u.hostname.replace(/^www\./, ""); if (!(h === host || h.endsWith("." + root) || h === root)) continue;
          if (/\.(pdf|jpe?g|png|gif|svg|docx?|xlsx?|zip|mp4)$/i.test(u.pathname)) continue;
          u.hash = ""; const key = u.toString().replace(/\/$/, ""); const title = htmlToText(m[2]).slice(0, 200);
          if (seen.has(key) || title.length < 3) continue; seen.add(key); out.push({ url: key, title });
          if (out.length >= 3000) break;  // fixed: one list page's link cap
        }
        return out;
      };
      const nextPages = (html: string, base: string, done: Set<string>) => {
        const pages: string[] = [];
        for (const m of html.matchAll(/<a\b[^>]*?href\s*=\s*["']([^"'#]+)["'][^>]*>/gi)) {
          let u: URL; try { u = new URL(m[1].replace(/&amp;/g, "&"), base) } catch { continue }
          if (/[?&](page|pg|p|start|offset)=\d+/i.test(u.search) || /\/page\/\d+\/?$/i.test(u.pathname)) {
            const k = u.toString(); if (!done.has(k) && new URL(base).hostname === u.hostname) { done.add(k); pages.push(k) }
          }
        }
        return pages;
      };
      // v0.37.1 (first live read, Waikato): a list drawn by the browser gave only the site menu by a direct read. Course links are the ones
      // under the list page's own folder (waikato.ac.nz/study/qualifications/...); too few of those means the scraper is used, and when the
      // page has enough of them only they are kept (not the menu).
      const folder = (url: string) => { try { const u = new URL(url); return u.origin + u.pathname.replace(/[^/]*\.[a-z0-9]+$/i, "").replace(/\/?$/, "/") } catch { return url } };
      const under = (links: { url: string; title: string }[], url: string) => { const f = folder(url); return links.filter((l) => l.url.startsWith(f) && l.url.length > f.length) };
      const read = async (url: string, providerId: string, minLinks: number) => {
        const d = await readDirect(url);
        let html = d.html && !/Pardon Our Interruption|Just a moment\.\.\./i.test(d.html) ? d.html : "", via = "direct", http = d.http;
        if ((!html || under(linksOf(html, url), url).length < minLinks) && await useFc("list_scrape", providerId, url)) {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 3000, timeout: 45000 }), signal: AbortSignal.timeout(60000) }).catch(() => null);
          const j2 = r ? await r.json().catch(() => ({})) : {};
          const code = Number(j2?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
          const h2 = r?.ok && code !== null && code < 400 ? pageHtml(j2) : "";
          if (h2 && under(linksOf(h2, url), url).length >= under(linksOf(html, url), url).length) { html = h2; via = "firecrawl"; http = code }
        }
        return { html, via, http, status: d.status };
      };
      await pool(items, 2, async (it) => {
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_course_list_record", { p_id: it.id, p_status: "due", p_http: null, p_via: null, p_links: null, p_pages: 0 }).catch(() => null); return }
        // v0.39.0 (22 Oct 2026): a course list given as a site map with an address pattern (search-app course finders give no links):
        // every page address that fits the pattern is kept, titled from its last address part; index files are followed by child_pattern
        if (it.link_pattern && it.read_via === "map") {
          let re: RegExp; try { re = new RegExp(it.link_pattern, "i") } catch { await rpc("svc_course_list_record", { p_id: it.id, p_status: "failed", p_http: null, p_via: "map", p_links: null, p_pages: 0 }).catch(() => null); return }
          const m = await fcMap(it.url, it.provider_id);
          if (!m) { await rpc("svc_course_list_record", { p_id: it.id, p_status: "due", p_http: null, p_via: null, p_links: null, p_pages: 0 }).catch(() => null); tally.waiting = (tally.waiting || 0) + 1; return }
          const links = new Map<string, string>(); for (const l of m.links) if (re.test(l.url) && links.size < 3000) links.set(l.url.replace(/\/$/, ""), l.title || decodeURIComponent(l.url.replace(/\/$/, "").split("/").pop() || "").replace(/[-_]+/g, " "));  // fixed: one list's link cap
          const st = m.ok ? "read" : "failed";
          await rpc("svc_course_list_record", { p_id: it.id, p_status: st, p_http: m.status, p_via: "map", p_links: [...links].map(([url, title]) => ({ url, title })), p_pages: 1 }).catch(() => null);
          tally[st] = (tally[st] || 0) + 1; tally.links = (tally.links || 0) + links.size; return;
        }
        if (it.link_pattern) {
          let re: RegExp, cre: RegExp | null = null;
          try { re = new RegExp(it.link_pattern, "i"); cre = it.child_pattern ? new RegExp(it.child_pattern, "i") : null } catch { await rpc("svc_course_list_record", { p_id: it.id, p_status: "failed", p_http: null, p_via: null, p_links: null, p_pages: 0 }).catch(() => null); return }
          const links = new Map<string, string>(); const queue = [it.url], seen = new Set<string>(); let files = 0, http: number | null = null, st = "failed";
          while (queue.length && files < 25 && Date.now() - t0 < BUDGET_MS) {  // fixed: a site map index lists a handful of files
            const u = queue.shift() as string; if (seen.has(u)) continue; seen.add(u);
            let text = "", code: number | null = null, ok = false;
            try { const uu = new URL(u); if (robotsAllows(await robotsFor(uu), uu.pathname + uu.search)) { const r = await fetch(uu, { headers: { "user-agent": UA, accept: "application/xml,text/xml;q=0.9,*/*;q=0.8" }, redirect: "follow", signal: AbortSignal.timeout(30000) }); code = r.status; ok = r.ok; text = r.ok ? await r.text() : (await r.body?.cancel(), "") } } catch { /* failed below */ }
            if (files === 0) { http = code; st = ok ? "read" : code && [401, 403, 406, 429].includes(code) ? "blocked" : code === 404 || code === 410 ? "gone" : "failed" }
            if (!text) { if (files === 0) break; continue }
            files++; st = "read";
            const locs = [...text.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/gi)].map((m) => m[1].replace(/&amp;/g, "&"));
            if (/<sitemapindex/i.test(text)) { for (const l of locs) if (!cre || cre.test(l)) queue.push(l) }
            else for (const l of locs) if (re.test(l) && links.size < 3000) {  // fixed: one list's link cap, as for list pages
              const key = l.replace(/\/$/, ""); const last = decodeURIComponent(key.split("/").pop() || "").replace(/\.[a-z0-9]+$/i, "");
              links.set(key, last.replace(/[-_]+/g, " ").trim().slice(0, 200));
            }
          }
          await rpc("svc_course_list_record", { p_id: it.id, p_status: st, p_http: http, p_via: "sitemap", p_links: [...links].map(([url, title]) => ({ url, title })), p_pages: files }).catch(() => null);
          tally[st] = (tally[st] || 0) + 1; tally.links = (tally.links || 0) + links.size; return;
        }
        const done = new Set<string>([it.url]); const links = new Map<string, string>(); let pagesRead = 0, via: string | null = null, http: number | null = null, st = "failed";
        const queue = [it.url];
        while (queue.length && pagesRead < Math.max(1, it.max_pages) && Date.now() - t0 < BUDGET_MS) {
          const u = queue.shift() as string; const r = await read(u, it.provider_id, it.min_links);
          if (pagesRead === 0) { via = r.via; http = r.http }
          if (!r.html) { if (pagesRead === 0) st = r.status === "blocked" || r.status === "robots_disallowed" ? "blocked" : r.status === "gone" ? "gone" : "failed"; break }
          pagesRead++; st = "read";
          const all = linksOf(r.html, u), course = under(all, it.url), before = links.size;
          for (const l of (course.length >= Math.min(5, it.min_links) ? course : all)) if (!links.has(l.url)) links.set(l.url, l.title);
          const nx = nextPages(r.html, u, done);
          // v0.37.2 (Waikato): next-page buttons drawn by the browser have no links; try the next page number in the address while each
          // page still adds course links
          if (!nx.length && links.size > before) { try { const n = new URL(u); const pg = Number(n.searchParams.get("page") || "1"); n.searchParams.set("page", String(pg + 1)); const k = n.toString(); if (!done.has(k)) { done.add(k); nx.push(k) } } catch { /* not a list address */ } }
          queue.push(...nx);
        }
        await rpc("svc_course_list_record", { p_id: it.id, p_status: st, p_http: http, p_via: via, p_links: [...links].map(([url, title]) => ({ url, title })), p_pages: pagesRead }).catch(() => null);
        tally[st] = (tally[st] || 0) + 1; tally.links = (tally.links || 0) + links.size;
      });
      return j({ ok: true, mode, workerVersion: WORKER, lists: items.length, read: tally.read || 0, items: items.length, tally, ms: Date.now() - t0 });  // v0.40.5: read and items for the idle guard
    }

    if (mode === "source_find") {
      // v0.40.2 (23 Oct 2026, test runs): one step per university per call, carried over between runs (pipeline.source_find_runs.step and
      // .work): map (learn the pattern, home page study sites, Firecrawl map), map_search, sitemap, lists. No step can use up the call.
      const next: { items: { provider_id: string; name: string; website: string; known: string[]; step: string | null; work: any; tried: any[] | null }[];
        list_paths: string[]; folder_words: string[]; settings: { min_links: number; min_recall: number; max_files: number; max_locs: number; max_list_tries: number } } =
        await rpc("svc_source_find_next", { p_limit: Math.min(Number(body.limit || 2), 10), p_provider_ids: Array.isArray(body.providers) ? body.providers : null });
      const S = next.settings;
      const STEP_MS = 55_000;  // fixed: one step must leave room for a second university and the records in one call
      const words = (next.folder_words || []).join("|") || "courses?|programmes?|programs?";
      const wordFile = new RegExp(`(${words})`, "i"), wordFolder = new RegExp(`^(${words})$`, "i");
      const esc = (x: string) => x.replace(/[.*+?^${}()|[\]\\\/]/g, "\\$&");
      const hostRe = (h: string) => `https?://(www\\.)?${esc(h.replace(/^www\./, ""))}`;
      const norm = (u: string) => u.replace(/^https?:\/\/(www\.)?/i, "").replace(/[?#].*$/, "").replace(/\/+$/, "").toLowerCase();
      const bare = (h: string) => h.replace(/^www\./, "");
      const getText = async (url: string) => {
        try {
          const u = new URL(url);
          if (!url.endsWith("/robots.txt") && !robotsAllows(await robotsFor(u), u.pathname + u.search)) return { http: null as number | null, text: "" };
          const r = await fetch(u, { headers: { "user-agent": UA, accept: "application/xml,text/xml,text/plain,text/html;q=0.9,*/*;q=0.8" }, redirect: "follow", signal: AbortSignal.timeout(10000) });  // fixed: a site map or robots.txt answers quickly or not at all
          return { http: r.status, text: r.ok ? await r.text() : (await r.body?.cancel(), "") };
        } catch { return { http: null as number | null, text: "" } }
      };
      const locsOf = (xml: string) => [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/gi)].map((m) => m[1].replace(/&amp;/g, "&"));
      type Pat = { re: string; basis: string; folder: string; host: string };
      const LIST_WORDS = /^(find-?a-?(course|program(me)?|degree)s?|course-?(search|finder|list)|all-?(courses|programs|programmes|qualifications)|courses|programmes|programs|qualifications|study-options|explore-programs|degrees|a-z|az)$/i;
      // the largest course-named folder (one address part under it) among addresses, on any host
      const wordPattern = (urls: string[], where: string): Pat | null => {
        const c = new Map<string, number>();
        for (const l of urls) { try { const u = new URL(l); const h = bare(u.hostname); const sg = u.pathname.split("/").filter(Boolean); for (let i = 0; i < Math.min(sg.length - 1, 3); i++) if (wordFolder.test(sg[i]) && sg.length === i + 2) { const k = h + "|" + sg.slice(0, i + 1).join("/"); c.set(k, (c.get(k) || 0) + 1) } } catch { /* bad address */ } }
        const top = [...c].sort((a, b) => b[1] - a[1])[0]; if (!top) return null;
        const [h, f] = top[0].split("|");
        return { re: `^${hostRe(h)}/${f.split("/").map(esc).join("/")}/[^/?#]+/?$`, basis: `course-named folder /${f} on ${h} in the ${where}`, folder: f, host: h };
      };
      const tally: Record<string, number> = {};
      await pool(next.items || [], 2, async (it) => {
        const t1 = Date.now(); const left = () => STEP_MS - (Date.now() - t1);
        const tried: Record<string, unknown>[] = Array.isArray(it.tried) ? [...it.tried] : [];
        const work: any = it.step && it.work ? { ...it.work } : {};
        const test = body.test === true || work.test === true;
        const step = it.step || "map";
        try {
          const known = (it.known || []).flatMap((k) => { try { return [new URL(k)] } catch { return [] } });
          const kn = (h: string) => known.filter((u) => bare(u.hostname) === bare(h));
          const judge = (fit: Set<string>, h: string) => { const k = kn(h); const hit = k.filter((u) => fit.has(norm(u.toString()))).length; const recall = k.length >= 3 ? hit / k.length : null;
            // v0.40.3: a source with at least as many course addresses as known pages is a fuller list (Victoria University's known
            // pages are partly stale); with no known pages to check against, twice the minimum (Manitoba picked a 20-address folder)
            return { known: k.length, known_found: hit, recall, ok: recall === null ? fit.size >= S.min_links * 2 : fit.size >= S.min_links && (recall >= S.min_recall || fit.size >= k.length) } };
          let chosen: Record<string, unknown> | null = null;
          if (step === "map") {
            // hosts: those of the known course pages (most first), then the website; the study sites its home page links to when few are known
            const hosts = new Map<string, number>(), seenAs: Record<string, string> = {};
            for (const u of known) { const h = bare(u.hostname); hosts.set(h, (hosts.get(h) || 0) + 1); seenAs[h] = seenAs[h] || u.hostname }
            try { const wh = new URL(it.website).hostname; if (!hosts.has(bare(wh))) hosts.set(bare(wh), 0); seenAs[bare(wh)] = seenAs[bare(wh)] || wh } catch { /* no website */ }
            let hostList = [...hosts].sort((a, b) => b[1] - a[1]).slice(0, 2).map((x) => x[0]);  // fixed: the main course host and the website
            if (known.length < 3 && it.website) {
              const home = await getText(it.website); const wh = bare((() => { try { return new URL(it.website).hostname } catch { return "" } })());
              const root = wh.split(".").slice(-(/\.(ac|edu|co|com|org|gov)\.[a-z]{2}$/.test(wh) ? 3 : 2)).join(".");
              const sib = new Map<string, number>();
              for (const m of (home.text || "").matchAll(/<a\b[^>]*?href\s*=\s*["']([^"'#]+)["'][^>]*>([\s\S]*?)<\/a>/gi)) {
                try { const u = new URL(m[1], it.website); const h = bare(u.hostname); if (h === wh || !(h === root || h.endsWith("." + root))) continue;
                  if (/(admission|study|apply|future|programs?|programmes?|courses?|etudes|degrees?)/i.test(h + " " + u.pathname + " " + htmlToText(m[2]))) { sib.set(h, (sib.get(h) || 0) + 1); seenAs[h] = seenAs[h] || u.hostname } } catch { /* bad link */ }
              }
              for (const [h] of [...sib].sort((x, y) => x[1] - y[1]).slice(-2)) if (!hostList.includes(h)) hostList.unshift(h);  // fixed: two study sites at most, read first
              tried.push({ kind: "home", url: it.website, http: home.http, sibling_sites: [...sib].sort((x, y) => y[1] - x[1]).slice(0, 5) });
            }
            // the address pattern of the known course pages: the folder most share, and the depths they have (rare ones left out).
            // v0.40.7: up to three course folders (UNSW: /study/postgraduate and /study/undergraduate); each further folder must hold half
            // of the known pages still uncovered and at least a sixth of all of them
            let pattern: Pat | null = null;
            for (const host of hostList) {
              let segs = kn(host).map((u) => u.pathname.split("/").filter(Boolean)); const total = segs.length; if (total < 3) continue;
              const parts: { re: string; folder: string; n: number }[] = [];
              while (parts.length < 3 && segs.length >= 3) {  // fixed: three course folders at most
                let got: { k: string; pl: number; n: number; d: Map<number, number> } | null = null;
                for (let pl = 4; pl >= 1 && !got; pl--) {
                  const c = new Map<string, { n: number; d: Map<number, number> }>();
                  for (const sg of segs) if (sg.length > pl) { const k = sg.slice(0, pl).join("/"); const e = c.get(k) || { n: 0, d: new Map() }; e.n++; e.d.set(sg.length, (e.d.get(sg.length) || 0) + 1); c.set(k, e) }
                  const top = [...c].sort((a, b) => b[1].n - a[1].n)[0];
                  if (top && top[1].n >= segs.length * 0.5 && top[1].n >= Math.max(3, total / 6)) got = { k: top[0], pl, n: top[1].n, d: top[1].d };  // fixed: the folder most known pages share
                }
                if (!got) break;
                const g = got; const ds = [...g.d].filter(([, n]) => n >= g.n * 0.1).map(([dd]) => dd - g.pl); const lo = Math.min(...ds), hi = Math.max(...ds);
                parts.push({ re: `${g.k.split("/").map(esc).join("/")}(/[^/?#]+){${lo === hi ? lo : `${lo},${hi}`}}`, folder: g.k, n: g.n });
                segs = segs.filter((sg) => !(sg.length > g.pl && sg.slice(0, g.pl).join("/") === g.k));
              }
              if (!parts.length) continue;
              pattern = { re: `^${hostRe(host)}/(?:${parts.map((x) => x.re).join("|")})/?$`, basis: `known pages (${parts.reduce((a, x) => a + x.n, 0)} of ${total} under ${parts.map((x) => "/" + x.folder).join(", ")})`, folder: parts[0].folder, host };
              break;
            }
            // a Firecrawl map of each host (1 credit; every address with its title, sub-sites included)
            for (const host of hostList) {
              if (chosen || left() < 20_000) break;  // fixed: a map takes up to 20 seconds
              const origin = `https://${seenAs[host] || host}`;
              const mp = await fcMap(origin, it.provider_id);
              if (!mp) { tried.push({ kind: "map", url: origin, result: "Firecrawl budget refused" }); break }
              const pat = pattern || wordPattern(mp.links.map((l) => l.url), "Firecrawl map");
              if (!pat) { tried.push({ kind: "map", url: origin, http: mp.status, addresses: mp.links.length, result: "no course address pattern" }); continue }
              if (!pattern) pattern = pat;
              const re = new RegExp(pat.re, "i"); const fitL = mp.links.filter((l) => re.test(l.url)); const fit = new Set(fitL.map((l) => norm(l.url))); const jd = judge(fit, pat.host);
              tried.push({ kind: "map", url: origin, http: mp.status, addresses: mp.links.length, matches: fit.size, known: jd.known, known_found: jd.known_found, recall: jd.recall, result: jd.ok ? "kept" : fit.size < S.min_links ? "too few course addresses" : "holds too few known pages" });
              if (jd.ok) chosen = { kind: "map", url: new URL(fitL[0].url).origin, link_pattern: pat.re, matches: fit.size, recall: jd.recall };
              // v0.40.3: list pages the map names (find-a-course, course-search, all-courses, ...), tried first in the lists step, no extra cost
              for (const l of mp.links) { try { const u = new URL(l.url); const sg = u.pathname.split("/").filter(Boolean); if (sg.length && sg.length <= 4 && LIST_WORDS.test(sg[sg.length - 1].replace(/\.[a-z]+$/i, "")) && !(work.list_candidates || []).includes(l.url)) (work.list_candidates ||= []).push(l.url) } catch { /* bad address */ } }
            }
            work.list_candidates = (work.list_candidates || []).sort((a: string, b: string) => a.length - b.length).slice(0, 6);  // fixed: the shortest few list addresses the map names
            Object.assign(work, { hosts: hostList, seenAs, pattern });
          } else if (step === "map_search") {
            // a map searched for the course words (1 credit): sites whose map leaves out deep pages
            const pattern: Pat | null = work.pattern || null; const host = pattern?.host || (work.hosts || [])[0];
            const search = pattern ? (pattern.folder.split("/").pop() || "").replace(/[-_]+/g, " ") : String((next.folder_words || [])[1] || "programs").replace(/[?]/g, "");
            const origin = `https://${(work.seenAs || {})[host] || host}`;
            const mp = host ? await fcMap(origin, it.provider_id, search) : null;
            if (!mp) tried.push({ kind: "map", url: origin, search, result: host ? "Firecrawl budget refused" : "no site" });
            else {
              const pat = pattern || wordPattern(mp.links.map((l) => l.url), "searched Firecrawl map");
              if (!pat) tried.push({ kind: "map", url: origin, search, http: mp.status, addresses: mp.links.length, result: "no course address pattern" });
              else {
                if (!pattern) work.pattern = pat;
                const re = new RegExp(pat.re, "i"); const fitL = mp.links.filter((l) => re.test(l.url)); const fit = new Set(fitL.map((l) => norm(l.url))); const jd = judge(fit, pat.host);
                tried.push({ kind: "map", url: origin, search, http: mp.status, addresses: mp.links.length, matches: fit.size, known: jd.known, known_found: jd.known_found, recall: jd.recall, result: jd.ok ? "kept" : fit.size < S.min_links ? "too few course addresses" : "holds too few known pages" });
                if (jd.ok) chosen = { kind: "map", url: new URL(fitL[0].url).origin, link_pattern: pat.re, matches: fit.size, recall: jd.recall };
              }
            }
          } else if (step === "sitemap") {
            // robots.txt and the site maps it names (or /sitemap.xml), index files named like course files first
            for (const host of (work.hosts || []) as string[]) {
              if (chosen || left() < 12_000) break;  // fixed: room for one more site map read
              const origin = `https://${(work.seenAs || {})[host] || host}`;
              const robots = await getText(`${origin}/robots.txt`);
              if (robots.http === null) { tried.push({ kind: "sitemap", host, result: "site does not answer direct reads" }); continue }
              const starts = [...(robots.text || "").matchAll(/^\s*sitemap:\s*(\S+)/gim)].map((m) => m[1]);
              if (!starts.length) starts.push(`${origin}/sitemap.xml`, `${origin}/sitemap_index.xml`);
              const queue = [...new Set(starts)], seen = new Set<string>(), parentOf = new Map<string, string>(); const files: { url: string; locs: string[]; parent: string | null }[] = []; let total = 0;
              while (queue.length && files.length < S.max_files && total < S.max_locs && left() > 12_000) {
                const u = queue.shift() as string; if (seen.has(u)) continue; seen.add(u);
                const r = await getText(u); if (!/<(urlset|sitemapindex)/i.test(r.text)) { tried.push({ kind: "sitemap", url: u, http: r.http, result: "not a site map" }); continue }
                const ls = locsOf(r.text);
                if (/<sitemapindex/i.test(r.text)) { for (const l of ls) parentOf.set(l, u); queue.unshift(...ls.filter((l) => wordFile.test(l))); queue.push(...ls.filter((l) => !wordFile.test(l))); continue }
                files.push({ url: u, locs: ls, parent: parentOf.get(u) || null }); total += ls.length;
              }
              const all = files.flatMap((f) => f.locs);
              const pat: Pat | null = work.pattern || wordPattern(all, "site map");
              if (!pat) { tried.push({ kind: "sitemap", host, files: files.length, addresses: all.length, result: "no course address pattern" }); continue }
              if (!work.pattern) work.pattern = pat;
              const re = new RegExp(pat.re, "i");
              const fitFiles = files.map((f) => ({ ...f, fit: f.locs.filter((l) => re.test(l)) })).filter((f) => f.fit.length > 0);
              const fit = new Set(fitFiles.flatMap((f) => f.fit.map(norm))); const jd = judge(fit, pat.host);
              tried.push({ kind: "sitemap", host, files: files.length, addresses: all.length, matches: fit.size, known: jd.known, known_found: jd.known_found, recall: jd.recall, result: jd.ok ? "kept" : fit.size < S.min_links ? "too few course addresses" : "holds too few known pages" });
              if (jd.ok) {
                const parents = new Set(fitFiles.map((f) => f.parent));
                const url = fitFiles.length === 1 ? fitFiles[0].url : parents.size === 1 && [...parents][0] ? [...parents][0] as string : fitFiles[0].url;
                const child = fitFiles.length > 1 && parents.size === 1 && [...parents][0] ? `^(${fitFiles.map((f) => esc(f.url)).join("|")})$` : null;
                chosen = { kind: "sitemap", url, child_pattern: child, link_pattern: pat.re, matches: fit.size, recall: jd.recall };
              }
            }
          } else {
            // the course folder itself and the usual list addresses (the scraper when a page is drawn by the browser, within the budget)
            const pattern: Pat | null = work.pattern || null; const host = pattern?.host || (work.hosts || [])[0];
            const origin = `https://${(work.seenAs || {})[host] || host}`;
            const re = pattern ? new RegExp(pattern.re, "i") : null;
            // v0.40.3: list pages the map named first, then the course folder and the folder without its first part (Waikato's known pages
            // were the international view /int/study/qualifications; its list is /study/qualifications), then the usual addresses
            const relaxed = pattern && pattern.folder.split("/").length > 1 ? [`${origin}/${pattern.folder.split("/").slice(1).join("/")}/`] : [];
            const tries = [...new Set([...(work.list_candidates || []), ...(pattern ? [`${origin}/${pattern.folder}/`] : []), ...relaxed, ...(next.list_paths || []).map((pth) => `${origin}${pth}`)])].slice(0, S.max_list_tries + (work.list_candidates || []).length);
            const tested = new Set(tried.filter((t) => t.kind === "list").map((t) => String(t.url)));
            let best: { url: string; n: number; via: string } | null = null;
            for (const url of tries) {
              if (tested.has(url)) continue; if (left() < 45_000) break;  // fixed: a list page read with the scraper takes up to 45 seconds
              const d = await readDirect(url); let via = "direct";
              const count = (h: string) => { const set = new Set<string>(); for (const m of h.matchAll(/<a\b[^>]*?href\s*=\s*["']([^"'#]+)["']/gi)) { try { const u = new URL(m[1].replace(/&amp;/g, "&"), url); const k = u.toString(); if (re ? re.test(k) : (bare(u.hostname) === bare(host) && u.pathname.split("/").filter(Boolean).some((x) => wordFolder.test(x)) && u.pathname.split("/").filter(Boolean).length >= 2)) set.add(norm(k)) } catch { /* bad link */ } } return set.size };
              let n = d.html ? count(d.html) : 0;
              if (n < S.min_links && ["read", "too_thin", "blocked"].includes(d.status) && await useFc("list_scrape", it.provider_id, url)) {
                const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 3000, timeout: 40000 }), signal: AbortSignal.timeout(45000) }).catch(() => null);
                const j2 = r ? await r.json().catch(() => ({})) : {}; const code = Number(j2?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
                const h2 = r?.ok && code !== null && code < 400 ? pageHtml(j2) : ""; const n2 = h2 ? count(h2) : 0;
                if (n2 > n) { n = n2; via = "firecrawl" }
              }
              tried.push({ kind: "list", url, http: d.http, status: d.status, via, matches: n });
              if (!best || n > best.n) best = { url, n, via };
              if (n >= S.min_links * 5) break;  // fixed: a clearly good list page ends the search
            }
            // list pages tried in earlier calls count too
            for (const t of tried) if (t.kind === "list" && Number(t.matches || 0) > (best?.n || 0)) best = { url: String(t.url), n: Number(t.matches), via: String(t.via || "direct") };
            if (best && best.n >= S.min_links) chosen = { kind: "list", url: best.url, link_pattern: pattern?.re || null, matches: best.n, via: best.via };
            // list addresses not reached yet: this step again
            else if (tries.some((u) => !tried.some((t) => t.kind === "list" && t.url === u))) {
              await rpc("svc_source_find_record", { p_provider_id: it.provider_id, p_result: { step_next: "lists", work, tried, known: known.length, pattern: pattern?.re || null, pattern_basis: pattern?.basis || null, worker: WORKER }, p_test: test });
              tally.lists = (tally.lists || 0) + 1; return;
            }
          }
          const order = ["map", "map_search", "sitemap", "lists"]; const nextStep = order[order.indexOf(step) + 1];
          const pattern: Pat | null = work.pattern || null;
          if (!chosen && nextStep) {
            await rpc("svc_source_find_record", { p_provider_id: it.provider_id, p_result: { step_next: nextStep, work, tried, known: known.length, pattern: pattern?.re || null, pattern_basis: pattern?.basis || null, worker: WORKER }, p_test: test });
            tally[step] = (tally[step] || 0) + 1; return;
          }
          const result = { known: known.length, pattern: pattern?.re || null, pattern_basis: pattern?.basis || null, chosen, tried, worker: WORKER,
            reason: chosen ? null : !pattern ? "no course address pattern (too few known course pages and no course-named folder in a map or site map)" : "no map, site map or list page gave enough course addresses" };
          await rpc("svc_source_find_record", { p_provider_id: it.provider_id, p_result: result, p_test: test });
          tally[chosen ? String(chosen.kind) : "none"] = (tally[chosen ? String(chosen.kind) : "none"] || 0) + 1;
        } catch (e) {
          await rpc("svc_source_find_record", { p_provider_id: it.provider_id, p_result: { error: e instanceof Error ? e.message : String(e), tried, worker: WORKER }, p_test: test }).catch(() => null);
          tally.failed = (tally.failed || 0) + 1;
        }
      });
      // v0.40.5: items and done are the keys the idle guard (security.worker_call_work_v1) counts as work
      return j({ ok: true, mode, workerVersion: WORKER, universities: (next.items || []).length, items: (next.items || []).length, done: Object.values(tally).reduce((a, b) => a + b, 0), tally, ms: Date.now() - t0 });
    }
    if (mode === "programme_discover") {
      const items: { id: number; provider_id: string; url: string; kind: string; url_pattern: string; child_pattern: string | null; max_urls: number; read_via?: string | null }[] =
        await rpc("svc_programme_source_next", { p_limit: Math.min(Number(body.limit || 4), 20) }) || [];
      const tally: Record<string, number> = {};
      const getText = async (url: string) => {
        try {
          const u = new URL(url);
          if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { http: null as number | null, text: "", status: "blocked" };
          const r = await fetch(u, { headers: { "user-agent": UA, accept: "application/xml,text/xml,text/html;q=0.9,*/*;q=0.8" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
          const text = r.ok ? await r.text() : (await r.body?.cancel(), "");
          return { http: r.status, text, status: r.ok ? "read" : [401, 403, 406, 429].includes(r.status) ? "blocked" : r.status === 404 || r.status === 410 ? "gone" : "failed" };
        } catch { return { http: null as number | null, text: "", status: "failed" } }
      };
      const locs = (xml: string) => [...xml.matchAll(/<loc>\s*([^<\s]+)\s*<\/loc>/gi)].map((m) => m[1].replace(/&amp;/g, "&"));
      await pool(items, 2, async (it) => {
        let re: RegExp, cre: RegExp | null = null;
        try { re = new RegExp(it.url_pattern, "i"); cre = it.child_pattern ? new RegExp(it.child_pattern, "i") : null }
        catch { await rpc("svc_programme_source_record", { p_id: it.id, p_status: "failed", p_http: null, p_via: null, p_urls: null }).catch(() => null); tally.failed = (tally.failed || 0) + 1; return }
        const found = new Map<string, string>(); let http: number | null = null, st = "failed", via: string | null = "direct";
        if (it.read_via === "map") {
          const m = await fcMap(it.url, it.provider_id); via = "map";
          if (!m) { tally.waiting = (tally.waiting || 0) + 1; await rpc("svc_programme_source_record", { p_id: it.id, p_status: "failed", p_http: null, p_via: "map", p_urls: null }).catch(() => null); return }
          http = m.status; st = m.ok ? "read" : "failed";
          for (const l of m.links) if (re.test(l.url) && found.size < it.max_urls) found.set(l.url, l.title);
        } else if (it.kind === "sitemap") {
          const queue = [it.url], seen = new Set<string>(); let files = 0;
          while (queue.length && files < 25 && Date.now() - t0 < BUDGET_MS) {  // fixed: a site map index lists a handful of files
            const u = queue.shift() as string; if (seen.has(u)) continue; seen.add(u);
            const r = await getText(u); if (files === 0) { http = r.http; st = r.status }
            if (!r.text) { if (files === 0) break; continue }
            files++; st = "read";
            const ls = locs(r.text);
            if (/<sitemapindex/i.test(r.text)) { for (const l of ls) if (!cre || cre.test(l)) queue.push(l) }
            else for (const l of ls) if (re.test(l) && found.size < it.max_urls) found.set(l, "");
          }
        } else {
          const d = await readDirect(it.url); http = d.http; st = d.html ? "read" : d.status === "too_thin" ? "read" : d.status;
          let html = d.html;
          const grab = (h: string) => { const out = new Map<string, string>();
            for (const m of h.matchAll(/<a\b[^>]*?href\s*=\s*["']([^"'#]+)[^"']*["'][^>]*>([\s\S]*?)<\/a>/gi)) {
              let u: URL; try { u = new URL(m[1].replace(/&amp;/g, "&"), it.url) } catch { continue }
              const k = u.toString(); if (re.test(k) && !out.has(k) && out.size < it.max_urls) out.set(k, htmlToText(m[2]).slice(0, 200));
            }
            return out };
          let got = html ? grab(html) : new Map<string, string>();
          if (got.size < 5 && await useFc("list_scrape", it.provider_id, it.url)) {
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 3000, timeout: 45000 }), signal: AbortSignal.timeout(60000) }).catch(() => null);
            const j2 = r ? await r.json().catch(() => ({})) : {};
            const code = Number(j2?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
            const h2 = r?.ok && code !== null && code < 400 ? pageHtml(j2) : "";
            const g2 = h2 ? grab(h2) : new Map<string, string>();
            if (g2.size > got.size) { got = g2; html = h2; via = "firecrawl"; http = code; st = "read" }
          }
          for (const [k, t] of got) found.set(k, t);
        }
        await rpc("svc_programme_source_record", { p_id: it.id, p_status: st, p_http: http, p_via: via, p_urls: [...found].map(([url, title]) => ({ url, title })) }).catch(() => null);
        tally[st] = (tally[st] || 0) + 1; tally.pages = (tally.pages || 0) + found.size;
      });
      return j({ ok: true, mode, workerVersion: WORKER, lists: items.length, read: tally.read || 0, items: items.length, tally, ms: Date.now() - t0 });  // v0.40.5: read and items for the idle guard
    }
    if (mode === "programme_read") {
      const items: { id: number; provider_id: string; url: string }[] = await rpc("svc_programme_next", { p_limit: Math.min(Number(body.limit || 40), 100) }) || [];
      const tally: Record<string, number> = {};
      const pick = (html: string, re: RegExp) => { const m = html.match(re); return m ? htmlToText(m[1]).replace(/\u0000/g, "").replace(/\s+/g, " ").trim().slice(0, 300) || null : null };  // v0.40.6: no null characters (jsonb refuses them)
      await pool(items, 6, async (it) => {
        if (Date.now() - t0 > BUDGET_MS) return;
        let d: { status: string; http: number | null; html: string; finalUrl: string } = await readDirect(it.url), via = "direct";
        if (d.status === "blocked" && await useFc("list_scrape", it.provider_id, it.url)) {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["rawHtml"], onlyMainContent: false, waitFor: 1500, timeout: 30000 }), signal: AbortSignal.timeout(45000) }).catch(() => null);
          const j2 = r ? await r.json().catch(() => ({})) : {};
          const code = Number(j2?.data?.metadata?.statusCode ?? (r?.ok ? 200 : r?.status ?? 0)) || null;
          const h2 = r?.ok && code !== null && code < 400 ? pageHtml(j2) : "";
          if (h2) { d = { status: "read", http: code, html: h2, finalUrl: String(j2?.data?.metadata?.url || it.url) }; via = "firecrawl" }
        }
        const html = d.html || "";
        const og = (html.match(/<meta[^>]+property=["']og:title["'][^>]+content=["']([^"']+)/i) || [])[1] || null;
        const result = { status: html ? (d.status === "too_thin" ? "too_thin" : "read") : d.status, http: d.http, via, final_url: d.finalUrl,
          heading: html ? pick(html, /<h1\b[^>]*>([\s\S]*?)<\/h1>/i) : null, title: html ? pick(html, /<title\b[^>]*>([\s\S]*?)<\/title>/i) : null,
          og_title: og ? htmlToText(og).replace(/\u0000/g, "").trim().slice(0, 300) : null };
        await rpc("svc_programme_record", { p_id: it.id, p_result: result }).catch(() => null);
        tally[result.status] = (tally[result.status] || 0) + 1;
      });
      return j({ ok: true, mode, workerVersion: WORKER, pages: items.length, tally, ms: Date.now() - t0 });
    }
    if (mode === "provider_facts_add_tests") {
      const items: { id: string; provider: string; url: string; storage_path: string }[] = await rpc("svc_provider_policy_add_tests_next", { p_parser: ADD_TESTS_PARSER, p_limit: Math.min(Number(body.limit || 40), 200) }) || [];
      const tally: Record<string, number> = { checked: 0, added: 0, rows: 0, skipped: 0, failed: 0 };
      await pool(items, 3, async (it) => {
        if (Date.now() - t0 > BUDGET_MS) return;
        let parsed: unknown = null, err: string | null = null;
        try {
          const { data, error } = await c.storage.from("evidence").download(it.storage_path); if (error || !data) throw Error(error?.message || "missing");
          const buf = new Uint8Array(await data.arrayBuffer());
          const md = buf[0] === 0x1f && buf[1] === 0x8b ? await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).text() : new TextDecoder().decode(buf);
          parsed = { ...englishPolicy(md), add_only: ADDED_TESTS };
        } catch (e) { err = (e instanceof Error ? e.message : String(e)).slice(0, 200); tally.failed++ }
        try {
          const r = await rpc("svc_provider_english_add_tests_v1", { p_proposal_id: it.id, p_parser: ADD_TESTS_PARSER, p_parsed: parsed, p_error: err });
          tally.checked++; tally.added += Number(r?.added || 0); tally.rows += Number(r?.rows || 0); tally.skipped += Number(r?.skipped || 0);
        } catch { tally.failed++ }
      });
      // CF-247 English requirements (6 Nov 2026, D5): stored pages read again with the current parser. The database lists only documents whose latest
      // reading gave no values, or was rejected as one faculty row, and that no reading by this parser exists for. Nothing is fetched and no model is asked;
      // the result is a proposal (group rules are never approved here).
      // fixed: the cap in the next call is the upper bound of the batch.policy_reparse setting range (0-200); the size itself comes from the setting
      const reparseItems: { id: string; provider: string; url: string; storage_path: string }[] = Number(body.reparse_limit || 0) > 0
        ? await rpc("svc_provider_policy_reparse_next", { p_parser: POLICY_PARSER, p_limit: Math.min(Number(body.reparse_limit), 200) }) || [] : [];
      const reparse: Record<string, number> = { checked: 0, proposed: 0, no_values: 0, failed: 0 };
      await pool(reparseItems, 3, async (it) => {
        if (Date.now() - t0 > BUDGET_MS) return;
        try {
          const { data, error } = await c.storage.from("evidence").download(it.storage_path); if (error || !data) throw Error(error?.message || "missing");
          const buf = new Uint8Array(await data.arrayBuffer());
          const md = buf[0] === 0x1f && buf[1] === 0x8b ? await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).text() : new TextDecoder().decode(buf);
          const r = await rpc("svc_provider_policy_record", { p_source_id: it.id, p_parsed: englishPolicy(md) });
          reparse.checked++; reparse[String(r?.status) === "proposed" ? "proposed" : "no_values"]++;
        } catch { reparse.failed++ }
      });
      return j({ ok: true, mode, workerVersion: WORKER, parser: ADD_TESTS_PARSER, policies: items.length, tally, reparse_parser: POLICY_PARSER, reparse, ms: Date.now() - t0 });
    }

    if (mode === "provider_facts_inspect" || mode === "provider_facts_parse") {
      const docs: { id: string; provider: string; kind: string; url: string; storage_path: string }[] = await rpc("svc_provider_facts_docs", { p_ids: body.ids || null, p_kind: body.kind || null, p_limit: Math.min(Number(body.limit || 5), 400) });
      const chars = Math.min(Number(body.chars || 6000), 60000), from = Math.max(0, Number(body.offset || 0));
      const out: unknown[] = []; const tally: Record<string, number> = {};
      await pool(docs, 6, async (d) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(d.storage_path); if (error || !data) throw Error(error?.message || "missing");
          const md = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const parsed = d.kind === "english_policy" ? englishPolicy(md) : d.kind === "intake_calendar" ? calendarStarts(md) : null;
          if (mode === "provider_facts_parse") {
            if (!parsed) return;
            const r = await rpc("svc_provider_policy_record", { p_source_id: d.id, p_parsed: parsed });
            tally[String(r?.status || "recorded")] = (tally[String(r?.status || "recorded")] || 0) + 1;
            if (body.summary) out.push({ id: d.id, provider: d.provider, kind: d.kind, status: r?.status, style: (parsed as { style?: string }).style, defaults: (parsed as { defaults?: unknown }).defaults, periods: (parsed as { periods?: unknown }).periods });
            return;
          }
          const lines = body.lines ? md.split("\n").filter((l) => new RegExp(String(body.lines), "i").test(l)).map((l) => l.slice(0, Number(body.line_chars || 400))).slice(0, Number(body.max_lines || 120)) : null;
          out.push({ id: d.id, provider: d.provider, kind: d.kind, url: d.url, chars: md.length, ...(lines ? { lines } : { text: md.slice(from, from + chars) }), ...(body.no_parse ? {} : { parsed }) });
        } catch (e) { tally.failed = (tally.failed || 0) + 1; out.push({ id: d.id, url: d.url, error: e instanceof Error ? e.message : String(e) }) }
      });
      return j({ ok: true, mode, workerVersion: WORKER, parser: POLICY_PARSER, docs: docs.length, tally, out });
    }

    if (mode === "provider_facts") {
      const searches: { provider_id: string; kind: string; query: string }[] = await rpc("svc_provider_facts_search_next", { p_limit: Math.min(Number(body.search_limit || 12), 40) });
      let found = 0;
      await pool(searches, 6, async (it) => {
        if (Date.now() - t0 > BUDGET_MS / 2) { await rpc("svc_provider_facts_search_record", { p_provider_id: it.provider_id, p_kind: it.kind, p_http: 0, p_results: [], p_error: "time budget" }); return }
        { const g = await useFcWhy("provider_facts_search", it.provider_id, it.query);
          if (!g.ok) { await rpc("svc_provider_facts_search_record", { p_provider_id: it.provider_id, p_kind: it.kind, p_http: 0, p_results: [], p_error: g.why }); return } }
        let http = 0, results: { url: string; title: string }[] = [];
        try {
          const r = await fetch("https://api.firecrawl.dev/v1/search", { method: "POST", headers: fcHeaders, body: JSON.stringify({ query: it.query, limit: wsNum("search_results_scholarship_discover", 6) }), signal: AbortSignal.timeout(45000) });
          http = r.status; const d = await r.json().catch(() => ({}));
          results = Array.isArray(d?.data) ? d.data.map((x: { url?: string; title?: string }) => ({ url: String(x?.url || ""), title: String(x?.title || "") })).filter((x: { url: string }) => x.url) : [];
        } catch { http = 0 }
        found += Number(await rpc("svc_provider_facts_search_record", { p_provider_id: it.provider_id, p_kind: it.kind, p_http: http, p_results: results, p_error: null }) || 0);
      });
      const docs: { id: string; provider_id: string; kind: string; url: string; country: string; currency: string }[] = await rpc("svc_provider_facts_read_next", { p_limit: Math.min(Number(body.read_limit || 6), 20) });
      const tally: Record<string, number> = {};
      await pool(docs, 4, async (it) => {
        const g = Date.now() - t0 > BUDGET_MS ? { ok: false, why: "time budget" } : await useFcWhy("provider_facts_scrape", it.provider_id, it.url);
        if (!g.ok) {
          await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: g.why } }); return
        }
        try {
          const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["markdown"], onlyMainContent: true }), signal: AbortSignal.timeout(90000) });
          const d = await r.json().catch(() => ({}));
          const md: string = d?.data?.markdown || "";
          const http = Number(d?.data?.metadata?.statusCode ?? r.status);
          const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
          if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: "provider_facts_scrape", p_provider_id: it.provider_id, p_url: it.url });
          if (!r.ok || md.length < 200) { await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: http, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: d?.error || "no content", chars: md.length } }); tally.failed = (tally.failed || 0) + 1; return }
          const sha = await sha256(new TextEncoder().encode(md));
          let path: string | null = `layer2/${it.country || "XX"}/provider-facts/${it.provider_id}/${it.id}/${sha}.md.gz`;
          const up = await c.storage.from("evidence").upload(path, await gzip(md), { contentType: "application/gzip", upsert: true });
          if (up.error) path = null;
          const parsed = it.kind === "fee_schedule" ? parseFeeRows(md) : { rows: [], summary: { chars: md.length } };
          const links = it.kind === "fee_schedule" ? feeLinks(md, it.url) : [];
          const res = await rpc("svc_provider_facts_read_record_v2", { p_id: it.id, p_status: "read", p_http: http, p_storage_path: path, p_sha256: path ? sha : null, p_mime: "text/markdown", p_rows: parsed.rows, p_summary: { ...parsed.summary, chars: md.length, title: String(d?.data?.metadata?.title || "").slice(0, 200) }, p_links: links });
          // Decision 227: English policy and academic calendar documents are parsed into a proposal (approved by a person)
          if (it.kind === "english_policy" || it.kind === "intake_calendar") {
            try { await rpc("svc_provider_policy_record", { p_source_id: it.id, p_parsed: it.kind === "english_policy" ? englishPolicy(md) : calendarStarts(md) }); tally.proposals = (tally.proposals || 0) + 1 }
            catch { tally.proposal_failed = (tally.proposal_failed || 0) + 1 }
          }
          tally.linked = (tally.linked || 0) + Number(res?.linked || 0);
          tally[it.kind] = (tally[it.kind] || 0) + 1; tally.fee_rows = (tally.fee_rows || 0) + Number(res?.fee_rows || 0);
        } catch (e) {
          await rpc("svc_provider_facts_read_record", { p_id: it.id, p_status: "failed", p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_rows: [], p_summary: { error: e instanceof Error ? e.message : String(e) } });
          tally.failed = (tally.failed || 0) + 1;
        }
      });
      return j({ ok: true, mode, workerVersion: VERSION, searched: searches.length, sources_found: found, read: docs.length, tally, ms: Date.now() - t0 });
    }

    // v0.8.0: scholarship discovery. Phase discover: a provider's own scholarship pages from its site maps (and a
    // scholarships.<domain> subdomain's), one Firecrawl map with search "scholarship" only when the site maps give none;
    // held Study Australia-only scholarships are matched to a page by exact name (address or title). Phase search: one
    // Firecrawl web search per held scholarship still without a page. Phase candidates: unheld pages at Australian
    // universities are read directly and offered to security.scholarship_admit_from_provider_page_v1.
    if (mode === "scholarship_discover") {
      const phase = String(body.phase || "all"), deadline = t0 + 105_000;
      const out: Record<string, unknown> = {};
      if (phase === "all" || phase === "discover") {
        // v0.58.0 (F4): each provider comes with its sources (website plus the scholarship catalogues recorded for it), all mapped in this run
        const provs: { provider_id: string; website: string; reason: string; hosts?: string[]; names: string[]; held: { scholarship_id: string; name: string }[]; sources?: string[] }[] = await rpc("svc_scholarship_discover_next", { p_limit: Math.min(Number(body.limit || 3), wsNum("scholarship.discover_providers_max", 6)) });
        const done: unknown[] = [];
        await pool(provs, 3, async (p) => {
          let site: URL;
          try { site = new URL(/^https?:/i.test(p.website) ? p.website : "https://" + p.website) } catch { await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: "failed", p_site_origin: null, p_method: "none", p_url_count: 0, p_candidates: [], p_matches: [], p_error: "invalid website" }); return }
          try {
            // v0.18.0: the site is mapped through the scraper only (its site maps included); no direct fetch of the site or its sitemaps
            const found = new Map<string, { url: string; title?: string; source: string }>();
            const methods: string[] = []; let total = 0;
            // v0.58.0 (F4): one map per distinct source origin and path (website first), each through the daily budget; a refused or failed map
            // is recorded by its reason and makes the result "deferred" (F3), never a final "empty"
            const srcs = [...new Set([site.origin, ...((p.sources || []).filter((u) => /^https?:\/\//i.test(u)))])].slice(0, wsNum("scholarship.sources_per_provider_max", 5));
            for (const src of srcs) {
              let origin = site.origin, hostname = site.hostname;
              try { const su = new URL(src); origin = su.pathname.length > 1 ? su.origin + su.pathname : su.origin; hostname = su.hostname } catch { continue }
              const gm = await useFcWhy("sch_map", p.provider_id, origin, true);
              if (gm.ok) {
                const r = await fetch("https://api.firecrawl.dev/v2/map", { method: "POST", headers: fcHeaders, body: JSON.stringify({ url: origin, search: "scholarship", limit: wsNum("map_limit_scholarships", 5000), sitemap: "include", includeSubdomains: true }), signal: AbortSignal.timeout(60000) }).catch(() => null);
                const d = r ? await r.json().catch(() => ({})) : {};
                if (!r || !r.ok || d?.success === false) methods.push(`map:${r ? r.status : "timeout"}`);
                else {
                  const links = (d.links || d.data?.links || []).map((x: any) => typeof x === "string" ? { url: x } : { url: x.url, title: x.title });
                  methods.push(`map_search(${links.length})`); total += links.length;
                  for (const u of links) if (u.url && keepScholarshipUrl(u.url, [site.hostname, hostname, ...(p.hosts || [])])) found.set(normUrl(u.url), { url: u.url, title: u.title, source: "map" });
                }
              } else methods.push(`map:${gm.why}`);
            }
            const cands = [...found.values()].slice(0, wsNum("scholarship.map_candidates_max", 6000));
            const pm: unknown[] = []; // v0.18.0: no matching of register (Study Australia) records; scholarships come from provider pages only
            const outcome = mapOutcome(methods, cands.length);  // v0.58.0 (F3)
            const rec = await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: outcome, p_site_origin: site.origin, p_method: methods.join("+") || "none", p_url_count: total, p_candidates: cands, p_matches: pm, p_error: outcome === "deferred" ? methods.filter((m) => m.startsWith("map:")).join(", ") : null });
            done.push({ provider_id: p.provider_id, status: outcome, sources: srcs.length, methods, total, kept: rec?.kept, held: (p.held || []).length, matched: rec?.matched });
          } catch (e) {
            await rpc("svc_scholarship_discover_record", { p_provider_id: p.provider_id, p_status: "failed", p_site_origin: site.origin, p_method: "discover", p_url_count: 0, p_candidates: [], p_matches: [], p_error: e instanceof Error ? e.message : String(e) });
            done.push({ provider_id: p.provider_id, status: "failed", error: e instanceof Error ? e.message : String(e) });
          }
        });
        out.discover = done;
      }
      // v0.18.0: the web search for register (Study Australia) records without a provider page is retired
      if ((phase === "all" || phase === "candidates") && Date.now() < deadline - 30000) {
        const items: { candidate_id: number; url: string; provider_id: string; site: string; currency?: string; hosts?: string[] }[] = await rpc("svc_scholarship_candidate_next", { p_limit: Math.min(Number(body.read_limit || 30), wsNum("scholarship.candidates_max", 60)) });
        const tally: Record<string, number> = {}; const admitted: unknown[] = [];
        await pool(items, 6, async (it) => {
          if (Date.now() > deadline) { await rpc("svc_scholarship_candidate_record", { p_candidate_id: it.candidate_id, p_read_status: "deferred", p_http_status: null, p_fetched_via: null, p_final_url: null, p_storage_path: null, p_sha256: null, p_facts: null }); return }
          // v0.18.0: candidates are read through the scraper only (Platform Admin, 11 Oct 2026)
          const pg = await readSchPage(it.url, it.provider_id);  // v0.58.0: award sections and redirected-away pages (F5, F7)
          const via = pg.via;
          // no scraper credit or service right now: back to the queue unchanged, tried again next run
          if (pg.status === "waiting_scraper") { await rpc("svc_scholarship_candidate_record", { p_candidate_id: it.candidate_id, p_read_status: "deferred", p_http_status: null, p_fetched_via: null, p_final_url: null, p_storage_path: null, p_sha256: null, p_facts: null }); tally.waiting_scraper = (tally.waiting_scraper || 0) + 1; return }
          let facts: Record<string, unknown> | null = null, path: string | null = null, sha: string | null = null;
          if (pg.status === "read") {
            let host = ""; try { host = new URL(/^https?:/i.test(it.site) ? it.site : "https://" + it.site).hostname } catch { /* */ }
            const adm = admissionCheck(pg.html, pg.finalUrl, [host, ...(it.hosts || [])]);
            facts = { ...scholarshipFacts(pg.html, titleOf(pg.html) + " " + h1Of(pg.html), adm.name || "", it.currency || "AUD"), page_title: titleOf(pg.html).slice(0, 200), h1: h1Of(pg.html).slice(0, 200), final_url: pg.finalUrl, extractor: SCH_VERSION, admission: adm };
          }
          // v0.19.2 (Platform Admin bugs 11/10-5, Fix 2): every page read keeps a stored copy (refused and too-thin pages too), so
          // each decision can be checked later; a page that would be admitted without its copy is not admitted
          if (pg.html && (pg.status === "read" || pg.status === "too_thin")) {
            const gz = await gzip(pg.html); sha = await sha256(new TextEncoder().encode(pg.html));
            path = `layer2/AU/scholarships/${it.provider_id}/candidates/${it.candidate_id}/${sha}.html.gz`;
            const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
            if (up.error) { path = null; sha = null; if (facts && (facts.admission as any)?.admit) { (facts.admission as any).admit = false; (facts.admission as any).reasons = ["evidence_upload_failed"] } }
          }
          const res = await rpc("svc_scholarship_candidate_record", { p_candidate_id: it.candidate_id, p_read_status: pg.status, p_http_status: pg.http, p_fetched_via: via, p_final_url: pg.finalUrl, p_storage_path: path, p_sha256: sha, p_facts: facts });
          const k = res?.admitted ? "admitted" : pg.status === "read" ? (res?.reason ? "read:" + res.reason : "read:rejected") : pg.status;
          tally[k] = (tally[k] || 0) + 1;
          if (res?.admitted) admitted.push({ candidate_id: it.candidate_id, scholarship_id: res.scholarship_id, apply: res.apply?.changes });
        });
        out.candidates = { items: items.length, tally, admitted };
      }
      return j({ ok: true, mode, phase, ...out, firecrawlRemainingAboveReserve: fcRemaining, scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER, scholarshipExtractor: SCH_VERSION });
    }
    // read only: headings, name check, admission rules and page text of stored evidence (or a live page) for hand checks
    // v0.9.0 (Decision 211): eligibility criteria and award scope from stored scholarship pages (no fetch). Only the
    // two new facts are added; the page's other facts and course links stay as they are.
    // v0.17.37 (CF-247 v2.15.240): a provider's scholarship listing page, read for the coverage check (Scholarships > Coverage)
    if (mode === "scholarship_listing") {
      // v0.58.0 (F5, F6): a listing source is read page by page (rendered, with the catalogue wait), following its pagination (rel="next", a Next
      // link, page=N, startRank/numRanks in the query or the fragment) until it ends, the stated total is reached, a page adds nothing, or the
      // page limit for one run is hit. Complete only when the pagination ended by itself; otherwise partial with the address to continue from.
      // Every item (a linked scholarship, or an award of an umbrella page keyed by its code) goes to svc_scholarship_listing_record_v2, which
      // keeps listing membership and turns new items into candidates without duplicating a held page or record.
      const rows: { id: number; provider_id: string; url: string; hosts: string[]; next_url?: string | null }[] = await rpc("svc_scholarship_listing_next", { p_limit: Math.min(Number(body.limit || 6), wsNum("scholarship.listing_max", 20)) });
      const out: unknown[] = [];
      const maxPages = wsNum("scholarship.listing_pages_max", 10), maxItems = wsNum("scholarship.listing_items_max", 80);
      await pool(rows, 3, async (r) => {
        const items = new Map<string, Record<string, unknown>>();
        let url: string | null = r.next_url || r.url, pages = 0, total: number | null = null, failed = false, lastNew = 0, http: number | null = null, err: string | null = null;
        const seenUrls = new Set<string>();
        while (url && pages < maxPages && !seenUrls.has(url) && Date.now() - t0 < BUDGET_MS - 30000) {
          seenUrls.add(url);
          const pg = await readSch(url, r.provider_id, wsNum("scholarship.catalogue_render_wait_ms", 5000), false);
          http = pg.http;
          if (pg.status !== "read") { failed = true; err = pg.status; break }
          pages++;
          const base = pg.finalUrl || url;
          if (total === null) total = statedTotal(mainText(pg.html));
          const before = items.size;
          for (const it of scholarshipListing(pg.html, base, r.hosts || [], maxItems)) items.set(`url:${it.url || it.name}`, { ...it, kind: "link" });
          for (const a of awardSections(pg.html, base)) items.set(a.url ? `url:${a.url}` : `award:${a.key}`, { name: a.name, url: a.url, code: a.key, codes: a.codes, value_text: a.value_text, kind: a.url ? "link" : "award_section" });
          lastNew = items.size - before;
          const nx = nextPage(url, pg.html);
          url = nx && !seenUrls.has(nx) ? nx : null;
        }
        const paging = pagingState({ pages_read: pages, items: items.size, total_stated: total, next_url: url, last_page_new: lastNew, failed, page_limit_hit: !!url && pages >= maxPages });
        await rpc("svc_scholarship_listing_record_v2", { p_id: r.id, p_status: pages > 0 ? "read" : "failed", p_http_status: http, p_items: [...items.values()], p_error: err, p_paging: paging });
        out.push({ id: r.id, items: items.size, ...paging });
      });
      return j({ ok: true, mode, pages: out, readVia: "scraper", scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER, scholarshipExtractor: SCH_VERSION });
    }
    if (mode === "scholarship_reextract") {
      const rows: { scholarship_id: string; storage_path: string }[] = await rpc("svc_scholarship_reextract_next", { p_limit: Math.min(Number(body.limit || 100), 300), p_version: SCH_VERSION });
      let done = 0, failed = 0; const changes: Record<string, number> = {};
      await pool(rows, 10, async (r) => {
        try {
          const { data, error } = await c.storage.from("evidence").download(r.storage_path);
          if (error || !data) throw Error(error?.message || "missing");
          const html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text();
          const text = mainText(html);
          const res = await rpc("svc_scholarship_reextract_record", { p_scholarship_id: r.scholarship_id, p_facts: { criteria: scholarshipCriteria(text), award_scope: awardScope(text), criteria_extractor: SCH_VERSION } });
          for (const k of (res?.changes || []) as string[]) changes[k] = (changes[k] || 0) + 1;
          done++;
        } catch { failed++ }
      });
      return j({ ok: true, mode, rows: rows.length, done, failed, changes, ms: Date.now() - t0, workerVersion: VERSION, scholarshipExtractor: SCH_VERSION });
    }
    const storedHtml = async (path: string) => { const { data, error } = await c.storage.from("evidence").download(path); if (error || !data) throw Error(error?.message || "missing"); return await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text() };
    // v0.20.0 (Platform Admin bugs 11/10-6, 11 Oct 2026: "scholarship to be read by code using Firecrawl but then use AI to extract
    // attributes"): each queued scholarship page (stored copy, or read now through the scraper and kept) is sent to the model and
    // instructions it was queued with. Every fact must quote the page; the quotes are checked here, and an unproven fact counts as not
    // stated. The database records the answer and, only while AI admission is on, applies it under the usual publish checks.
    if (mode === "scholarship_ai") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: any[] = await rpc("svc_scholarship_ai_next", { p_limit: Math.min(Number(body.limit || 8), 12) });
      const schTokens = answerLimit(ws, "scholarship_page");
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(items, 4, async (it) => {
        const t1 = Date.now();
        const rec = (x: Record<string, unknown>) => rpc("svc_scholarship_ai_record", { p_queue_id: it.queue_id, p_answer: null, p_checks: null, p_verdict: null, p_cost: 0, p_tokens_in: null, p_tokens_out: null, p_seconds: (Date.now() - t1) / 1000, p_error: null, p_storage_path: null, p_sha256: null, p_final_url: null, p_rule_facts: null, p_retry: false, ...x });
        // v0.78.0: a version 3 read may take up to SCH_V3_TIMEOUT_MS, so it starts only early in the call (the rest wait, no try used)
        if (Date.now() - t0 > BUDGET_MS - (Number(it.prompt_version || 0) >= 3 ? SCH_V3_TIMEOUT_MS : 25000)) { await rec({ p_retry: true }); tally.later = (tally.later || 0) + 1; return }
        let html = "", finalUrl = it.url, path: string | null = null, sha: string | null = null, ruleFacts: Record<string, unknown> | null = null;
        try {
          if (it.storage_path) html = await storedHtml(it.storage_path);
          else {
            const pg = await readSch(it.url, it.provider_id || null);
            if (pg.status === "waiting_scraper") { await rec({ p_retry: true }); tally.waiting_scraper = (tally.waiting_scraper || 0) + 1; return }
            html = pg.html || ""; finalUrl = pg.finalUrl || it.url;
            if (html) {
              const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
              path = `layer2/AU/scholarships/${it.provider_id || "none"}/ai/${it.queue_id}/${sha}.html.gz`;
              const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
              if (up.error) { path = null; sha = null }
            }
            if (it.candidate_id) {
              let facts: Record<string, unknown> | null = null;
              if (pg.status === "read") { let host = ""; try { host = new URL(finalUrl).hostname } catch { /* */ } const adm = admissionCheck(html, finalUrl, [host]);
                facts = { ...scholarshipFacts(html, titleOf(html) + " " + h1Of(html), adm.name || "", it.currency || "AUD"), page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), final_url: finalUrl, extractor: SCH_VERSION, admission: adm } }
              ruleFacts = { read_status: pg.status, facts };
            }
          }
          if (!html) { await rec({ p_error: "the page could not be read", p_final_url: finalUrl }); tally.unread = (tally.unread || 0) + 1; return }
          // v0.83.0: a long-page recovery item reads the award's own section of the stored page (sch-extract.ts awardSection) instead of its first 14,000 characters
          const recovery = it.recovery === RECOVERY_VARIANT && Number(it.prompt_version || 0) >= 3;
          const section = recovery ? awardSection(mainText(html), it.scholarship_name || null, wsNum("reading.sch_recovery_section_chars", 6000)) : null;
          const title = titleOf(html).slice(0, 300), h1 = h1Of(html).slice(0, 300), text = section ? section.text : mainText(html).slice(0, 14000);
          // v0.77.0 (F-SCH redesign §4, §6): prompt version 3 reads one evidence bundle: the page and, when it links to one on the same site, its
          // eligibility or terms page, read directly (no credit; a refused or thin linked page is simply left out). Version 2 items read as before.
          const v3 = Number(it.prompt_version || 0) >= 3;
          let linked: BundlePart | null = null;
          if (v3 && Date.now() - t0 < BUDGET_MS - 45000) {
            const lk = eligibilityLinks(html, finalUrl, 1)[0];
            if (lk) { const dr = await readDirect(lk); if (dr.html && (dr.status === "read" || dr.status === "too_thin")) { const lt = mainText(dr.html).slice(0, recovery ? wsNum("reading.sch_recovery_linked_chars", 4000) : 8000); if (lt.length >= 200) linked = { id: "linked", url: dr.finalUrl || lk, title: titleOf(dr.html).slice(0, 200), text: lt } } }  // fixed: 200 characters is the least text that can carry a sentence of eligibility
          }
          const parts: BundlePart[] = [{ id: "page", url: finalUrl, title, h1, text }, ...(linked ? [linked] : [])];
          const bundleIn = { provider: it.provider || "", country: it.country || null, currency: it.currency || null, scholarship: recovery ? (it.scholarship_name || null) : undefined, parts };
          const ask = async (reqBody: unknown, where: string) => {
            const r = await cascadeFetch(fetch, { service: "scholarship_extraction" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
              body: JSON.stringify(reqBody), signal: AbortSignal.timeout(v3 ? SCH_V3_TIMEOUT_MS : 60000) });
            const d = await r.json().catch(() => ({}));
            // v0.54.0 (W32): a cut answer is named before anything else (an empty cut answer was "no answer") and the call's cost is kept on the error
            const ans = where === "scholarship_page" ? readAnswer(d, "scholarship_page", schTokens) : readAnswer(d, "scholarship_page", schTokens, where);
            return { r, d, ans, cost: ans.cost };
          };
          let a: any, c1 = 0, tokIn: number | null = null, tokOut: number | null = null;
          if (recovery) {
            // v0.83.0: two smaller calls over the same bundle (part A identity/eligibility/availability + version 2 keys; part B benefits/payment/
            // application/duration/summary), merged into one version 3 answer; both costs are kept, also when a part fails
            const [pa, pb] = await Promise.all([
              ask(scholarshipExtractPartRequest(it.model, it.prompt, bundleIn, "a", schTokens), "scholarship_page_part_a"),
              ask(scholarshipExtractPartRequest(it.model, it.prompt, bundleIn, "b", schTokens), "scholarship_page_part_b")]);
            c1 = pa.cost + pb.cost; cost += c1;
            for (const [x, nm] of [[pa, "part a"], [pb, "part b"]] as const) {
              if (!x.r.ok) throw readError(`recovery ${nm}: HTTP ${x.r.status}: ${JSON.stringify(x.d?.error || x.d).slice(0, 160)}`, c1);
              if (x.d?.model && !String(x.d.model).startsWith(it.model)) throw readError(`recovery ${nm}: returned model ${x.d.model}, not ${it.model}`, c1);
              if (!x.ans.ok) throw readError(`recovery ${nm}: ${x.ans.error}`, c1);
            }
            a = mergeRecoveryParts((pa.ans as any).a, (pb.ans as any).a);
            tokIn = (Number(pa.d?.usage?.prompt_tokens) || 0) + (Number(pb.d?.usage?.prompt_tokens) || 0) || null;
            tokOut = (Number(pa.d?.usage?.completion_tokens) || 0) + (Number(pb.d?.usage?.completion_tokens) || 0) || null;
          } else {
            const reqBody = v3 ? scholarshipExtractRequest(it.model, it.prompt, bundleIn, schTokens)
                               : scholarshipAiRequest(it.model, it.prompt, { provider: it.provider || "", url: finalUrl, title, h1, text }, schTokens);
            const x = await ask(reqBody, "scholarship_page"); c1 = x.cost; cost += c1;
            if (!x.r.ok) throw readError(`HTTP ${x.r.status}: ${JSON.stringify(x.d?.error || x.d).slice(0, 200)}`, c1);
            if (x.d?.model && !String(x.d.model).startsWith(it.model)) throw readError(`returned model ${x.d.model}, not ${it.model}`, c1);
            if (!x.ans.ok) throw readError(x.ans.error, c1);
            a = (x.ans as any).a; tokIn = x.d?.usage?.prompt_tokens ?? null; tokOut = x.d?.usage?.completion_tokens ?? null;
          }
          const checks: Record<string, unknown> = checkScholarshipAnswer(a, `${title} ${h1} ${text}${linked ? " " + linked.text : ""}`, it.country || null);
          if (v3) {
            checks.contract = SCH_EXTRACT_CONTRACT;
            checks.detail = checkScholarshipDetail(a.detail, parts, NAT_NAMES);
            // which source proved who may apply (the linked terms page counts as the scholarship's own official evidence)
            checks.audience_source = checks.audience ? quoteSource(a.audience_quote, parts) : null;
            a.bundle = { page: finalUrl, linked: linked?.url || null, linked_sha256: linked ? await sha256(new TextEncoder().encode(linked.text)) : null,
                         ...(section ? { section: { start: section.start, chars: section.chars, found: section.found, sha256: await sha256(new TextEncoder().encode(section.text)) } } : {}) };
            if (recovery) checks.recovery = { variant: RECOVERY_VARIANT, parts: 2, section_found: section?.found ?? null, section_chars: section?.chars ?? null };
          }
          const verdict = !a.is_scholarship ? "not_scholarship" : !a.single_scholarship ? "listing" : !checks.name ? "unproven" : "scholarship";
          await rec({ p_answer: a, p_checks: checks, p_verdict: verdict, p_cost: c1, p_tokens_in: tokIn, p_tokens_out: tokOut,
                      p_storage_path: path, p_sha256: sha, p_final_url: finalUrl, p_rule_facts: ruleFacts });
          tally[verdict] = (tally[verdict] || 0) + 1;
        } catch (e) {
          await rec({ p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400), p_cost: errorCost(e), p_storage_path: path, p_sha256: sha, p_final_url: finalUrl, p_rule_facts: ruleFacts });  // v0.54.0 (W32): cost recorded on a failed read
          tally.error = (tally.error || 0) + 1;
        }
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.34.0 (20 Oct 2026, Platform Admin "NZQA Code signatory (Recommended)"): New Zealand providers that enrol international students. Each
    // provider page NZQA publishes (stored by the Layer 1 NZQA reader in its batch files) says whether the organisation is a signatory to the
    // Code of Practice for the pastoral care of international students; only signatories may enrol them. The stored files are read (no
    // fetch, no credit) and each provider's number, whether the sentence is there and the sentence itself are recorded; the database sets
    // the international-enrolment flag from them (security.nz_cop_apply_v1). Read only here.
    if (mode === "nz_cop") {
      const files: any[] = await rpc("svc_nz_cop_next", { p_limit: Math.max(1, Math.min(Number(body?.limit) || 3, 10)) });  // fixed: files a call (each about 1 MB)
      if (!Array.isArray(files) || !files.length) return j({ ok: true, mode, idle: true, worker: WORKER });
      const SIGN = /[^.<>]*\bis a Signatory to the (?:Education \(Pastoral Care[^)]*\) )?Code(?: of Practice)?[^.<>]*\./i;
      const NOT = /[^.<>]*\b(?:is not|is no longer|not) a Signatory to the[^.<>]*\./i;
      const out: any[] = [];
      for (const f of files) {
        try {
          const { data, error } = await c.storage.from("evidence").download(f.path);
          if (error || !data) throw Error(`stored file missing: ${f.path}`);
          const parsed = JSON.parse(await data.text());
          const list = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.providers) ? parsed.providers : [];
          const rows = list.filter((x: any) => x?.provider_code && typeof x?.detailsHtml === "string").map((x: any) => {
            const text = String(x.detailsHtml).replace(/<[^>]+>/g, " ").replace(/&nbsp;/gi, " ").replace(/&amp;/gi, "&").replace(/\s+/g, " ");
            const no = text.match(NOT), yes = no ? null : text.match(SIGN);
            // v0.34.1: the NZQA type and the words around "Code" are kept, so a page worded differently (the universities) can be seen
            const at = text.search(/Code of Practice|Pastoral Care|Signatory|international (?:students|learners)/i);
            return { code: String(x.provider_code), name: x.provider_name || null, signatory: Boolean(yes), explicit_no: Boolean(no), quote: (yes || no)?.[0]?.trim().slice(0, 300) || null, nzqa_id: x.providerId || null,
                     type: x.type || null, snippet: at < 0 ? null : text.slice(Math.max(0, at - 120), at + 280).trim() };
          });
          out.push({ path: f.path, providers: rows.length, signatories: rows.filter((r: any) => r.signatory).length, result: await rpc("svc_nz_cop_record", { p_path: f.path, p_rows: rows, p_error: null, p_reader: "v2" }) });
        } catch (e) {
          const msg = e instanceof Error ? e.message : String(e);
          await rpc("svc_nz_cop_record", { p_path: f.path, p_rows: [], p_error: msg.slice(0, 500), p_reader: "v2" });
          out.push({ path: f.path, error: msg });
        }
      }
      // v0.59.3: the ledger counts files read and failed (svc_worker_report_v1 reads "read" and "failed")
      const nzFailed = out.filter((x: any) => x?.error).length;
      return j({ ok: true, mode, files: out, read: out.length, failed: nzFailed, worker: WORKER });
    }
    // v0.33.0 (19 Oct 2026, Platform Admin 22:47 "AI re-check, then finish"): a held scholarship page (held because a quote did not prove
    // who it is for or its value, or the page was not read) is asked one narrow question by the first (cheap) model of the chain: who may
    // apply and the value, each with the exact sentence. The sentences are checked on the page and must say international or domestic in
    // words (as checkScholarshipAnswer does). The answer becomes a recommendation on the held item; nothing is published or rejected here.
    if (mode === "scholarship_recheck") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: any[] = await rpc("svc_scholarship_recheck_next", { p_limit: Math.min(Number(body.limit || 12), 40) });
      const recheckTokens = answerLimit(ws, "scholarship_recheck");
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(items, 4, async (it) => {
        let usedModel = String(it.model || ""); const rec = async (result: Record<string, unknown> | null, c1: number, err: string | null) => { const res = await rpc("svc_scholarship_recheck_record", { p_id: it.id, p_result: result, p_cost: c1, p_error: err }); if (usedModel !== String(it.model || "")) await rpc("svc_ai_model_answered_v1", { p_source: "scholarship_ai_reviews", p_source_id: String(it.id), p_model: usedModel }).catch(() => null); return res };
        if (Date.now() - t0 > BUDGET_MS - 25000) { await rec(null, 0, "time budget"); tally.later = (tally.later || 0) + 1; return }
        let c1 = 0;
        try {
          let html = "";
          if (it.storage_path) html = await storedHtml(it.storage_path).catch(() => "");
          if (!html) { const pg = await readSch(it.url, it.provider_id || null); html = pg.status === "read" ? pg.html || "" : "" }
          if (!html) { await rec({ recommendation: "unsettled", why: "The page could not be read again." }, 0, null); tally.unread = (tally.unread || 0) + 1; return }
          const title = titleOf(html).slice(0, 300), h1 = h1Of(html).slice(0, 300), text = mainText(html).slice(0, 14000);
          const r = await cascadeFetch(fetch, { models: (it as any).models, deadline: t0 + BUDGET_MS - 25000, service: "scholarship_extraction", source: "scholarship_recheck", source_id: it.id }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(scholarshipRecheckRequest(it.model, { name: it.name || "", provider: it.provider || "", url: it.url, title, h1, text }, recheckTokens)), signal: AbortSignal.timeout(60000) });
          const d = await r.json().catch(() => ({})); usedModel = sentModel(d, it.model);
          // v0.54.0 (W32): the cost is counted before any check; a cut or empty answer fails the re-check, named (an empty answer was read as "{}")
          const ans = readAnswer(d, "scholarship_recheck", recheckTokens); c1 = ans.cost; cost += c1;
          if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`);
          if (d?.model && !String(d.model).startsWith(sentModel(d, it.model))) throw Error(`returned model ${d.model}, not ${it.model}`);
          if (!ans.ok) throw Error(ans.error);
          const a = ans.a;
          const out = judgeScholarshipRecheck(a, `${title} ${h1} ${text}`);
          await rec({ ...out, model: it.model }, c1, null);
          tally[out.recommendation] = (tally[out.recommendation] || 0) + 1;
        } catch (e) {
          await rec(null, c1, (e instanceof Error ? e.message : String(e)).slice(0, 300));
          tally.error = (tally.error || 0) + 1;
        }
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.75.0 (12 Nov 2026, CF-247 F-SCH.01, eligibility.ts): a scholarship page refused only because no sentence said international students may
    // apply is read again with the re-check question (stored copy first, no Firecrawl); when the page is silent, at most links_max pages it links
    // to for its eligibility or conditions on the same site are read (Firecrawl through the scholarship share) and asked the same question about
    // that scholarship. Each sentence must be on the page it was read from and name international or domestic students in words. Every item
    // leased is answered exactly once through public.svc_scholarship_eligibility_record; the database decides (shadow until sch_elig.apply_on).
    if (mode === "scholarship_eligibility") {
      const w: any = await rpc("svc_scholarship_eligibility_next", { p_limit: Math.min(Number(body.limit || 10), 40) });  // fixed: the setting batch.sch_eligibility_read's upper bound
      const items: any[] = Array.isArray(w?.items) ? w.items : [];
      if (!items.length) return j({ ok: true, mode, items: 0, read: 0, failed: 0, held: w?.held ?? null, worker: WORKER });
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      const tokens = answerLimit(ws, "scholarship_recheck"), ors = orStats();
      const tally: Record<string, number> = {}; let cost = 0;
      const bump = (k: string) => { tally[k] = (tally[k] || 0) + 1 };
      await pool(items, 4, async (it) => {
        const rec = (result: Record<string, unknown> | null, c1: number, err: string | null) => rpc("svc_scholarship_eligibility_record", { p_id: it.id, p_result: result, p_cost: c1, p_error: err });
        if (!key) { await rec(null, 0, "OpenRouter credential unavailable"); bump("error"); return }
        if (Date.now() - t0 > BUDGET_MS - 30000) { await rec(null, 0, "time budget"); bump("later"); return }
        let c1 = 0;
        const ask = async (html: string, url: string, from: string | null) => {
          const title = titleOf(html).slice(0, 300), h1 = h1Of(html).slice(0, 300), text = mainText(html).slice(0, 14000);
          let req: any = scholarshipRecheckRequest(it.model, { name: it.name || "", provider: it.provider || "", url, title, h1, text }, tokens);
          if (from) req = linkedPageNote(req, it.name || "", from);
          const r = await cascadeFetch(ors.fetch, { service: "scholarship_eligibility" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(req), signal: AbortSignal.timeout(60000) });  // fixed: API time-out of one call
          const d = await r.json().catch(() => ({}));
          const ans = readAnswer(d, "scholarship_recheck", tokens, from ? "linked page" : "page"); c1 += ans.cost; cost += ans.cost;
          if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`);
          if (d?.model && !String(d.model).startsWith(it.model)) throw Error(`returned model ${d.model}, not ${it.model}`);
          if (!ans.ok) throw Error(ans.error);
          return eligibilityProof(judgeScholarshipRecheck(ans.a, `${title} ${h1} ${text}`));  // v0.76.0: "international" must describe who may apply
        };
        try {
          let html = "", via = "stored";
          if (it.storage_path) html = await storedHtml(it.storage_path).catch(() => "");
          if (!html) { via = "firecrawl"; const pg = await readSch(it.url, it.provider_id || null); html = pg.status === "read" ? pg.html || "" : "" }
          if (!html) { await rec({ outcome: "unread", page_via: via }, 0, null); bump("unread"); return }
          const first = await ask(html, it.url, null);
          const linked: { url: string; status: string; judged?: any }[] = [];
          if (!first.audience_proven && it.link_follow) {
            for (const u of eligibilityLinks(html, it.url, Number(it.links_max || 0))) {
              const pg = await readSch(u, it.provider_id || null);
              if (pg.status !== "read" || !pg.html) { linked.push({ url: u, status: pg.status }); continue }
              const judged = await ask(pg.html, pg.finalUrl || u, it.url);
              linked.push({ url: pg.finalUrl || u, status: "read", judged });
              if (judged.audience_proven) break;
            }
          }
          const o = eligibilityOutcome(first, linked);
          await rec({ outcome: o.outcome, source: o.source, source_url: o.source === "linked" ? o.source_url : it.url, page_via: via, model: it.model,
                      ...(o.judged || {}), page: o.source === "linked" ? first : undefined,
                      links: linked.map((l) => ({ url: l.url, status: l.status, audience: l.judged?.audience ?? null, proven: l.judged?.audience_proven ?? null })) }, c1, null);
          bump(o.outcome === "proven" ? `proven_${o.source}_${o.judged?.audience}` : o.outcome);
        } catch (e) {
          await rec(null, c1, (e instanceof Error ? e.message : String(e)).slice(0, 300));
          bump("error");
        }
      });
      return j({ ok: true, mode, items: items.length, read: items.length - (tally.error || 0) - (tally.later || 0), failed: tally.error || 0, tally, cost_usd: cost,
                 openrouter: ors.summary(), ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.21.0 (fix 3): central pages read with a pinned model; recorded as proposals for a person to approve
    // v0.59.5 (3 Nov 2026, CF-247 P0 autonomous operations; workstream A interface request, contract ops-diagnose-v1 of migration
    // 20261104100000): AI-assisted diagnosis of integration issues the deterministic classifier diagnosed with low confidence (ops-diagnose.ts).
    // public.svc_ops_diagnosis_next leases requests only while ops.ai_diagnosis_on is 1 and inside the AI guards (daily ceiling, lane cap
    // ops.ai_diagnosis_usd_per_day); each carries its pinned model, instructions and response_schema. One call per request through the existing
    // OpenRouter path (credential, require_parameters, the pinned model only, the answer limit a setting); every request leased is answered exactly
    // once through public.svc_ops_diagnosis_record: the contract's answer, or {error} with the cost spent (recorded, never asked again).
    if (mode === "ops_diagnose") {
      const w: any = await rpc("svc_ops_diagnosis_next", { p_limit: Math.min(Number(body.limit || 5), 20) });  // fixed: the setting batch.ops_diagnose's upper bound
      const items: any[] = Array.isArray(w?.items) ? w.items : [];
      if (!items.length) return j({ ok: true, mode, items: 0, held: w?.held ?? null, worker: WORKER });
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }).catch(() => null); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      const maxTokens = opsDiagnoseLimit(ws), ors = orStats(), tally: Record<string, number> = {}; let cost = 0, dropped = 0;
      await pool(items, 2, async (it) => {
        let out: { answer: Record<string, unknown>; cost: number; dropped_quotes: number };
        const why = !key ? "OpenRouter credential unavailable" : opsDiagnoseUsable(it) ?? (Date.now() - t0 > BUDGET_MS - 20000 ? "time budget" : null);
        if (why) out = { answer: { error: why }, cost: 0, dropped_quotes: 0 };
        else {
          try {
            const r = await cascadeFetch(ors.fetch, { service: "ops_diagnosis" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
              body: JSON.stringify(opsDiagnoseRequest(it, maxTokens)), signal: AbortSignal.timeout(60000) });  // fixed: API time-out of one call
            const d = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
            out = opsDiagnoseAnswer(d, it, maxTokens, r.ok, r.status);
          } catch (e) { out = { answer: { error: `call failed: ${(e instanceof Error ? e.message : String(e)).slice(0, 200)}` }, cost: 0, dropped_quotes: 0 } }
        }
        cost += out.cost; dropped += out.dropped_quotes;
        try {
          const res = await rpc("svc_ops_diagnosis_record", { p_id: Number(it.id), p_answer: out.answer, p_cost_usd: out.cost });
          const st = String(res?.state || "recorded") + (res?.applied ? "_applied" : "");
          tally[st] = (tally[st] || 0) + 1;
        } catch (e) { tally.record_failed = (tally.record_failed || 0) + 1 }
      });
      return j({ ok: true, mode, items: items.length, tally, dropped_quotes: dropped, cost_usd: cost, openrouter: ors.summary(), contract: OPS_DIAGNOSE_CONTRACT, ms: Date.now() - t0, worker: WORKER });
    }
    // v0.79.0 (13 Nov 2026, CF-247 Decision 276 AER v2 step 1): the shadow course-page reader. The database picks the courses (sample, priority
    // providers, budget, switch aer.v2_shadow_on) and hands over the trial prompt version; each stored page is read once with the pinned model,
    // every record is checked by the verifier (aer-v2.ts) and the result is recorded in pipeline.aer_v2_shadow_results. Nothing is admitted.
    if (mode === AER_V2_MODE) {
      const w: any = await rpc("svc_aer_v2_shadow_next", { p_limit: Math.max(1, Math.min(Number(body.limit) || 1, 40)) });  // fixed: the setting batch.aer_v2_shadow's upper bound
      const items: any[] = Array.isArray(w?.items) ? w.items : [];
      if (!items.length) return j({ ok: true, mode, items: 0, held: w?.held ?? null, worker: WORKER });
      const ver = w?.version || {}, system = String(ver.system_text || ""), model = String(ver.model || ""), version = String(ver.version || "");
      if (!system || !model || !version || (await aerV2Sha256(system)) !== String(ver.system_sha256 || "")) {
        return j({ ok: false, mode, error: "the trial prompt text does not match its recorded sha-256 (or has no pinned model)", version, worker: WORKER }, 409);
      }
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }).catch(() => null); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", worker: WORKER }, 503);
      const refs = aerV2Refs(w?.countries, w?.qualifications), quals = (Array.isArray(w?.qualifications) ? w.qualifications : []).map((q: any) => ({ code: String(q.code), name: String(q.name) }));
      const pageChars = wsNum("reading.aer_v2_page_chars", 60000), maxTokens = wsNum("reading.aer_v2_max_tokens", 6000), quoteMax = Number(ver.quote_max_chars) || 300;  // fixed: the prompt's own quote limit when the version row has none
      // v0.88.0: a version with answer contract aer-v2-answer-v3 reads the whole page as numbered lean-md-v1 blocks and is checked by the v3 verifier
      const v3 = String(ver.answer_contract || "") === AER_V3_CONTRACT, gapMax = wsNum("reading.aer_v3_lead_in_max_blocks", 3);
      const routing = ver.routing && typeof ver.routing === "object" ? ver.routing : null, params = ver.params && typeof ver.params === "object" ? ver.params : null;
      const ors = orStats(), tally: Record<string, number> = {}; let cost = 0, passed = 0, failed = 0;
      const late = () => Date.now() - t0 > BUDGET_MS - 25000;  // fixed: time left for the last call and its record
      await pool(items, Math.max(1, Math.min(wsNum("reading.aer_v2_concurrency", 4), 8)), async (it: any) => {  // fixed: the setting's upper bound (reading.aer_v2_concurrency)
        if (late()) { tally.time_budget = (tally.time_budget || 0) + 1; return }  // not recorded: picked again by a later run
        let out: { records: any[]; checks: any[]; seen: any[]; cost: number; error: string | null } = { records: [], checks: [], seen: [], cost: 0, error: null };
        try {
          // the text the current course entry reader gives the model (page data items, then the page without navigation, header and footer)
          const raw = await readEvidenceCopy(c, String(it.storage_path)), di = pageDataItems(raw);
          const blocks = v3 ? aerV3Blocks(leanText(raw), di) : null;
          const text = blocks ? blocks.text : (di ? `Page data fields:\n${di}\n\n` : "") + htmlToText(raw.replace(/<(nav|header|footer)\b[\s\S]*?<\/\1>/gi, " "));
          if (text.length > pageChars) out.error = `page_too_long: ${text.length} characters, more than reading.aer_v2_page_chars (${pageChars}); a cut page is never read`;
          else {
            // v0.89.0: a version that pins its providers (#1137 routing, allow_fallbacks off) is sent to one model only, never moved down the cascade with
            // another model's provider pins (the call is then exactly as before; a refusal is recorded as the read's error)
            const r = await cascadeFetch(ors.fetch, { models: routing ? null : ver.models, deadline: t0 + BUDGET_MS - 25000, service: "entry_requirements_v2_shadow" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
              body: JSON.stringify(blocks
                ? aerV3Request(model, system, aerV3User({ title: it.title, provider: it.provider, provider_country: it.provider_country, level: it.level, url: it.url }, quals, blocks), maxTokens, routing, params)
                : aerV2Request(model, system, aerV2User({ title: it.title, provider: it.provider, provider_country: it.provider_country, level: it.level, url: it.url }, quals, text), maxTokens)),
              signal: AbortSignal.timeout(90000) });  // fixed: API time-out of one call
            const d = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
            const ans = aerV2Answer(d, sentModel(d, model)); out.cost = ans.cost; (out as any).model = sentModel(d, model);
            if (!r.ok) out.error = `HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`;
            else if (!ans.ok) out.error = ans.error;
            else { const v = blocks ? aerV3Verify(ans.a, blocks, refs, quoteMax, gapMax) : aerV2Verify(ans.a, text, refs, quoteMax); out = { ...out, records: v.records, checks: v.checks, seen: v.seen_not_mapped }; passed += v.passed; failed += v.failed }
          }
        } catch (e) { out.error = `read failed: ${(e instanceof Error ? e.message : String(e)).slice(0, 200)}` }
        cost += out.cost;
        try {
          await rpc("svc_aer_v2_shadow_record", { p_course_id: it.course_id, p_prompt_version: version, p_model: String((out as any).model || model), p_evidence_id: it.evidence_id ?? null, p_content_hash: it.content_hash ?? null,
            p_records: out.records, p_checks: out.checks, p_seen_not_mapped: out.seen, p_cost_usd: out.cost, p_error: out.error, p_worker: WORKER.slice(0, 40) });
          tally[out.error ? "error" : "read"] = (tally[out.error ? "error" : "read"] || 0) + 1;
        } catch { tally.record_failed = (tally.record_failed || 0) + 1 }
      });
      return j({ ok: true, mode, version, model, items: items.length, tally, records_passed: passed, records_failed: failed, cost_usd: cost, openrouter: ors.summary(), ms: Date.now() - t0, worker: WORKER });
    }
    // v0.88.0 (14 Nov 2026, CF-247 Lean AI Input Phase 1b step 1, Platform Admin 14 Nov 2026 11:37; admin LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md
    // §4): the offline recall check of the section selector. The database hands over labelled cases (a stored page and a value a person or a
    // tested adapter took from it); each page is turned into the platform's one [B#] block form (aer-v2.ts aerV3Blocks over leanText, BLOCK_INPUT lean-blocks-v1, the same blocks the AER v2 reader sees), the field's sections are selected (lean-sections-v1)
    // and the case records whether the value is on the page at all, inside the first enrich.page_chars characters the current reader sends, in the
    // converted page and in the selected sections. Stored copies only: no AI call, no scraper credit, no live fetch; nothing is admitted or changed.
    if (mode === "lean_sections_eval") {
      const items: any[] = await rpc("svc_lean_sections_eval_next_v1", { p_limit: Math.max(1, Math.min(Number(body.limit) || 1, 200)) });  // fixed: the setting batch.lean_sections_eval's upper bound
      if (!Array.isArray(items) || !items.length) return j({ ok: true, mode, items: 0, worker: WORKER });
      const cut = Number(ws?.["enrich.page_chars"] ?? 24000) || 24000;
      const rows: any[] = [], tally: Record<string, number> = {};
      await pool(items, 4, async (it) => {  // fixed: stored-copy reads at once (storage only)
        const row: any = { case_id: it.case_id, selector: LEAN_SECTIONS, converter: BLOCK_INPUT, worker: WORKER };
        try {
          if (Date.now() - t0 > BUDGET_MS - 15000) { row.error = "time budget"; return }
          const raw = await readEvidenceCopy(c, String(it.storage_path));
          const gold: string[] = Array.isArray(it.gold) ? it.gold.map(String) : [], f = String(it.field);
          const di = pageDataItems(raw), stripped = raw.replace(/<(nav|header|footer)\b[\s\S]*?<\/\1>/gi, " ");
          // the text the current reader of this field is given, before its cut
          const current = f === "entry_requirements" ? (di ? `Page data fields:\n${di}\n\n` : "") + htmlToText(stripped)
            : f === "description" || f === "deadline" ? courseTextPage(raw, Number.MAX_SAFE_INTEGER)
            : (di ? `Page data fields:\n${di}\n\n` : "") + mainText(raw);
          const ab = aerV3Blocks(leanText(raw), di), whole = blockPlain(ab), sel = selectSections(ab, f, SEC_OPT);
          // v0.92.0: a page with nothing selected is sent whole (design §3, "a page with no selection is sent in full"), so it is checked whole
          const selText = sel.no_selection ? whole : sel.plain;  // v0.91.0: matched on the blocks' words without their [B#] labels (a quote may run across adjacent blocks); page data lines always travel (design §3.5)
          Object.assign(row, { page_chars: current.length, cut_chars: cut, lean_chars: whole.length, lean_blocks: ab.blocks.length,
            gold_in_page: holds(current, gold) || holds(whole, gold) || holds(raw, gold), gold_in_current: holds(current, gold),
            gold_in_first_cut: holds(current.slice(0, cut), gold), gold_in_lean: holds(whole, gold), gold_in_selection: holds(selText, gold),
            no_selection: sel.no_selection, selected_blocks: sel.blocks, selected_chars: sel.chars, block_ids: sel.block_ids.slice(0, 400) });
          tally[row.gold_in_selection ? "held" : row.gold_in_page ? "missed" : "not_on_page"] = (tally[row.gold_in_selection ? "held" : row.gold_in_page ? "missed" : "not_on_page"] || 0) + 1;
        } catch (e) { row.error = (e instanceof Error ? e.message : String(e)).slice(0, 200); tally.error = (tally.error || 0) + 1 }
        finally { rows.push(row) }
      });
      const rec = await rpc("svc_lean_sections_eval_record_v1", { p_rows: noNul(rows) });
      return j({ ok: true, mode, items: items.length, tally, recorded: rec, selector: LEAN_SECTIONS, converter: BLOCK_INPUT, ai_calls: 0, ms: Date.now() - t0, worker: WORKER });
    }
    if (mode === "central_ai") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: any[] = await rpc("svc_central_ai_next", { p_limit: Math.min(Number(body.limit || 6), 10) });
      const centralTokens = answerLimit(ws, "central_page");
      const tally: Record<string, number> = {}; let cost = 0;
      await pool(items, 3, async (it) => {
        let usedModel = String(it.model || ""); const rec = async (x: Record<string, unknown>) => { const res = await rpc("svc_central_ai_record", { p_queue_id: it.queue_id, p_parsed: null, p_cost: 0, p_error: null, ...x }); if (usedModel !== String(it.model || "")) await rpc("svc_ai_model_answered_v1", { p_source: "central_ai_queue", p_source_id: String(it.queue_id), p_model: usedModel }).catch(() => null); return res };
        if (Date.now() - t0 > BUDGET_MS - 25000) { await rec({ p_error: "time budget" }); return }
        try {
          const md = await storedHtml(it.storage_path);
          // v0.59.7 (CF-247 decision 5 Nov 2026, calendar-v2): an academic calendar is read whole in slices, with dated starts, deadlines, meaning,
          // scope and the reader's notes; every value proven on the page (calendar.ts). English policy pages are read as before.
          if (it.kind === "intake_calendar") {
            const calTokens = wsNum("reading.calendar_answer_tokens", centralTokens);
            const { slices, cut } = calendarSlices(md, wsNum("reading.calendar_slice_chars", 24000), wsNum("reading.calendar_max_slices", 4));
            const answers: any[] = []; let c2 = 0;
            for (let k = 0; k < slices.length; k++) {
              const r = await cascadeFetch(fetch, { models: (it as any).models, deadline: t0 + BUDGET_MS - 25000, service: it.kind === "intake_calendar" ? "calendar_reading" : "central_english_policy", source: "central_ai_queue", source_id: it.queue_id }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
                body: JSON.stringify(calendarAiRequest(it.model, { provider: it.provider || "", url: it.url, text: slices[k], notes: it.notes || null, slice: slices.length > 1 ? `${k + 1} of ${slices.length}` : undefined }, calTokens)), signal: AbortSignal.timeout(60000) });
              const d = await r.json().catch(() => ({}));
              const ans = readAnswer(d, "central_page", calTokens, `slice ${k + 1} of ${slices.length}`); c2 += ans.cost; cost += ans.cost;
              if (!r.ok) throw readError(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, c2);
              if (d?.model && !String(d.model).startsWith(sentModel(d, it.model))) throw readError(`returned model ${d.model}, not ${it.model}`, c2);
              usedModel = sentModel(d, it.model);
              if (!ans.ok) throw readError(ans.error, c2);
              answers.push(ans.a);
            }
            const parsed = calendarAiParsed(answers, md, `ai:${it.model_code}:${CALENDAR_READER}`, cut, String(it.url || ""));  // v2.2: the address may give the edition year (Decision 270)
            const res = await rec({ p_parsed: parsed, p_cost: c2 });
            tally[String(res?.status || "recorded")] = (tally[String(res?.status || "recorded")] || 0) + 1;
            return;
          }
          const text = md.slice(0, 24000);
          const r = await cascadeFetch(fetch, { models: (it as any).models, deadline: t0 + BUDGET_MS - 25000, service: it.kind === "intake_calendar" ? "calendar_reading" : "central_english_policy", source: "central_ai_queue", source_id: it.queue_id }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(centralAiRequest(it.model, it.kind, { provider: it.provider || "", url: it.url, text }, centralTokens)), signal: AbortSignal.timeout(60000) });
          const d = await r.json().catch(() => ({})); usedModel = sentModel(d, it.model);
          // v0.54.0 (W32): a cut answer is named and never parsed; the call's cost is kept on the error
          const ans = readAnswer(d, "central_page", centralTokens), c1 = ans.cost; cost += c1;
          if (!r.ok) throw readError(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, c1);
          if (d?.model && !String(d.model).startsWith(sentModel(d, it.model))) throw readError(`returned model ${d.model}, not ${it.model}`, c1);
          if (!ans.ok) throw readError(ans.error, c1);
          const parsed = centralAiParsed(it.kind, ans.a, text, `ai:${it.model_code}`);
          const res = await rec({ p_parsed: parsed, p_cost: c1 });
          tally[String(res?.status || "recorded")] = (tally[String(res?.status || "recorded")] || 0) + 1;
        } catch (e) { await rec({ p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400), p_cost: errorCost(e) }); tally.error = (tally.error || 0) + 1 }  // v0.54.0 (W32): cost recorded on a failed read
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.59.7 (CF-247 decision 5 Nov 2026 §2, §7, job calendar-reread): stored academic calendar documents read again by the current reader,
    // with no paid page read. The dated parser first (its reading recorded as its own proposal for the existing approval); the existing central-page
    // AI queue only when the parser gives no current or future dated teaching start or the address is not a trusted main teaching calendar.
    if (mode === "calendar_reread") {
      // v0.59.8: documents read by an earlier calendar reader are read again; only those still needed (svc_calendar_reread_next_v2)
      const docs: { id: string; provider_id: string; url: string; storage_path: string; trusted_address: boolean }[] = await rpc("svc_calendar_reread_next_v2", { p_limit: Math.min(Number(body.limit || 20), 100) /* fixed: guards a malformed call only; the run size is setting batch.calendar_reread (maximum 100) */, p_reader: CALENDAR_READER });
      const tally: Record<string, number> = {};
      await pool(docs, 4, async (d) => {
        try {
          if (Date.now() - t0 > BUDGET_MS) throw Error("time budget");
          const md = await storedHtml(d.storage_path);
          const parsed = { ...calendarStarts(md), parser: CALENDAR_PARSER_DATES };
          const safe = calendarSafe(parsed, d.trusted_address);
          const r = await rpc("svc_calendar_reread_record_v2", { p_id: d.id, p_parsed: parsed, p_send_to_ai: !safe.safe, p_reason: safe.reason, p_error: null, p_reader: CALENDAR_READER });
          const k = safe.safe ? "dated_by_parser" : r?.sent_to_ai ? "sent_to_ai" : "no_dates"; tally[k] = (tally[k] || 0) + 1;
        } catch (e) {
          await rpc("svc_calendar_reread_record_v2", { p_id: d.id, p_parsed: null, p_send_to_ai: false, p_reason: null, p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400), p_reader: CALENDAR_READER }).catch(() => null);
          tally.failed = (tally.failed || 0) + 1;
        }
      });
      // v0.59.8 (mandate 5 Nov 2026 12:44 R2): stale editions of needed calendars are handed to the existing provider-facts reads, within the
      // database's credit budget (svc_calendar_refresh_v1 decides and records; this mode itself fetches nothing)
      const refresh = await rpc("svc_calendar_refresh_v1", { p_reader: CALENDAR_READER }).catch((e) => ({ error: (e instanceof Error ? e.message : String(e)).slice(0, 200) }));
      return j({ ok: true, mode, reader: CALENDAR_READER, documents: docs.length, tally, refresh, paid_reads: 0, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.47.0 (CF-247 Track C, entry requirements step A): the entry matrix reader. Phase 1 reads entry pages not held yet (stored copies
    // are taken by the database first): direct, robots.txt respected (a disallowed page is never fetched another way); Firecrawl only when
    // the site refuses a direct read. Phase 2 reads each new stored page version with the pinned model, in slices for large tables, and
    // records the rows; the database proposes them and sends the run to Layer 4. Nothing runs while entry.matrix_enabled is 0.
    // v0.48.5 (27 Oct 2026, Platform Admin 05:46: D5 and D4 tests "must use the stored source pages"): mode entry_inspect returns, for at
    // most 12 entry-matrix sources, the stored copy's h1, title and raw table markup with its content hash. Read only: no AI call, no web
    // fetch, no write. Size-capped per page (entry.inspect_chars is not a setting: this is a diagnostic cap, fixed below).
    if (mode === "entry_inspect") {
      const ids = (Array.isArray(body.source_ids) ? body.source_ids : []).slice(0, 12);  // fixed: diagnostic batch cap
      const rows: { source_id: string; url: string; storage_path: string | null; mime: string | null; content_hash: string | null }[] = await rpc("svc_entry_matrix_inspect_paths", { p_source_ids: ids });
      const out: unknown[] = [];
      for (const r of rows) {
        try {
          if (!r.storage_path) { out.push({ source_id: r.source_id, url: r.url, error: "no stored copy" }); continue }
          const { data, error } = await c.storage.from("evidence").download(r.storage_path); if (error || !data) throw Error(error?.message || "missing");
          const b = new Uint8Array(await data.arrayBuffer());
          const t = b[0] === 0x1f && b[1] === 0x8b ? await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).text() : new TextDecoder().decode(b);
          const pick = (re: RegExp) => (t.match(re) || [])[0] || "";
          const tables = t.match(/<table\b[\s\S]*?<\/table>/gi) || [];
          const html = [pick(/<title[^>]*>[\s\S]*?<\/title>/i), pick(/<h1[^>]*>[\s\S]*?<\/h1>/i), ...tables].join("\n").slice(0, 120000);  // fixed: diagnostic size cap
          out.push({ source_id: r.source_id, url: r.url, content_hash: r.content_hash, storage_path: r.storage_path, sha256: await sha256(new TextEncoder().encode(t)), tables: tables.length, chars: t.length, html });
        } catch (e) { out.push({ source_id: r.source_id, url: r.url, error: (e instanceof Error ? e.message : String(e)).slice(0, 200) }) }
      }
      return j({ ok: true, mode, pages: out, worker: WORKER, workerVersion: VERSION });
    }
    if (mode === "entry_ai") {
      const limit = Math.min(Number(body.limit || 4), 20);
      // v0.70.0 (F-AER.03): asked once a call; a failure leaves qualification-first off for this call (the rows are dropped as before)
      const qualsP: Promise<any> = rpc("svc_aer_qualifications_v1", {}).catch(() => null);
      const fetchTally: Record<string, number> = {};
      const toFetch: { source_id: string; provider_id: string; url: string; country: string | null }[] = await rpc("svc_entry_matrix_fetch_next", { p_limit: limit });
      // v0.50.0 (AER programme Step B): a PDF entry table is read directly (robots.txt respected), never through Firecrawl (its rendered text
      // has no positions to prove columns from), within the size cap the database gives (entry.pdf_max_bytes); kept whole, gzipped
      const readPdf = async (url: string, maxBytes: number) => {
        let http: number | null = null;
        try {
          const u = new URL(url);
          if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) return { status: "robots_disallowed", http, bytes: null as Uint8Array | null };
          const r = await fetch(u, { headers: { "user-agent": UA, accept: "application/pdf" }, redirect: "follow", signal: AbortSignal.timeout(30000) });  // fixed: API time-out
          http = r.status;
          if (!r.ok) { await r.body?.cancel(); return { status: [401, 403, 406, 429].includes(r.status) ? "blocked_pdf" : r.status === 404 || r.status === 410 ? "gone" : "fetch_failed", http, bytes: null } }
          const b = new Uint8Array(await r.arrayBuffer());
          if (b.length > maxBytes) return { status: "pdf_too_large", http, bytes: null };
          if (!(b[0] === 0x25 && b[1] === 0x50 && b[2] === 0x44 && b[3] === 0x46)) return { status: "not_pdf", http, bytes: null };  // %PDF
          return { status: "read", http, bytes: b };
        } catch { return { status: "fetch_failed", http, bytes: null } }
      };
      await pool(toFetch, 4, async (it: any) => {
        const frec = (x: Record<string, unknown>) => rpc("svc_entry_matrix_fetch_record", { p_source_id: it.source_id, p_status: "failed", p_via: null, p_http: null, p_storage_path: null, p_sha256: null, p_mime: null, p_error: null, ...x });
        try {
          if (it.pdf === true) {
            const p = await readPdf(it.url, Number(it.pdf_max_bytes) || 20000000);
            if (p.status === "robots_disallowed") { await frec({ p_status: "robots_disallowed", p_http: p.http }); fetchTally.robots = (fetchTally.robots || 0) + 1; return }
            // v0.80.0 (Platform Admin 12 Nov 2026 20:23: "use firecrawl for http is refused and store the artifact as evidence in storage"): a PDF the provider's
            // server refuses (401, 403, 406, 429) is fetched once through Firecrawl (reading.entry_pdf_firecrawl_on), within the Firecrawl budget check, and its
            // text (Firecrawl's PDF parse, markdown) is stored in the evidence bucket like any page and read as text. It has no column positions, so the PDF
            // cell and grid readers do not apply; every quote is still checked against this stored copy.
            if (!p.bytes && p.status === "blocked_pdf" && Number(ws["reading.entry_pdf_firecrawl_on"]) >= 1) {
              const g = await useFcWhy("fc_read", it.provider_id, it.url, true);  // v0.80.1: the reads share (reading one page), not the central discovery share
              if (!g.ok) { await frec({ p_http: p.http, p_error: `blocked_pdf; firecrawl: ${g.why}` }); fetchTally[String(g.why)] = (fetchTally[String(g.why)] || 0) + 1; return }
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(scrapeBody(it.url, { read_formats: ["markdown"], read_proxy: FC_PROXY }, String(it.country || ""))), signal: AbortSignal.timeout(90000) });  // fixed: API time-out
              const d = await r.json().catch(() => ({}));
              const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
              if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: "fc_read", p_provider_id: it.provider_id, p_url: it.url });
              const md = String(d?.data?.markdown || ""), http = Number(d?.data?.metadata?.statusCode ?? r.status);
              if (!r.ok || md.length < 200) { await frec({ p_http: http, p_error: `blocked_pdf; firecrawl: ${d?.error || "no content"}`.slice(0, 400) }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
              const sha = await sha256(new TextEncoder().encode(md));
              const path = `layer2/${it.country || "XX"}/entry-matrix/${it.provider_id}/${it.source_id}/${sha}.md.gz`;
              const up = await c.storage.from("evidence").upload(path, await gzip(md), { contentType: "application/gzip", upsert: true });
              if (up.error) { await frec({ p_http: http, p_error: "storage: " + up.error.message }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
              await frec({ p_status: "read", p_via: "firecrawl", p_http: http, p_storage_path: path, p_sha256: sha, p_mime: "text/markdown" });
              fetchTally.pdf_firecrawl = (fetchTally.pdf_firecrawl || 0) + 1; return;
            }
            if (!p.bytes) { await frec({ p_http: p.http, p_error: p.status }); fetchTally[p.status] = (fetchTally[p.status] || 0) + 1; return }
            const sha = await sha256(p.bytes);
            const path = `layer2/${it.country || "XX"}/entry-matrix/${it.provider_id}/${it.source_id}/${sha}.pdf.gz`;
            const up = await c.storage.from("evidence").upload(path, await gzip(p.bytes), { contentType: "application/gzip", upsert: true });
            if (up.error) { await frec({ p_http: p.http, p_error: "storage: " + up.error.message }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
            await frec({ p_status: "read", p_via: "direct", p_http: p.http, p_storage_path: path, p_sha256: sha, p_mime: "application/pdf" });
            fetchTally.pdf = (fetchTally.pdf || 0) + 1; return;
          }
          // v0.50.0 (AER programme Step C): a page whose requirements are drawn by the browser (entry.render_hosts) is read once rendered
          // through Firecrawl (rawHtml, waiting entry.render_wait_ms), robots.txt respected, within the Firecrawl budget check; stored as HTML
          // and read like any page. A rendered page that publishes no minimum gives no rows: the provider stays "contact provider".
          if (it.render === true) {
            const u = new URL(it.url);
            if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) { await frec({ p_status: "robots_disallowed" }); fetchTally.robots = (fetchTally.robots || 0) + 1; return }
            const g = await useFcWhy("provider_facts_scrape", it.provider_id, it.url, true);
            if (!g.ok) { await frec({ p_error: g.why }); fetchTally[String(g.why)] = (fetchTally[String(g.why)] || 0) + 1; return }
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(scrapeBody(it.url, { read_formats: ["rawHtml"], read_proxy: FC_PROXY, read_wait_ms: Number(it.render_wait_ms) || 5000 }, String(it.country || ""))), signal: AbortSignal.timeout(90000) });  // fixed: API time-out
            const d = await r.json().catch(() => ({}));
            const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
            if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: "provider_facts_scrape", p_provider_id: it.provider_id, p_url: it.url });
            const html = pageHtml(d), http = Number(d?.data?.metadata?.statusCode ?? r.status);
            if (!r.ok || html.length < 200) { await frec({ p_http: http, p_error: d?.error || "no rendered content" }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
            const sha = await sha256(new TextEncoder().encode(html));
            const path = `layer2/${it.country || "XX"}/entry-matrix/${it.provider_id}/${it.source_id}/${sha}.html.gz`;
            const up = await c.storage.from("evidence").upload(path, await gzip(html), { contentType: "application/gzip", upsert: true });
            if (up.error) { await frec({ p_http: http, p_error: "storage: " + up.error.message }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
            await frec({ p_status: "read", p_via: "firecrawl", p_http: http, p_storage_path: path, p_sha256: sha, p_mime: "text/html" });
            fetchTally.rendered = (fetchTally.rendered || 0) + 1; return;
          }
          const d1 = await readDirect(it.url);
          let body1 = "", via = "direct", mime = "text/html", http = d1.http;
          if (d1.status === "robots_disallowed") { await frec({ p_status: "robots_disallowed", p_http: http }); fetchTally.robots = (fetchTally.robots || 0) + 1; return }
          if (d1.status === "read") body1 = d1.html;
          else if (d1.status === "blocked" || d1.status === "too_thin") {
            const g = await useFcWhy("provider_facts_scrape", it.provider_id, it.url, true);
            if (!g.ok) { await frec({ p_error: g.why, p_http: http }); fetchTally[String(g.why)] = (fetchTally[String(g.why)] || 0) + 1; return }
            // v0.50.2 (AER programme, HTML Firecrawl-fallback route): the page's own HTML is kept (rawHtml), not markdown, so its tables are read
            // row by row (table-rows-v1) and quotes are checked against the same lines as a direct read (AUT, Wintec, Lincoln, Otago lost rows
            // as quote_not_on_page against markdown tables)
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(scrapeBody(it.url, { read_formats: ["rawHtml"], read_proxy: FC_PROXY }, String(it.country || ""))), signal: AbortSignal.timeout(90000) });  // fixed: API time-out
            const d = await r.json().catch(() => ({}));
            const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
            if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: "provider_facts_scrape", p_provider_id: it.provider_id, p_url: it.url });
            http = Number(d?.data?.metadata?.statusCode ?? r.status); body1 = pageHtml(d); via = "firecrawl"; mime = "text/html";
            if (!r.ok || body1.length < 200) { await frec({ p_http: http, p_error: d?.error || "no content" }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
          } else { await frec({ p_http: http, p_error: d1.status }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
          const sha = await sha256(new TextEncoder().encode(body1));
          const path = `layer2/${it.country || "XX"}/entry-matrix/${it.provider_id}/${it.source_id}/${sha}.${mime === "text/html" ? "html" : "md"}.gz`;
          const up = await c.storage.from("evidence").upload(path, await gzip(body1), { contentType: "application/gzip", upsert: true });
          if (up.error) { await frec({ p_http: http, p_error: "storage: " + up.error.message }); fetchTally.failed = (fetchTally.failed || 0) + 1; return }
          await frec({ p_status: "read", p_via: via, p_http: http, p_storage_path: path, p_sha256: sha, p_mime: mime });
          fetchTally[via] = (fetchTally[via] || 0) + 1;
        } catch (e) { await frec({ p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400) }); fetchTally.failed = (fetchTally.failed || 0) + 1 }
      });
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, fetched: fetchTally, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      // a stored copy may be gzip (this lane, the provider-facts lane) or plain (older course-page copies)
      const storedText = async (path: string, mimeType: string | null, pdfMaxPages = 40, nameNumbers = false): Promise<{ text: string; lines: EntryLineSet; manifest: EntryManifest; emptyLines: string[]; pdf?: PdfResult; pdfPages?: any[]; named?: number }> => {
        const { data, error } = await c.storage.from("evidence").download(path); if (error || !data) throw Error(error?.message || "missing");
        const b = new Uint8Array(await data.arrayBuffer());
        // v0.50.0 (Step B): a stored PDF is rebuilt from its own drawn rules and proven (pdf.ts) before anything is read; its text is the
        // proven table lines, each cell named by its column header
        if (/pdf/i.test(String(mimeType || "")) || /\.pdf(\.gz)?$/i.test(path)) {
          const raw = b[0] === 0x1f && b[1] === 0x8b ? new Uint8Array(await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).arrayBuffer()) : b;
          const doc = await getDocumentProxy(raw); const { OPS } = await getResolvedPDFJS();
          const pages = await pdfPages(doc, OPS, pdfMaxPages), t = pdfTables(pages);
          return { text: t.text, lines: Object.assign([] as EntryBandLine[], { forms: t.forms }) as EntryLineSet, manifest: { status: "none", reason: "stored copy is a PDF", heading: "", entries: [], columns: [], footnotes: [] } as EntryManifest, emptyLines: [] as string[], pdf: t, pdfPages: pages };
        }
        const t = b[0] === 0x1f && b[1] === 0x8b ? await new Response(new Blob([b]).stream().pipeThrough(new DecompressionStream("gzip"))).text() : new TextDecoder().decode(b);
        // v0.48.1: tables as whole rows, a merged or blank row label carried down; v0.48.2: with the band each line publishes (entryTables)
        // v0.48.3: and the source-table manifest the completeness guard compares the read with (entryManifest)
        // v0.48.7 (D4): with the band tables' data lines that publish no minimum (entryManifestDetail)
        if (/html/i.test(String(mimeType || "")) || /\.html?(\.gz)?$/i.test(path) || /^\s*<(!doctype|html)/i.test(t)) { const tb = entryTables(t, htmlToText, nameNumbers), md = entryManifestDetail(t, htmlToText); return { text: tb.text, lines: tb.lines, manifest: md.manifest, emptyLines: md.emptyLines, named: tb.named } }
        return { text: t, lines: [] as EntryBandLine[], manifest: { status: "none", reason: "stored copy is not HTML", heading: "", entries: [], columns: [], footnotes: [] } as EntryManifest, emptyLines: [] as string[] };
      };
      // v0.48.4 (D2): the country reference list, read once per call when a page under the guard needs it
      let countryList: EntryCountryRef[] | null = null;
      const countryRefs = async () => countryList ??= ((await rpc("svc_entry_country_refs_v1", {})) || []) as EntryCountryRef[];
      const items: any[] = await rpc("svc_entry_matrix_next", { p_limit: limit });
      const tally: Record<string, number> = {}; let cost = 0, pdfTaken = 0;
      await pool(items, 2, async (it) => {
        const rec = (x: Record<string, unknown>) => rpc("svc_entry_matrix_record", { p_run_id: it.run_id, p_result: null, p_cost: 0, p_error: null, ...x });
        if (Date.now() - t0 > BUDGET_MS - 30000) { await rec({ p_error: "time budget" }); return }
        // v0.74.1 (12 Nov 2026, F-AER.08 production verification: UNSW's grid read was stopped by the call's CPU limit after Sydney and UQ in the same call): a call reads
        // at most reading.entry_pdf_per_call stored PDFs; a further PDF goes back to the queue without spending a try (time budget, no cost) for the next call
        if (/\.pdf($|[?#])/i.test(String(it.url || "")) && pdfTaken++ >= Math.max(1, Number(ws["reading.entry_pdf_per_call"]) || 1)) { await rec({ p_error: "time budget" }); tally.pdf_deferred = (tally.pdf_deferred || 0) + 1; return }
        let c1 = 0;
        try {
          const stored = await storedText(it.storage_path, it.mime, Number(it.pdf_max_pages) || 40, it.completeness_required !== true), page = stored.text;
          // v0.50.0 (Step B): a PDF whose tables are not proven, or a PDF source without a stored PDF, is held before any AI read, for every
          // provider (not only those under the completeness guard); the reason names the page and the text
          // v0.73.0 (F-AER.08, reading.entry_grid_reader_on): a PDF whose tables have no drawn rules but print one aligned course-by-qualification grid per page
          // (UNSW, Sydney, UQ) is proven by alignment (pdf-grid.ts: every value in exactly one column, fail closed) and read cell by cell without the model
          const gridAll = stored.pdf && stored.pdfPages && Number(ws["reading.entry_grid_reader_on"]) >= 1 ? pdfGrids2(stored.pdfPages) : null;
          const grid = gridAll && gridAll.status === "ok" && gridAll.tables.length > 0 ? gridAll : null;
          if (stored.pdf && stored.pdf.status !== "ok" && !grid) {
            await rec({ p_error: `held_unparsed: PDF ${stored.pdf.reason}${gridAll && gridAll.status !== "ok" ? `; grid ${gridAll.reason}` : ""}`.slice(0, 400), p_result: { rows: [], dropped: [], completeness: { status: "unparsed", reason: stored.pdf.reason }, worker: WORKER, prompt_version: ENTRY_PROMPT_VERSION, page_basis: PDF_METHOD, pdf: { status: stored.pdf.status, tables: stored.pdf.tables.length } } });
            tally.held_unparsed = (tally.held_unparsed || 0) + 1; return;
          }
          // v0.80.0: a refused PDF's Firecrawl text (stored as text/markdown by the fetch fallback above) is read as text; any other non-PDF copy of a PDF is held
          if (!stored.pdf && /\.pdf($|[?#])/i.test(String(it.url || "")) && !/markdown/i.test(String(it.mime || ""))) {
            await rec({ p_error: "held_unparsed: PDF source without a stored PDF copy", p_result: { rows: [], dropped: [], completeness: { status: "unparsed", reason: "no stored PDF" }, worker: WORKER, prompt_version: ENTRY_PROMPT_VERSION, page_basis: PDF_METHOD } });
            tally.held_unparsed = (tally.held_unparsed || 0) + 1; return;
          }
          // v0.48.3: a provider under the completeness guard whose stored tables cannot be read as a manifest is held before any AI read;
          // v0.48.4 (D2): so is a table that is not one country's (requirement-type columns, or a heading that names no country). Held
          // unparsed is terminal in the database (state failed, no retry); the logged re-read can bring it back.
          // v0.59.5 (workstream C, RMIT IB and GAC pages; reading.entry_global_pages_on, ships off): a page whose heading names a global
          // qualification and that says the qualification applies whatever the country is not held for naming no country (entry.ts)
          const globalQ = Number(ws["reading.entry_global_pages_on"]) >= 1 && stored.manifest.status === "ok"
            ? entryGlobalQualification(stored.manifest.heading, page, Array.isArray(ws["reading.entry_global_qualifications"]) ? ws["reading.entry_global_qualifications"] as string[] : [],
                                       Array.isArray(ws["reading.entry_global_phrases"]) ? ws["reading.entry_global_phrases"] as string[] : []) : null;
          stored.manifest.global = globalQ;  // entryNonCountryShape: a global-qualification page is not held for naming no country
          const nonCountry = it.completeness_required === true && stored.manifest.status === "ok" ? entryNonCountryShape(stored.manifest, await countryRefs()) : null;
          // v0.48.8 (PR A, R2): a column of bare numbers on a page that prints no scale is a source hold, before any AI read
          const unscaled = it.completeness_required === true && stored.manifest.status === "ok" && !nonCountry ? entryUnscaledColumns(stored.manifest) : [];
          if (it.completeness_required === true && (stored.manifest.status !== "ok" || nonCountry || unscaled.length)) {
            const completeness = entryCompleteness(stored.manifest, []);
            const why = nonCountry ? `not a country table: ${nonCountry}` : unscaled.length ? `no printed scale: bare numbers in ${unscaled.join("; ")}` : (stored.manifest.reason || stored.manifest.status);
            await rec({ p_error: `held_unparsed: ${why}`.slice(0, 400), p_result: { rows: [], dropped: [], completeness: { ...completeness, status: "unparsed", reason: why }, worker: WORKER, prompt_version: ENTRY_PROMPT_VERSION, page_basis: ENTRY_TABLE_BASIS } });
            tally.held_unparsed = (tally.held_unparsed || 0) + 1; return;
          }
          // v0.59.5 (workstream C, UWA China ranges; reading.entry_range_lower_bound_on, ships off): a value within one printed range is its lower
          // bound (entry.ts entryRangeLower), carried to the parser with the page's line structure
          stored.lines.rangeLower = Number(ws["reading.entry_range_lower_bound_on"]) >= 1;
          // v0.59.11 (8 Nov 2026, CF-247 AER reader quality): governed country aliases (reading.entry_country_aliases, switch reading.entry_country_aliases_on)
          // and a number with no printed basis left out of a row whose grade text is printed (switch reading.entry_value_null_on); both ship off
          // v0.70.0 (12 Nov 2026, CF-247 F-AER.03 qualification-first): international qualifications and every-country words from the database (svc_aer_qualifications_v1);
          // with them a row naming no ISO country is kept for a recognised qualification and sent as a qualification row (the database decides and records it)
          const quals = await qualsP;
          const parseOpts = { countryAliases: Number(ws["reading.entry_country_aliases_on"]) >= 1 ? entryCountryAliases(ws["reading.entry_country_aliases"]) : {},
                              nullValue: Number(ws["reading.entry_value_null_on"]) >= 1,
                              // v0.74.0 (F-AER.10): reader fixes, each under its own setting (entry.ts EntryParseOptions)
                              ...(Number(ws["reading.entry_quote_parts_on"]) >= 1 ? { quoteParts: { window: Number(ws["reading.entry_quote_window_chars"]) || 600 } } : {}),
                              bandLabelWords: Array.isArray(ws["reading.entry_band_label_words"]) ? ws["reading.entry_band_label_words"] : [],
                              qualificationCountries: entryQualificationCountries(ws["reading.entry_qualification_countries"]),
                              ...(quals?.on && Array.isArray(quals.qualifications) ? { qualifications: quals.qualifications, globalTokens: Array.isArray(quals.global_tokens) ? quals.global_tokens : [] } : {}) };
          // v0.49.2: slice size and answer length from settings (entry.matrix_slice_chars, entry.matrix_max_tokens)
          const slices = entrySlices(page, Number(it.max_rows) || 400, Number(it.slice_chars) || 24000);
          const rows: any[] = [], dropped: any[] = [], qrows: any[] = []; let edition: string | null = null, intake_year: number | null = null;
          // v0.51.0: the slices of one page are read entry.matrix_slice_concurrency at a time (1 = one after another, as before), so a long
          // table fits the call's time; results are joined in slice order; the first failure fails the read once every slice has settled
          let parts: { parsed: any; nm: any }[] = new Array(slices.length); let failed: unknown = null;
          // v0.71.0 (F-AER.07 PDF cell reader, reading.entry_cell_reader_on): a proven PDF table with one line per cell (a country, education board or international
          // qualification by study-level columns) is read cell by cell without the model (entry-cells.ts); its rows go through the same checks as a model's answer
          const cellRead = stored.pdf && Number(ws["reading.entry_cell_reader_on"]) >= 1
            ? entryCellRead(page, await countryRefs(), quals?.on && Array.isArray(quals.qualifications) ? quals.qualifications : [], parseOpts.countryAliases,
                            { minLevels: Number(ws["reading.entry_cell_min_levels"]) || 4, minLines: Number(ws["reading.entry_cell_min_lines"]) || 20 }) : null;
          if (cellRead) {
            const parsed = entryMatrixParsed(cellRead.answer, page, stored.lines, parseOpts);
            parts = [{ parsed: { ...parsed, dropped: [...parsed.dropped, ...cellRead.dropped] }, nm: { rows: parsed.rows, dropped: [] } }];
          }
          // v0.73.0 (F-AER.08): the aligned grid gives one row per course and qualification column; its rows go through the same checks as a model's answer
          const gridRead = !cellRead && grid
            ? entryGridRead(grid.tables, await countryRefs(), quals?.on && Array.isArray(quals.qualifications) ? quals.qualifications : [], entryGridHeadingList(ws["reading.entry_grid_headings"]), parseOpts.countryAliases)
            : null;
          if (gridRead) {
            const parsed = entryMatrixParsed(gridRead.answer, grid!.text, Object.assign([] as EntryBandLine[], { forms: [] }) as EntryLineSet, parseOpts);
            parts = [{ parsed: { ...parsed, dropped: [...parsed.dropped, ...gridRead.dropped] }, nm: { rows: parsed.rows, dropped: [] } }];
          }
          if (!cellRead && !gridRead) await pool([...slices.keys()], Math.max(1, Math.min(Number(it.slice_concurrency) || 1, 12)), async (i) => {  // fixed: the setting's upper bound (entry.matrix_slice_concurrency)
           if (failed) return;
           try {
            if (Date.now() - t0 > BUDGET_MS - 20000) throw Error("time budget");
            const r = await cascadeFetch(fetch, { service: "entry_matrices" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
              // v0.48.7 (D4): a one-slice page with a readable band table goes with its published cells (a cell list in every slice would ask for each cell more than once)
              body: JSON.stringify(entryMatrixRequest(it.model, { provider: it.provider || "", url: it.url, text: slices[i], slice: slices.length > 1 ? `${i + 1} of ${slices.length}` : undefined, cells: slices.length === 1 ? entryCellList(stored.manifest) : undefined, note: stored.pdf ? PDF_NOTE : stored.named ? NAMED_NOTE : undefined }, Number(it.max_tokens) || 8000)), signal: AbortSignal.timeout(90000) });
            // v0.51.0: a reply that cannot be read (cut by the call's time-out while it streamed) is named, not taken as an empty answer
            const d = await r.json().catch((e) => ({ unreadable: e instanceof Error ? `${e.name}: ${e.message}` : String(e) }));
            if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`);
            if (d?.model && !String(d.model).startsWith(it.model)) throw Error(`returned model ${d.model}, not ${it.model}`);  // pinned: no other model's answer is used
            c1 += Number(d?.usage?.cost || 0);
            const content = String(d?.choices?.[0]?.message?.content || "");
            // v0.50.2: an empty answer says why (the provider's error or finish reason, as OpenRouter returns it); the read is unchanged
            if (!content.trim()) throw Error(`the model returned no answer${entryNoAnswerWhy(d, i + 1, slices.length)}`);
            // v0.49.2: an answer cut off at its length limit is named (not a JSON error); smaller slices or a larger limit are settings
            if (d?.choices?.[0]?.finish_reason === "length") throw Error(`output_truncated: slice ${i + 1} of ${slices.length} reached entry.matrix_max_tokens`);
            // v0.52.0: stored.lines carries the page's structure forms and header rows (EntryLineSet), so a printed cell quoted with its structure is found
            const parsed = entryMatrixParsed(JSON.parse(content), page, stored.lines, parseOpts);  // quotes are checked against the whole stored page
            const nm = entryDropNoMinimum(stored.manifest, stored.emptyLines, parsed.rows);  // v0.48.7 (D4): rows for lines that publish no minimum
            parts[i] = { parsed, nm };
           } catch (e) { failed ??= e }
          });
          if (failed) throw failed;
          for (const { parsed, nm } of parts) { rows.push(...nm.rows); dropped.push(...parsed.dropped, ...nm.dropped); edition ??= parsed.edition; intake_year ??= parsed.intake_year }
          // v0.70.0 (F-AER.03): the slices' qualification rows, in slice order; a row read twice in a slice overlap is kept once
          for (const { parsed } of parts) for (const q of parsed.qualification_rows || []) {
            const k = [q.qualification_code, q.study_level, q.min_grade, q.min_value, q.quote].join("|");
            if (!qrows.some((y) => [y.qualification_code, y.study_level, y.min_grade, y.min_value, y.quote].join("|") === k)) qrows.push(q);
          }
          cost += c1;
          // v0.48.3: the whole read is compared with the source-table manifest; a read that is not complete proposes nothing (held, kept, retried
          // within entry.matrix_attempts by the database)
          const completeness = entryCompleteness(stored.manifest, rows);
          // v0.59.5 (workstream C, UWA AP subject equivalences; reading.entry_subject_rows_on, ships off): rows of one identity that each name a
          // subject become one subject-prerequisite row, after completeness is checked on the rows as read
          const subj = Number(ws["reading.entry_subject_rows_on"]) >= 1 ? entrySubjectRows(rows) : { rows, merged: 0 };
          rows.splice(0, rows.length, ...subj.rows);
          const result = { rows, ...(qrows.length ? { qualification_rows: qrows } : {}), dropped, edition, intake_year, slices: cellRead || gridRead ? 0 : slices.length, worker: WORKER,
                           ...(cellRead ? { reader: ENTRY_CELL_READER, cell_reader: { ...cellRead.stats, levels: cellRead.levels } } : {}),
                           ...(gridRead ? { reader: ENTRY_GRID_READER, cell_reader: { ...gridRead.stats, tables: grid!.tables.length, method: grid!.method,
                                             columns_unmapped: gridRead.columns.filter((c) => c.kind === "unknown").map((c) => c.head) } } : {}), prompt_version: ENTRY_PROMPT_VERSION, page_basis: stored.pdf ? PDF_METHOD : ENTRY_TABLE_BASIS, completeness,
                           ...(subj.merged ? { subject_rows_merged: subj.merged } : {}), ...(globalQ ? { global_qualification: globalQ } : {}),
                           ...(stored.pdf ? { pdf: { tables: stored.pdf.tables.length, rows: stored.pdf.tables.reduce((a, t) => a + t.rows, 0) } } : {}) };
          if (it.completeness_required === true && completeness.status !== "complete") {
            await rec({ p_error: `held_incomplete: ${completeness.reason || completeness.status}`.slice(0, 400), p_result: result, p_cost: c1 });
            tally.held_incomplete = (tally.held_incomplete || 0) + 1; return;
          }
          const res = await rec({ p_result: result, p_cost: c1 });
          tally[String(res?.status || "recorded")] = (tally[String(res?.status || "recorded")] || 0) + 1;
        } catch (e) { cost += c1; await rec({ p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400), p_cost: c1 }); tally.error = (tally.error || 0) + 1 }
      });
      return j({ ok: true, mode, fetched: fetchTally, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.35.0 (21 Oct 2026): AI fee reader. One stored fee page a call to the pinned model; the database decides what is admitted.
    if (mode === "fee_ai") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: any[] = await rpc("svc_fee_ai_next", { p_limit: Math.min(Number(body.limit || 3), 40) });  // fixed: the setting's upper bound (fees.pages_per_run); the time check below requeues what does not fit
      const tally: Record<string, number> = {}; let cost = 0; const ors = orStats(); const feeTokens = answerLimit(ws, "fee_page");
      await pool(items, Math.max(1, Math.min(Number(body.concurrency || 2), 16)), async (it) => {  // fixed: the setting's upper bound (fees.concurrency)
        const rec = (x: Record<string, unknown>) => rpc("svc_fee_ai_record", { p_queue_id: it.queue_id, p_result: null, p_cost: 0, p_error: null, ...x });
        if (Date.now() - t0 > BUDGET_MS - 40000) { await rec({ p_error: "time budget" }); return }
        try {
          const md = await storedHtml(it.storage_path);
          // v0.41.0 (23 Oct 2026): a course's own page is stored as HTML; it is read as page text
          const text = noNul(it.course_page ? htmlToText(md) : md).slice(0, Number(it.page_chars || 40000));
          // v0.36.0 (22 Oct 2026, NZ review fix 6): no money amount on the page, no fee table: recorded as no rows without an AI call
          if (!hasFeeAmount(text)) { const res = await rec({ p_result: { rows: [], quotes_missing: 0, more_fee_pages: [], page_notes: "", skipped: "no_amount", model: it.model }, p_cost: 0 }); tally.no_amount = (tally.no_amount || 0) + 1; for (const [k, v] of Object.entries(res || {})) if (typeof v === "number") tally[k] = (tally[k] || 0) + v; return }
          const r = await cascadeFetch(ors.fetch, { models: (it as any).models, deadline: t0 + BUDGET_MS - 25000, service: "fee_reader", source_id: it.id }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(feeAiRequest(it.model, { provider: it.provider || "", country: it.country, url: it.url, notes: it.notes, profile: it.profile, findings: it.findings || [], courses: it.courses || [], course_page: it.course_page === true }, text, feeTokens)),
            signal: AbortSignal.timeout(90000) });
          const d = await r.json().catch(() => ({}));
          // v0.54.0 (W32): the answer now has a limit (reading.answer_tokens.fee_page; none was sent before, so the model's own applied); a cut
          // answer is named and no row of it is proposed; the call's cost is kept on the error
          const ans = readAnswer(d, "fee_page", feeTokens), c1 = ans.cost; cost += c1;
          if (!r.ok) throw readError(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, c1);
          if (d?.model && !String(d.model).startsWith(sentModel(d, it.model))) throw readError(`returned model ${d.model}, not ${it.model}`, c1);
          if (!ans.ok) throw readError(ans.error, c1);
          const parsed = feeAiParsed(ans.a, text, new Set((it.courses || []).map((x: any) => String(x.id))));
          const res = await rec({ p_result: { ...parsed, model: String(d?.model || it.model) }, p_cost: c1 });
          for (const [k, v] of Object.entries(res || {})) if (typeof v === "number") tally[k] = (tally[k] || 0) + v;
        } catch (e) { await rec({ p_error: (e instanceof Error ? e.message : String(e)).slice(0, 400), p_cost: errorCost(e) }); tally.error = (tally.error || 0) + 1 }  // v0.54.0 (W32): cost recorded on a failed read
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, openrouter: ors.summary(), ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.22.0 (14 Oct 2026, CF-247 v2.15.273, Platform Admin 10:41: "a job to enrich data for specific or multiple fields across uni or
    // countries using scraper and ai"): the AI step of the Enrich fields job. Stored course pages are read for the asked fields (each
    // value must quote the page), titles are classified (field of study, level), a university's campus names become one campus list,
    // and a provider's address is read from its stored contact page or, when the job allows the scraper, its home page read once.
    // The pinned central-pages model is used. The database checks every code again and applies only missing values.
    // v0.57.0 (CF-247 P1 provider descriptions, Platform Admin 2 Nov 2026 10:28): one provider's official About / Overview page, stored copy
    // first, then a pinned-model description whose every sentence quotes the page. The database validates, proposes to Layer 4 and admits
    // nothing by itself; this mode never writes a description.
    if (mode === "provider_description") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", worker: WORKER }, 503);
      const descriptionLimit = Math.min(Number(body.limit || 3), 10);  // fixed: the setting's upper bound (batch.provider_description)
      // The lease names the reservation protocol this worker follows; the database gives no item to a worker that does not.
      const w: any = await rpc("svc_provider_description_lease_v1", { p_limit: descriptionLimit, p_cohort: body.cohort_id ? String(body.cohort_id) : null, p_protocol: DESCRIPTION_WORKER_PROTOCOL });
      const items: any[] = w?.items || [];
      if (!items.length) return j({ ok: true, mode, idle: true, reason: w?.reason || "nothing due", items: 0, worker: WORKER });
      const model = String(w.model || ""), pageChars = Number(w.page_chars) || 16000, minQuote = Number(w.min_quote_chars) || 20;
      // v0.69.0: the prompt from Settings (a version string and its text), or null for the built-in prompt v2
      const prompt = w.prompt && typeof w.prompt.system === "string" && w.prompt.system.trim().length >= 200 && w.prompt.version ? { version: String(w.prompt.version), system: String(w.prompt.system) } : null;  // fixed: the table's own minimum
      const buildRequest = (it: any, rec: any, page: string) => prompt ? promptRequest(model, prompt.system, String(it.provider || ""), String(rec.url || ""), page, maxTokens, w.length)
        : descriptionRequest(model, String(it.provider || ""), String(rec.url || ""), page, maxTokens, w.length, Number(w.verbatim_span_max_chars));
      const patterns: string[] = (w.about_patterns || []).map(String);
      const maxTokens = wsNum(DESCRIPTION_ANSWER_KEY, 1500), ors = orStats(), out: any[] = [], tally: Record<string, number> = {};
      let cost = 0;
      const late = () => Date.now() - t0 > BUDGET_MS - 25000;
      let pricingLookup: Promise<any> | null = null;
      const modelPrices = () => pricingLookup ||= (async () => {
        tally.pricing_lookups = (tally.pricing_lookups || 0) + 1;
        try {
          const response = await ors.fetch("https://openrouter.ai/api/v1/models", { method: "GET", headers: { authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(15000) }); // fixed: read-only pricing API time-out.
          return response.ok ? await response.json().catch(() => null) : null;
        } catch { return null }
      })();
      const readStoredCopy = async (path: string) => {
        const { data, error } = await c.storage.from("evidence").download(path); if (error || !data) throw Error(error?.message || "stored copy missing");
        const buf = new Uint8Array(await data.arrayBuffer());
        if (buf[0] === 0x1f && buf[1] === 0x8b) return await new Response(new Blob([buf]).stream().pipeThrough(new DecompressionStream("gzip"))).text();
        return new TextDecoder().decode(buf);
      };
      // a page on the provider's own hosts: direct first (robots.txt respected); Firecrawl only when the site refuses or the page is too thin
      const acquireDirect = w.acquire_direct === true, acquireFc = w.acquire_firecrawl === true;  // off until the pilot cost is approved (Decision 7)
      // the pilot's hard Firecrawl ceiling (pdesc.firecrawl_reads_max, less the reads already made): never more reads than the database allows
      let fcLeft = Math.max(0, Math.floor(Number(w.firecrawl_left) || 0)); const fcBy = new Map<string, number>();
      const readPage = async (url: string, it: any) => {
        const d1 = await readDirect(url);
        if (d1.status === "read") return { ok: true, html: d1.html, via: "direct", http: d1.http, url: d1.finalUrl };
        if (d1.status === "robots_disallowed") return { ok: false, why: "robots_disallowed", http: d1.http };
        if (d1.status !== "blocked" && d1.status !== "too_thin") return { ok: false, why: d1.status, http: d1.http };
        if (!acquireFc) return { ok: false, why: `${d1.status}; Firecrawl off`, http: d1.http };
        if (fcLeft <= 0) return { ok: false, why: `${d1.status}; Firecrawl ceiling reached`, http: d1.http };
        fcLeft -= 1; fcBy.set(String(it.item_id), (fcBy.get(String(it.item_id)) || 0) + 1);
        if (it.on_demand === true) {
          // v0.69.0: Fill description (an operator asked): the daily shares do not apply; the account's monthly limit and credit reserve still do
          const g = await useFcWhy("provider_description_on_demand", it.provider_id, url, true);
          if (!g.ok) return { ok: false, why: String(g.why), http: d1.http, retry: true };
        } else {
        const g = await useFcWhy("provider_description", it.provider_id, url, true);
        if (!g.ok) return { ok: false, why: String(g.why), http: d1.http, retry: true };
        }
        const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(scrapeBody(url, { read_formats: ["rawHtml"], read_proxy: FC_PROXY }, String(it.country || ""))), signal: AbortSignal.timeout(90000) });  // fixed: API time-out
        const d = await r.json().catch(() => ({}));
        const extra = Math.max(0, Number(d?.data?.metadata?.creditsUsed ?? d?.creditsUsed ?? 1) - 1);
        if (extra > 0) await rpc("svc_coverage_usage", { p_units: extra, p_purpose: it.on_demand === true ? "provider_description_on_demand" : "provider_description", p_provider_id: it.provider_id, p_url: url });
        const html = pageHtml(d), http = Number(d?.data?.metadata?.statusCode ?? r.status);
        return r.ok && html.length >= 200 ? { ok: true, html, via: "firecrawl", http, url: String(d?.data?.metadata?.url || d?.data?.metadata?.sourceURL || url) } : { ok: false, why: String(d?.error || "no content"), http, retry: true };
      };
      await pool(items, 2, async (it: any) => {
        const base = { item_id: it.item_id, model, prompt_version: prompt ? prompt.version : DESCRIPTION_PROMPT_VERSION, worker: WORKER.slice(0, 60) };
        if (late()) { out.push({ ...base, retry: true, reason: "time budget" }); return }
        const hosts: string[] = (it.hosts || []).map(String);
        let html = "", rec: any = {};
        try {
          // 1 reuse: the stored copy of the provider's own About page
          if (it.stored?.storage_path) {
            html = await readStoredCopy(String(it.stored.storage_path));
            rec = { stored_evidence_id: it.stored.evidence_id, url: it.stored.url };
            tally.stored = (tally.stored || 0) + 1;
          } else {
            if (!acquireDirect) { out.push({ ...base, retry: true, reason: "no stored copy and acquisition is off" }); return }
            // 2 discover: the About page the central page finder suggested, else the About / Overview link of the home page, on the provider's own hosts only
            const pageRule = w.page_rule || {};  // v0.58.0: the page rule's lists (settings), the same rule as the database
            const suggested: string[] = (it.candidates || []).map(String).filter((u: string) => aboutPageCheck(u, hosts, patterns, pageRule).ok);
            if (!it.website && !suggested.length) { out.push({ ...base, rule: "no_website", reason: "the provider has no website" }); return }
            // the site's own home page (a website held as a section, such as /international, is read from its origin)
            let target = suggested[0] || "";
            if (!target) {
              let home: string; try { home = new URL(/^https?:/i.test(it.website) ? String(it.website) : "https://" + it.website).origin + "/" } catch { out.push({ ...base, rule: "no_website", reason: "the website address cannot be read" }); return }
              const h = await readPage(home, it);
              if (!h.ok) { out.push(h.retry ? { ...base, retry: true, reason: `home page not read: ${h.why}` } : { ...base, rule: h.why === "robots_disallowed" ? "robots_disallowed" : "home_not_read", reason: `home page not read: ${h.why}` }); return }
              if (!ownHost(new URL(h.url || home).hostname, hosts)) { out.push({ ...base, rule: "wrong_host", reason: "The home page redirected away from the approved provider hosts." }); return }
              const links = aboutLinks(h.html, h.url || home, hosts, patterns, pageRule);
              if (!links.length) { out.push({ ...base, rule: "no_about_page", reason: "no About or Overview link on the home page" }); return }
              target = links[0].url;
            }
            const tc = aboutPageCheck(target, hosts, patterns, pageRule);
            if (!tc.ok) { out.push({ ...base, rule: tc.rule, reason: "the page found is not the provider's own About or Overview page" }); return }
            // 3 acquire: the About page, stored gzipped as evidence
            const a = await readPage(target, it);
            if (!a.ok) { out.push(a.retry ? { ...base, retry: true, reason: `About page not read: ${a.why}` } : { ...base, rule: a.why === "robots_disallowed" ? "robots_disallowed" : "about_not_read", reason: `About page not read: ${a.why}` }); return }
            const finalUrl = String(a.url || target), finalCheck = aboutPageCheck(finalUrl, hosts, patterns, pageRule);
            if (!finalCheck.ok) { out.push({ ...base, rule: finalCheck.rule, reason: "The final About-page address after redirects is not an approved institutional source.", fetch: { status: "refused", url: finalUrl } }); return }
            html = a.html;
            const sha = await sha256(new TextEncoder().encode(html));
            const path = `layer2/${it.country || "XX"}/provider-description/${it.provider_id}/${sha}.html.gz`;
            const up = await c.storage.from("evidence").upload(path, await gzip(html), { contentType: "application/gzip", upsert: true });
            if (up.error) { out.push({ ...base, retry: true, reason: "storage: " + up.error.message }); return }
            rec = { fetch: { status: "read", via: a.via, url: finalUrl, http: a.http, storage_path: path, sha256: sha, mime: "text/html" }, url: finalUrl };
            tally[a.via] = (tally[a.via] || 0) + 1;
          }
          // 4 extract: the pinned model; every sentence with the page's exact words
          const page = descriptionPageText(html, pageChars);
          const sourceCheck = aboutPageCheck(String(rec.url || ""), hosts, patterns, w.page_rule || {});
          if (!sourceCheck.ok) { out.push({ ...base, ...rec, rule: sourceCheck.rule, reason: "The stored source is not an approved About or Overview page." }); return }
          // v0.59.13: the strict proof first; when it fails, the registry evidence (the page is on the provider's own verified host, the headings name the provider or a registry abbreviation and nothing else)
          const proofTrace: IdentityTrace = {};  // v0.63.0: filled by the proof while it runs; diagnostics only
          const identity = descriptionSourceIdentity(html, page, Array.isArray(it.identity_names) ? it.identity_names.map(String) : [String(it.provider || "")], { url: String(rec.url || ""), hosts }, proofTrace);
          rec.identity_check = { ...identity, reader_behavior_version: "provider-description-source-guard-v5" };
          if (!identity.ok) rec.identity_check.seen = { ...descriptionIdentitySeen(html), proof: proofTrace };  // v0.62.0: a failed proof also records what the page showed it (checks.identity.seen); which pages pass is unchanged
          if (!identity.ok) { out.push({ ...base, ...rec, rule: identity.rule, reason: "The page does not prove the provider's current full institutional identity; no AI call was made." }); return }
          if (!prompt && (!Number.isInteger(Number(w.verbatim_span_max_chars)) || Number(w.verbatim_span_max_chars) < 1)) { out.push({ ...base, ...rec, rule: "invalid_verbatim_limit", reason: "The governed quotation-copy limit is unavailable; no AI call was made." }); return }
          const request = buildRequest(it, rec, page);
          const quote = descriptionCostQuote(request, await modelPrices());
          if (!quote.ok) { out.push({ ...base, ...rec, rule: quote.reason, reason: "The exact approved model has no verified non-negative pricing bound; no AI call was made." }); return }
          const reservation = await rpc("svc_provider_description_reserve_v1", { p_item: String(it.item_id), p_model: model, p_max_cost: quote.max_cost_usd, p_source_hash: String(rec.fetch?.sha256 || it.stored?.content_hash || "") || null });
          rec.ai_reservation = { ...quote, quote_source: "https://openrouter.ai/api/v1/models", quoted_at: new Date().toISOString(), reservation };
          if (reservation?.ok !== true) { out.push({ ...base, ...rec, rule: String(reservation?.reason || "ai_budget_refused"), reason: "The existing governed AI budget refused the conservative per-call reservation; no AI call was made." }); return }
          rec.cost_known = false; // Unknown charges retain their reservation until reconciled; a timeout is never assumed free.
          rec.ai_call_started = true;
          tally.ai_calls = (tally.ai_calls || 0) + 1;
          const r = await cascadeFetch(ors.fetch, { service: "provider_description" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify({ ...request, provider: { ...request.provider, max_price: quote.provider_max_price } }), signal: AbortSignal.timeout(60000) });  // fixed: API time-out of one call
          const d = await r.json().catch(() => ({}));
          rec.cost_known = d?.usage?.cost != null && String(d.usage.cost).trim() !== "" && Number.isFinite(Number(d.usage.cost)) && Number(d.usage.cost) >= 0;
          const ans = descriptionAnswer(d, maxTokens); cost += ans.cost;
          if (!r.ok) { out.push({ ...base, ...rec, error: `HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, cost: ans.cost }); return }
          if (d?.model && !String(d.model).startsWith(model)) { out.push({ ...base, ...rec, error: `returned model ${d.model}, not ${model}`, cost: ans.cost }); return }  // pinned: no other model's answer is used
          if (!ans.ok) { out.push({ ...base, ...rec, error: ans.error, cost: ans.cost }); return }
          if (prompt) {
            // v0.69.0: the prompt carries the wording; every passage is checked against the page here and the database applies the prompt profile
            out.push({ ...base, ...rec, answer: promptSentences(ans.a, page, minQuote), cost: ans.cost });
            tally.read = (tally.read || 0) + 1; tally.prompt = (tally.prompt || 0) + 1;
            return;
          }
          const claimCheck = descriptionClaimCheck(ans.a, Number(w.verbatim_span_max_chars));
          // v0.60.0: a copied sentence (verbatim_passage) is not a reason to hold the whole answer; the database leaves that sentence out and keeps the rest. Any other failure still holds it.
          if (!claimCheck.ok && claimCheck.rule !== "verbatim_passage") { out.push({ ...base, ...rec, answer: providerDescriptionSentences(ans.a, page, minQuote, { fragments: Number(ws["reading.provider_quote_fragments_on"]) >= 1 }), quality_hold: claimCheck, cost: ans.cost }); return }
          // 5 the quotes are checked against the page here; the database repeats every other check
          out.push({ ...base, ...rec, answer: providerDescriptionSentences(ans.a, page, minQuote, { fragments: Number(ws["reading.provider_quote_fragments_on"]) >= 1 }), cost: ans.cost });
          tally.read = (tally.read || 0) + 1;
        } catch (e) { out.push({ ...base, ...rec, error: (e instanceof Error ? e.message : String(e)).slice(0, 300), cost: errorCost(e) }); tally.error = (tally.error || 0) + 1 }
      });
      for (const o of out) o.fc_reads = fcBy.get(String(o.item_id)) || 0;  // each Firecrawl read is counted against the ceiling
      // v0.61.0: one record call for each item, so one slow item cannot roll back the others' ai_calls, cost and reservation settle; a failed item is tried once more (the next fire settles what is still left)
      const recorded: Record<string, number> = {}, recordErrors: string[] = [];
      for (const o of out) {
        let done = false, last = "";
        for (let attempt = 0; attempt < 2 && !done; attempt++) {  // fixed: one retry of a failed record
          try {
            const part: any = await rpc("svc_provider_description_record", { p_results: noNul([o]) });
            for (const [k, v] of Object.entries(part || {})) recorded[k] = (recorded[k] || 0) + Number(v || 0);
            done = true;
          } catch (e) { last = (e instanceof Error ? e.message : String(e)).slice(0, 200) }
        }
        if (!done) recordErrors.push(`${String(o.item_id)}: ${last}`);
      }
      return j({ ok: recordErrors.length === 0, mode, model, items: items.length, tally, recorded, ...(recordErrors.length ? { record_errors: recordErrors } : {}), cost_usd: cost, openrouter: ors.summary(), ms: Date.now() - t0, worker: WORKER }, recordErrors.length ? 500 : 200);
    }
    if (mode === "enrich_ai") {
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) { const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE }); const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof?.id }); key = typeof data === "string" ? data : "" }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", worker: WORKER }, 503);
      const w: any = await rpc("svc_enrich_ai_next", { p_limit: Math.min(Number(body.limit || 12), 40) });
      // v0.85.0: the description, the entry requirements and the other fields each have their own route (w.routes); w.model is kept for a database
      // that does not hand out routes yet
      const routes: any = w?.routes || {};
      const model = String(routes.course_other_fields?.model || w?.model || ""), descModel = String(routes.course_description?.model || w?.model || ""), askModels = new Set<string>(), out: any[] = []; const tally: Record<string, number> = {}; let cost = 0; const ors = orStats();
      const on = (page: string, q: string) => { const fq = flat(q); return fq.length >= 4 && flat(page).includes(fq) };
      // v0.54.0 (CF-247 decision W32): the answer limit of each read is a setting (reading.answer_tokens.<read>, answer.ts; it was a fixed
      // 2,000 tokens here). A cut answer (finish_reason length, or not JSON at the limit) is held_partial: output_truncated and never parsed,
      // and the cost of every call is carried on its error so the failed items record it (it was lost: cost_usd 0 on every cut read).
      const ASK_READ: Record<string, ReadType> = { course_fields: "course_fields", titles: "course_titles", campus_regions: "campus_regions", campus_list: "campus_lists", address: "provider_address" };
      const ask = async (system: string, user: string, name: string, schema: unknown, mdl: string = model) => {
        const read = ASK_READ[name] || "course_fields", maxTokens = answerLimit(ws, read);
        const r = await cascadeFetch(ors.fetch, { models: mdl === model ? routes.course_other_fields?.models : null, deadline: t0 + BUDGET_MS - 25000, service: mdl === descModel && mdl !== model ? "course_description" : "course_other_fields" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
          body: JSON.stringify({ model: mdl, temperature: 0, max_tokens: maxTokens, provider: { require_parameters: true }, response_format: { type: "json_schema", json_schema: { name, strict: true, schema } },
            messages: [{ role: "system", content: system }, { role: "user", content: user }] }), signal: AbortSignal.timeout(60000) });  // fixed: API time-out of one call
        const d = await r.json().catch(() => ({}));
        const ans = readAnswer(d, read, maxTokens, name); cost += ans.cost;
        if (!r.ok) throw readError(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, ans.cost);
        if (d?.model && !String(d.model).startsWith(sentModel(d, mdl))) throw readError(`returned model ${d.model}, not ${mdl}`, ans.cost);
        if (!ans.ok) throw readError(ans.error, ans.cost);
        askModels.add(sentModel(d, mdl)); return { a: ans.a, cost: ans.cost };
      };
      // v0.49.0 (28 Oct 2026, Track C Step B B1): a course's academic entry requirements with the pinned entry model.
      // Rows keep the page's exact words; a row whose quote is not on the page is dropped here; the database applies the B1 rules
      // (basis printed with a score, band printed, no English test, audience from the quote) and proposes the rows for a person.
      // v0.53.0 (29 Oct 2026, CF-247 AER decision W29): the page is read in bounded slices (course-entry.ts). The answer limit was a fixed 2,000
      // tokens here, and three Monash pages with long per-country minimum lists were cut mid-answer ("Unterminated string in JSON"); a page
      // is now read whole or held, every slice answered whole or the read held (held_partial, retried by the database within its tries),
      // and the cost of every call made is recorded, also when the read fails.
      const ENTRY_PROMPT = COURSE_ENTRY_PROMPT_VERSION;
      // v0.59.4 (CF-247 Workstream C): a course's description and application deadline on the stored page only
      // v0.72.0 (12 Nov 2026, CF-247 F-CDESC, Admin PR #430): the description has its OWN call with the pinned prompt cdesc-source-grounded-v1 over the
      // page's numbered source spans (course-text.ts cdesc*); the deadline keeps prompt course-text-v2 in its own call. The length re-ask is retired.
      const textRead = async (pg: any, raw: string, items: any[]) => {
        const page = courseTextPage(raw, PAGE_CHARS), maxTokens = courseTextAnswerLimit(ws);
        const askText = async (req: unknown, service = "course_other_fields") => {
          const r = await cascadeFetch(ors.fetch, { models: (req as any)?.model === descModel ? routes.course_description?.models : routes.course_other_fields?.models, deadline: t0 + BUDGET_MS - 25000, service }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(req), signal: AbortSignal.timeout(60000) });  // fixed: API time-out of one call
          const d = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
          const a = courseTextAnswer(d, maxTokens); cost += a.cost;
          if (!r.ok) throw readError(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`, a.cost);
          if (d?.model && !String(d.model).startsWith(sentModel(d, String((req as any)?.model || model)))) throw readError(`returned model ${d.model}, not ${model}`, a.cost);  // pinned: no other model's answer is used
          if (!a.ok) throw readError(a.error, a.cost);
          return Object.assign(a, { model: sentModel(d, String((req as any)?.model || model)) });
        };
        const descIt = items.filter((x: any) => String(x.field) === "description"), dlIt = items.filter((x: any) => String(x.field) === "deadline");
        // a failed call fails only its own items (the other call still records)
        if (descIt.length) {
          try {
            const spans = cdescSpans(page, wsNum("enrich.course_description_min_quote_chars", 20));
            const ans = await askText(cdescRequest(descModel, cdescUser({ course_id: String(pg.course_id), title: pg.title, provider: pg.provider, study_level: pg.level ?? null, official_course_id: pg.code ?? null, source_url: pg.url ?? null }, spans), maxTokens), "course_description");
            out.push(...cdescResults(ans.a, spans, String(pg.course_id), descIt, { model: String((ans as any).model || descModel), worker: WORKER.slice(0, 40), cost: ans.cost },
              { reachShare: wsNum("enrich.course_description_claim_reach_share", 0.5), reachMinWords: wsNum("enrich.course_description_claim_reach_min_words", 2) }));
          } catch (e) { fail(descIt.map((x: any) => Number(x.item_id)), e) }
        }
        if (dlIt.length) {
          try {
            const ans = await askText(courseTextRequest(model, courseTextUser(pg.provider, pg.title, ["deadline"], page, courseTextLength(ws)), ["deadline"], maxTokens));
            out.push(...courseTextResults(ans.a, page, dlIt, { model: String((ans as any).model || model), worker: WORKER.slice(0, 40), cost: ans.cost }));
          } catch (e) { fail(dlIt.map((x: any) => Number(x.item_id)), e) }
        }
        tally.course_text = (tally.course_text || 0) + items.length;
      };
      const entryCall = async (user: string, mdl: string, maxTokens: number) => {
        const r = await cascadeFetch(ors.fetch, { models: routes.course_entry_requirements?.models, deadline: t0 + BUDGET_MS - 25000, service: "course_entry_requirements" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
          body: JSON.stringify(courseEntryRequest(mdl, user, maxTokens)), signal: AbortSignal.timeout(90000) });  // fixed: API time-out of one call
        const d = await r.json().catch((e) => ({ unreadable: e instanceof Error ? e.message : String(e) }));
        const c1 = Number(d?.usage?.cost || 0); cost += c1;
        if (!r.ok) throw Object.assign(Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 200)}`), { cost: c1 });
        if (d?.model && !String(d.model).startsWith(sentModel(d, mdl))) throw Object.assign(Error(`returned model ${d.model}, not ${mdl}`), { cost: c1 });  // pinned: no other model's answer is used
        return { d, cost: c1, model: sentModel(d, mdl) };
      };
      const entryRead = async (pg: any, raw: string, items: any[]) => {
        const em = String(w?.entry?.model || ""), chars = Number(w?.entry?.page_chars || 0);
        if (!em || !chars) { for (const x of items) out.push({ item_id: Number(x.item_id), error: "the entry model or page size is not set" }); return }
        // v0.49.1: the whole page text without navigation, header and footer (not only <main>); v0.53.0: never cut (the plan holds a longer page)
        const di = pageDataItems(raw), text = (di ? `Page data fields:\n${di}\n\n` : "") + htmlToText(raw.replace(/<(nav|header|footer)\b[\s\S]*?<\/\1>/gi, " "));
        const overlap = Number(ws["enrich.course_entry_slice_overlap_chars"]);
        const plan = courseEntryPlan(text, { pageChars: chars, sliceChars: wsNum("enrich.course_entry_slice_chars", 12000), maxSlices: wsNum("enrich.course_entry_max_slices", 10),
          overlapChars: Number.isFinite(overlap) && overlap >= 0 ? overlap : 600 });
        if (!plan.ok) {  // held before any AI call: nothing spent
          for (const x of items) out.push({ item_id: Number(x.item_id), error: `held_partial: ${plan.reason}`.slice(0, 300), cost: 0 });
          tally.entry_held = (tally.entry_held || 0) + items.length; return;
        }
        const n = plan.slices.length, maxTokens = wsNum("enrich.course_entry_max_tokens", 8000);
        // v0.59.11 (8 Nov 2026, CF-247 AER reader quality): the longest quote kept (enrich.course_entry_quote_chars, never above the 300-character column), a quote joined
        // from fragments proven fragment by fragment (switch reading.course_quote_fragments_on, ships off; each at least reading.course_entry_fragment_min_chars)
        const quoteOpts = { quoteChars: Math.min(300, wsNum("enrich.course_entry_quote_chars", 300)), fragments: Number(ws["reading.course_quote_fragments_on"]) >= 1,  // fixed: catalogue.course_entry_requirements.quote is at most 300 characters
                            minFragment: wsNum("reading.course_entry_fragment_min_chars", 6) };
        const outcomes: (CourseSliceOutcome | undefined)[] = new Array(n); const used = new Set<string>();  // the models that answered the slices
        let stop = false;  // a failed slice stops the slices not yet started (the read is held whole anyway)
        await pool(plan.slices, Math.max(1, Math.min(wsNum("enrich.course_entry_slice_concurrency", 4), 12)), async (s) => {  // fixed: the setting's upper bound (enrich.course_entry_slice_concurrency)
          if (stop) return;
          if (late()) { outcomes[s.index] = { index: s.index, ok: false, error: `time budget before slice ${s.index + 1} of ${n}`, cost: 0 }; stop = true; return }
          try {
            const { d, cost: c1, model: m1 } = await entryCall(courseEntryUser(pg.provider, pg.title, s, n, plan.page_chars), em, maxTokens); used.add(m1);
            const ans = courseEntryAnswer(d, s.index, n);
            outcomes[s.index] = ans.ok ? { index: s.index, ok: true, ...courseEntrySliceRows(ans.a, s.text, quoteOpts), cost: c1 } : { index: s.index, ok: false, error: ans.error, cost: c1 };
          } catch (e) { outcomes[s.index] = { index: s.index, ok: false, error: `slice ${s.index + 1} of ${n}: ${e instanceof Error ? e.message : String(e)}`.slice(0, 200), cost: Number((e as any)?.cost || 0) } }
          if (!outcomes[s.index]?.ok) stop = true;
        });
        const m = courseEntryMerge(plan.slices, outcomes, plan.page_chars);
        if (!m.complete) {
          for (const x of items) out.push({ item_id: Number(x.item_id), error: `held_partial: ${m.reason}`.slice(0, 300), cost: m.cost / items.length });
          tally.entry_held = (tally.entry_held || 0) + items.length; return;
        }
        const { rows, dropped } = m;
        for (const x of items) out.push({ item_id: Number(x.item_id), value: { rows, dropped, coverage: m.coverage }, quote: rows[0]?.quote ?? null, model: used.size ? [...used].join("+") : em, worker: WORKER.slice(0, 40), prompt_version: ENTRY_PROMPT,
          reason: rows.length ? null : dropped.length ? "no quoted requirement was on the page" : "the page does not state it", cost: m.cost / items.length });
        tally.entry = (tally.entry || 0) + items.length;
      };
      // v0.54.0 (W32): a failed read records its cost, shared over its items
      const fail = (ids: number[], e: unknown) => { const c1 = errorCost(e) / Math.max(1, ids.length); for (const id of ids) out.push({ item_id: id, error: (e instanceof Error ? e.message : String(e)).slice(0, 300), cost: c1 }); tally.error = (tally.error || 0) + ids.length; if (/output_truncated/.test(String((e as any)?.message || ""))) tally.held_partial = (tally.held_partial || 0) + ids.length };
      const late = () => Date.now() - t0 > BUDGET_MS - 25000;
      const strOrNull = { type: ["string", "null"] };
      // v0.23.0 (v2.15.275): how much page text the AI reads and titles per call are settings (Settings › Pipeline settings)
      const PAGE_CHARS = wsNum("enrich.page_chars", 24000), TITLE_BATCH = wsNum("enrich.title_batch", 20);
      // v0.87.0 (CF-247 Lean AI Input Phase 1, Platform Admin 13 Nov 2026 22:51; admin docs/platform/LEAN-AI-INPUT-PHASE0-BASELINE-2026-11-13.md §4): each
      // course-page read is observed (lean-input.ts): the source text length, what is sent, whether and where it is cut, the high-recall preflight on
      // the text sent and on the whole page, the sent-input hash and fingerprint. Shadow only: no request, skip, value or admission changes.
      // Rows go to public.svc_ai_input_observe_v1 at the end of the call; a failure to observe never fails a read. Off with reading.input_observe_on 0.
      // v0.92.0: the switch is read as a switch (0 is off); before, wsNum turned a 0 into the default 1
      const OBSERVE = wsOn("reading.input_observe_on", 1), observed: any[] = [];
      // v0.92.0 (CF-247 Lean AI Input Phase 1b step 2, admin docs/platform/LEAN-AI-INPUT-PHASE1B-SECTION-SELECTION-DESIGN.md §5.2): shadow selection.
      // Each observed read also records what the section selector (lean-sections.ts, over aer-v2.ts lean-blocks-v1) would send for its field: the
      // block count, characters, block ids, whether it fell back to the whole page, the preflight on the selection and the selection's SHA-256.
      // The request sent is unchanged. Off with reading.selection_shadow_on 0.
      // A page whose structured text is longer than reading.selection_shadow_max_chars is not shadowed (recorded as skipped), so the shadow's CPU
      // time stays bounded inside a paid read (the offline check hit the edge CPU limit on large fee pages); sel_ms records what the shadow took.
      const SEL_SHADOW = wsOn("reading.selection_shadow_on", 1), SEL_MAX = wsNum("reading.selection_shadow_max_chars", 200000);
      const shadowSel = async (ab: any, f: string) => {
        const t1 = Date.now(), s = selectSections(ab, f, SEC_OPT);
        return { selector: LEAN_SECTIONS, sel_input: BLOCK_INPUT, sel_blocks: s.blocks, sel_chars: s.chars, sel_no_selection: s.no_selection,
          sel_block_ids: s.block_ids.slice(0, 400),  // fixed: the recorded id list's length, a storage bound
          preflight_selection: s.signal, sel_sha256: await sha256Hex(s.text), sel_ms: Date.now() - t1 };
      };
      const observeReads = async (pg: any, raw: string, data: string) => {
        const lean = leanText(raw), sourceSha = await sha256Hex(raw), stripped = raw.replace(/<(nav|header|footer)\b[\s\S]*?<\/\1>/gi, " ");
        const fieldsSrc = (data ? `Page data fields:\n${data}\n\n` : "") + mainText(raw), textSrc = courseTextPage(raw, Number.MAX_SAFE_INTEGER);
        const di = pageDataItems(raw), entrySrc = (di ? `Page data fields:\n${di}\n\n` : "") + htmlToText(stripped), entryChars = Number(w?.entry?.page_chars || 0) || null;
        const big = SEL_SHADOW && lean.text.length > SEL_MAX, t1 = Date.now(), ab = SEL_SHADOW && !big ? aerV3Blocks(lean, di) : null, blocksMs = Date.now() - t1;
        const fieldsWant = (pg.items || []).map((x: any) => String(x.field)).filter((f: string) => f !== "entry_requirements" && !(COURSE_TEXT_FIELDS as readonly string[]).includes(f)).sort().join(",");
        for (const x of pg.items || []) {
          const f = String(x.field);
          const o = f === "entry_requirements" ? { read: "course_entry", src: entrySrc, sent: entryChars && entrySrc.length > entryChars ? "" : entrySrc, limit: entryChars, prompt: COURSE_ENTRY_PROMPT_VERSION, model: String(w?.entry?.model || ""), schema: "course_entry" }
            : f === "description" ? { read: "course_description", src: textSrc, sent: courseTextPage(raw, PAGE_CHARS), limit: PAGE_CHARS, prompt: CDESC_PROMPT_VERSION, model: descModel, schema: "cdesc" }  // v0.88.0: the description route's model (#1128), as the read sends it
            : f === "deadline" ? { read: "course_deadline", src: textSrc, sent: courseTextPage(raw, PAGE_CHARS), limit: PAGE_CHARS, prompt: COURSE_TEXT_PROMPT_VERSION, model, schema: "course_text:deadline" }
            : { read: "course_fields", src: fieldsSrc, sent: fieldsSrc.slice(0, PAGE_CHARS), limit: PAGE_CHARS, prompt: `course-fields@${WORKER}`, model, schema: `course_fields:${fieldsWant}` };
          const obs = await observation({ read: o.read, field: f, item_id: Number(x.item_id), course_id: pg.course_id ?? null, storage_path: pg.storage_path ?? null, source_text: o.src,
            sent_text: o.sent, limit_chars: o.limit, lean, prompt_key: o.prompt, model: o.model, schema_key: o.schema, worker: WORKER }, sourceSha);
          observed.push(ab ? { ...obs, ...(await shadowSel(ab, f).then((x) => ({ ...x, sel_ms: x.sel_ms + blocksMs })).catch(() => ({}))) }
            : big ? { ...obs, selector: `${LEAN_SECTIONS}:skipped-size` } : obs);  // shadow only: a selector failure records no selection
        }
      };
      // v0.22.1: stored copies are gzip (course pages) or plain (contact page snapshots); read either
      const readStored = (path: string) => readEvidenceCopy(c, path);  // v0.79.0: the same loader, shared with mode aer_v2_shadow
      // 1 stored course pages: one call per course for the fields it still needs
      // v0.43.0: pages read at once is a setting (enrich.ai_pages_at_once), sent by the database
      await pool(w?.pages || [], Math.max(1, Math.min(Number(body.concurrency || 3), 12)), async (pg: any) => {  // fixed: the setting's upper bound
        const ids = (pg.items || []).map((x: any) => Number(x.item_id));
        if (late()) { for (const id of ids) out.push({ item_id: id, retry: true, reason: "time budget" }); return }
        try {
          // v0.42.3 (23 Oct 2026, Auckland diplomas read with no campus): the page's labelled data items come first, then its main text
          const raw = await readStored(pg.storage_path), data = pageDataItems(raw);
          if (OBSERVE) await observeReads(pg, raw, data).catch(() => {});  // shadow only: never fails or changes the read
          // v0.49.0: entry requirements are read in their own call; the other fields as before
          const entryIt = (pg.items || []).filter((x: any) => String(x.field) === "entry_requirements");
          if (entryIt.length) {
            await entryRead(pg, raw, entryIt);
            pg.items = (pg.items || []).filter((x: any) => String(x.field) !== "entry_requirements");
            if (!pg.items.length) { tally.pages = (tally.pages || 0) + 1; return }
          }
          // v0.59.4: description and deadline in their own call; a failed call fails only these items
          const textIt = (pg.items || []).filter((x: any) => (COURSE_TEXT_FIELDS as readonly string[]).includes(String(x.field)));
          if (textIt.length) {
            try { await textRead(pg, raw, textIt) } catch (e) { fail(textIt.map((x: any) => Number(x.item_id)), e) }
            pg.items = (pg.items || []).filter((x: any) => !(COURSE_TEXT_FIELDS as readonly string[]).includes(String(x.field)));
            if (!pg.items.length) { tally.pages = (tally.pages || 0) + 1; return }
          }
          const page = ((data ? `Page data fields:\n${data}\n\n` : "") + mainText(raw)).slice(0, PAGE_CHARS);
          const want: string[] = (pg.items || []).map((x: any) => String(x.field));
          const props: Record<string, unknown> = {};
          for (const f of want) props[f] = { type: "object", additionalProperties: false, required: ["value", "quote"], properties: { value: strOrNull, quote: { type: "string" } } };
          const { a, cost: c1 } = await ask(
            "You read one university course page and report only what the page itself states for the course. For each field give the value and quote the exact words from the page that state it; give null when the page does not state it. " +
            "Page data fields at the top of the page text are the page's own labelled values (label: value); they are stated by the page: quote the value as written. " +
            "campus: the campus or campuses where the course is taught, as the page names them (not 'online'); some pages give them only as a short data list of location names such as [\"City\",\"South Auckland\"]: give those names and quote the list exactly. duration: the full-time length with its unit, e.g. '3 years', also when given only as a short data label such as '1 Year'. " +
            "delivery: one of on_campus, online, blended, on_campus_and_online. blended means every student mixes campus and online study within the course (for example 70% face to face and 30% online, 14 hours on campus and 6 online, or online with on-campus block weeks); on_campus_and_online means the page offers a choice of modes (for example 'On campus, Online'); if online study is only for domestic students, answer on_campus. international: 'yes' if the page says international students can apply or lists international fees, 'no' if it says domestic students only. " +
            "level: one of " + (w.levels || []).map((l: any) => `${l.code} (${l.name})`).join(", ") + ". " +
            // v0.42.0 (23 Oct 2026, Platform Admin 10:25 "cross check the gaps and accommodate the ai reader"): English and intakes too
            "english: the IELTS (Academic) requirement for this course written as 'overall/lowest band', e.g. '6.5/6.0', or just the overall, e.g. '6.0', when no band is given; quote the sentence with the IELTS score; null when the page gives no IELTS score for this course. " +
            "intakes: the months the course starts, as month names separated by commas, e.g. 'February, July', or the semesters, trimesters or terms it starts in as the page names them, e.g. 'Semester 1, Semester 2'; quote the words naming them; null when the page does not say when it starts. Never guess.",
            `University: ${pg.provider}\nCourse: ${pg.title}\nFields: ${want.join(", ")}\n` +
              // v0.36.0 (22 Oct 2026, NZ review fix 4): a field whose last quote was not on the page is asked once more, saying so
              (pg.items || []).filter((x: any) => x.hint).map((x: any) => `Note for ${x.field}: ${x.hint}; copy the words exactly as they appear on the page, or give null.\n`).join("") +
              `\nPage text:\n${page}`, "course_fields",
            { type: "object", additionalProperties: false, required: want, properties: props });
          for (const x of pg.items || []) {
            const v = a?.[x.field] || {}, val = v.value == null ? null : String(v.value).trim(), q = String(v.quote || "");
            // v0.22.2: "international" needs words about the course's students or fees, not a site footer ("International Enquiries")
            const strong = x.field === "english" ? /ielts/i.test(q) && /\b[4-9](\.[05])?\b/.test(q)
              : x.field === "intakes" ? /\b(jan|feb|mar|apr|may|jun|jul|aug|sep|oct|nov|dec)[a-z]*\b|\b(semester|trimester|term|quarter|block)\s*(\d|one|two|three|four)\b/i.test(q)
              : x.field !== "international" || /international\s*(students?|applicants?|fees?|tuition)|international\s*:\s*\$|domestic\s+(students\s+)?only|not\s+(open|available)\s+to\s+international/i.test(q);
            // v0.23.2: a duration quote about the fee basis ("fee displayed is for 1 year of study") is not the course length
            const feeLine = x.field === "duration" && /fees?\s+(displayed|shown|quoted|listed)\s+(is|are)\s+for|fees?\s+(is|are)\s+(for|based\s+on)\s+(1|one)\s+year|(per|for)\s+(1|one)\s+year\s+of\s+study|equivalent\s+to\s+\d+\s+credits/i.test(q);
            const proven = val != null && on(page, q) && strong && !feeLine;
            const value = !proven ? null : x.field === "campus" ? { campus: val } : x.field === "delivery" ? { mode: val } : x.field === "level" ? { level: val } : x.field === "international" ? { open: val.toLowerCase() === "yes" ? "true" : val.toLowerCase() === "no" ? "false" : null } : { text: val };
            // v0.36.0: the first time a quote is not on the page, the item is asked once more with a note (svc_enrich_ai_next passes the hint)
            if (val != null && !proven && strong && !feeLine && !x.hint) { out.push({ item_id: Number(x.item_id), retry: true, reason: "the quote is not on the page", cost: c1 / Math.max(1, (pg.items || []).length) }); continue }
            out.push({ item_id: Number(x.item_id), value, quote: proven ? q.slice(0, 300) : null, reason: val == null ? "the page does not state it" : proven ? null : feeLine ? "the quote is about the fee basis, not the course length" : strong ? "the quote is not on the page" : x.field === "english" ? "the quote does not name IELTS with a score" : x.field === "intakes" ? "the quote names no start month or semester" : "only a site-wide line mentions international", cost: c1 / Math.max(1, (pg.items || []).length) });
          }
          tally.pages = (tally.pages || 0) + 1;
        } catch (e) { fail(ids, e) }
      });
      // 2 titles in batches of 20: field of study and level from the title and the level already known
      const titles: any[] = w?.titles || [];
      for (let b = 0; b < titles.length; b += TITLE_BATCH) {
        const batch = titles.slice(b, b + TITLE_BATCH), ids = batch.map((x) => Number(x.item_id));
        if (late()) { for (const id of ids) out.push({ item_id: id, retry: true, reason: "time budget" }); continue }
        try {
          const { a, cost: c1 } = await ask(
            "Classify each course from its title (and its level when given). field: the one closest field code from this list: " + (w.fields || []).map((f: any) => `${f.code} ${f.name}`).join("; ") +
            ". level: one code from: " + (w.levels || []).map((l: any) => `${l.code} ${l.name}`).join("; ") + ", or null when the title does not show it.",
            batch.map((x, i) => `${i + 1}. [${x.item_id}] ${x.title}${x.level ? ` (level: ${x.level})` : ""} — ${x.provider}`).join("\n"), "titles",
            { type: "object", additionalProperties: false, required: ["courses"], properties: { courses: { type: "array", items: { type: "object", additionalProperties: false, required: ["id", "field", "level"],
              properties: { id: { type: "integer" }, field: strOrNull, level: strOrNull } } } } });
          const by = new Map<number, any>(((a?.courses || []) as any[]).map((x) => [Number(x.id), x]));
          for (const x of batch) {
            const r = by.get(Number(x.item_id));
            const value = !r ? null : x.field === "field_of_study" ? (r.field ? { field: r.field } : null) : (r.level ? { level: r.level } : null);
            out.push({ item_id: Number(x.item_id), value, quote: String(x.title).slice(0, 300), reason: value ? null : "not classified", cost: c1 / batch.length });
          }
          tally.titles = (tally.titles || 0) + batch.length;
        } catch (e) { fail(ids, e) }
      }
      // v0.42.0 (23 Oct 2026, Platform Admin 10:25: "Locations state and city are also missing"): the region (state, province, NZ
      // region) of each campus city, chosen from the country's own list; one call per university; the database keeps each city's
      // region so a city is asked once
      await pool(w?.regions || [], 2, async (u: any) => {
        if (late()) { out.push({ item_id: Number(u.item_id), retry: true, reason: "time budget" }); return }
        try {
          const names: string[] = (u.regions || []).map((r: any) => String(r));
          const { a, cost: c1 } = await ask(
            "For each campus city, give the region it is in, chosen exactly from the given list (the state, province or region of the country). Give null when the city is not clearly in one region of the list. Never guess.",
            `University: ${u.provider}\nCountry: ${u.country}\nRegions: ${names.join("; ")}\n\nCampus cities:\n${(u.cities || []).map((c: any) => `- ${c}`).join("\n")}`, "campus_regions",
            { type: "object", additionalProperties: false, required: ["cities"], properties: { cities: { type: "array", items: { type: "object", additionalProperties: false,
              required: ["city", "region"], properties: { city: { type: "string" }, region: strOrNull } } } } });
          const cities = ((a?.cities || []) as any[]).filter((x) => x && x.region && names.includes(String(x.region)) && (u.cities || []).includes(String(x.city)))
            .map((x) => ({ city: String(x.city), region: String(x.region) }));
          out.push({ item_id: Number(u.item_id), value: { cities }, quote: cities.map((x) => `${x.city}: ${x.region}`).join(" | ").slice(0, 300), cost: c1 });
          tally.regions = (tally.regions || 0) + 1;
        } catch (e) { fail([Number(u.item_id)], e) }
      });
      // 3 campus lists, one university at a time
      await pool(w?.campus_lists || [], 2, async (u: any) => {
        if (late()) { out.push({ item_id: Number(u.item_id), retry: true, reason: "time budget" }); return }
        try {
          const contact = u.storage_path ? mainText(await readStored(u.storage_path)).slice(0, Math.round(PAGE_CHARS * 2 / 3)) : "";
          const names: string[] = (u.names || []).map((n: any) => String(n.text));
          const { a, cost: c1 } = await ask(
            "These are the campus names a university's course pages give (with how many pages give each). Make the university's list of physical campuses: merge names for the same campus, " +
            "leave out 'online', distance study and anything that is not a campus. For each campus list the given names it stands for (copied exactly as given), its city, and its street address and postcode only when the contact page text quotes them.",
            `University: ${u.provider}\n\nCampus names from course pages:\n${(u.names || []).map((n: any) => `- ${n.text} (${n.pages} pages)`).join("\n")}\n\nContact page text:\n${contact || "(none stored)"}`, "campus_list",
            { type: "object", additionalProperties: false, required: ["campuses"], properties: { campuses: { type: "array", items: { type: "object", additionalProperties: false,
              required: ["name", "raw", "city", "street", "postcode", "quote"], properties: { name: { type: "string" }, raw: { type: "array", items: { type: "string" } }, city: strOrNull, street: strOrNull, postcode: strOrNull, quote: strOrNull } } } } });
          const campuses = ((a?.campuses || []) as any[]).map((x) => {
            // v0.42.4 (23 Oct 2026): a name given as a list (["City","South Auckland"]) stands for each campus in it; the database matches the same way
            const raw = (x.raw || []).filter((r: string) => names.some((n) => n === r || (flat(r).length >= 2 && flat(n).includes(flat(r)))));
            const proven = !!(contact && x.street && x.quote && on(contact, x.quote) && flat(x.quote).includes(flat(x.street)));
            const city = x.city && (names.some((n) => flat(n).includes(flat(x.city))) || (contact && on(contact, x.city))) ? x.city : null;
            return { name: String(x.name).slice(0, 120), raw, city, street: proven ? x.street : null, postcode: proven ? x.postcode : null };
          }).filter((x) => x.raw.length);
          out.push({ item_id: Number(u.item_id), value: { campuses }, quote: names.slice(0, 6).join(" | ").slice(0, 300), cost: c1 });
          tally.campus_lists = (tally.campus_lists || 0) + 1;
        } catch (e) { fail([Number(u.item_id)], e) }
      });
      // 4 provider addresses: stored contact page, else the home page read once through the scraper (when the job allows it)
      await pool(w?.addresses || [], 2, async (p: any) => {
        if (late()) { out.push({ item_id: Number(p.item_id), retry: true, reason: "time budget" }); return }
        try {
          let text = "", stored: Record<string, unknown> = {};
          if (p.storage_path) text = mainText(await readStored(p.storage_path));
          else if (p.website) {
            if (!(await useFc("enrich_address", p.provider_id, p.website, true))) { out.push({ item_id: Number(p.item_id), retry: true, reason: "no scraper credit" }); return }
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: p.website, formats: ["markdown"], onlyMainContent: false, timeout: 30000 }), signal: AbortSignal.timeout(45000) });
            const d = await r.json().catch(() => ({}));
            text = String(d?.data?.markdown || "");
            if (!r.ok || !text) throw Error(`home page not read (HTTP ${r.status})`);
            const sha = await sha256(new TextEncoder().encode(text)), path = `layer2/${p.country || "XX"}/enrich/${p.provider_id}/${sha}.md.gz`;
            const up = await c.storage.from("evidence").upload(path, await gzip(text), { contentType: "application/gzip", upsert: true });
            if (up.error) throw Error(`copy not stored: ${up.error.message}`);
            stored = { storage_path: path, sha256: sha, url: p.website };
          } else { out.push({ item_id: Number(p.item_id), value: null, reason: "no stored page and no website" }); return }
          const page = text.slice(0, Math.round(PAGE_CHARS * 5 / 6));
          const { a, cost: c1 } = await ask(
            "Find the postal street address of this education provider's main campus or head office on the page. Quote the exact words of the address from the page. Give null when the page has no street address.",
            `Provider: ${p.provider}\n\nPage text:\n${page}`, "address",
            { type: "object", additionalProperties: false, required: ["street", "city", "postcode", "quote"], properties: { street: strOrNull, city: strOrNull, postcode: strOrNull, quote: strOrNull } });
          const proven = !!(a?.street && a?.quote && on(page, a.quote) && flat(a.quote).includes(flat(a.street)));
          out.push({ item_id: Number(p.item_id), ...stored, value: proven ? { street: a.street, city: a.city, postcode: a.postcode } : null, quote: proven ? String(a.quote).slice(0, 300) : null, reason: proven ? null : "no street address quoted on the page", cost: c1 });
          tally.addresses = (tally.addresses || 0) + 1;
        } catch (e) { fail([Number(p.item_id)], e) }
      });
      // v0.23.1: a null character in page text or an AI reply cannot be stored; remove it before recording
      const noNul = (v: unknown): unknown => typeof v === "string" ? v.replace(/\u0000/g, "") : Array.isArray(v) ? v.map(noNul)
        : v && typeof v === "object" ? Object.fromEntries(Object.entries(v as Record<string, unknown>).map(([k, x]) => [k, noNul(x)])) : v;
      // v0.59.5 (workstream D interface request; mandate 15:37 §4 "do not incur a new paid read simply because a previous task failed to persist a
      // result"): the answers are kept first (public.svc_enrich_ai_stash_v1, one short insert), so a failed record is replayed from the copy, not
      // read again; a failed stash is reported and the record goes ahead
      // the model that answered goes with every result (public.svc_enrich_ai_record keeps it; the spend ledger reads it). The other-fields calls
      // name it only when every such call of this run was answered by the same model; otherwise it is left for the database to fill from the route.
      if (askModels.size === 1) for (const o of out) if (o && typeof o === "object" && !o.model && !o.error) o.model = [...askModels][0];
      const stash = out.length ? await rpc("svc_enrich_ai_stash_v1", { p_results: noNul(out) }).catch((e) => ({ error: (e instanceof Error ? e.message : String(e)).slice(0, 200) })) : {};
      const res = out.length ? await rpc("svc_enrich_ai_record", { p_results: noNul(out) }) : {};
      // v0.87.0 Lean AI Input Phase 1: the input observations, after the answers are kept and recorded (a failure is reported, never raised)
      const inputs = observed.length ? await rpc("svc_ai_input_observe_v1", { p_rows: noNul(observed) }).catch((e) => ({ error: (e instanceof Error ? e.message : String(e)).slice(0, 200) })) : { kept: 0 };
      return j({ ok: true, mode, model, items: out.length, tally, stash, recorded: res, inputs, cost_usd: cost, openrouter: ors.summary(), ms: Date.now() - t0, worker: WORKER });
    }
    if (mode === "scholarship_inspect") {
      const chars = Math.min(Number(body.chars || 2500), 8000);
      const paths = await rpc("svc_scholarship_inspect_paths", { p_scholarship_ids: body.scholarship_ids || [], p_candidate_ids: body.candidate_ids || [] });
      const rows: any[] = [...(paths?.scholarships || []), ...(paths?.candidates || []), ...((body.urls || []) as string[]).map((u) => ({ url: u, live: true, name: body.name || "" }))];
      const out: unknown[] = [];
      await pool(rows, 4, async (r) => {
        try {
          let html = "";
          if (r.live) { const pg = await readSch(r.url, null); html = pg.html; r.status = pg.status; r.url = pg.finalUrl }
          else if (r.storage_path) { const { data, error } = await c.storage.from("evidence").download(r.storage_path); if (error || !data) throw Error(error?.message || "missing"); html = await new Response(data.stream().pipeThrough(new DecompressionStream("gzip"))).text() }
          if (!html) { out.push({ ...r, error: "no page" }); return }
          const hd = pageHeadings(html), text = mainText(html);
          let host = ""; try { host = new URL(r.url).hostname } catch { /* */ }
          out.push({ scholarship_id: r.scholarship_id, candidate_id: r.candidate_id, url: r.url, name: r.name, headings: hd,
            name_check: r.name ? nameOnPage(r.name, hd.primary, providerTokens(r.names || []), hd.secondary) : null,
            admission: admissionCheck(html, r.url, host), facts: scholarshipFacts(html, titleOf(html) + " " + h1Of(html), r.name || ""), text: text.slice(0, chars) });
        } catch (e) { out.push({ ...r, error: e instanceof Error ? e.message : String(e) }) }
      });
      return j({ ok: true, mode, pages: out, readVia: "scraper", scholarshipFirecrawlLeft: schLeft, ms: Date.now() - t0, workerVersion: VERSION, scholarshipExtractor: SCH_VERSION });
    }
    // v0.10.0 (2 Oct 2026, map-first link matcher): for a course with no verified page, one pinned model picks the
    // course's own page from the 25 closest addresses in its university's stored site map, or none. The choice must be
    // one of those addresses (checked again in the database); the page is then read by mode read and accepted only under
    // the identity rule. Nothing is admitted here. No Firecrawl credit is used.
    if (mode === "ai_match") {
      // the account key: the Edge secret when set, otherwise the governed OpenRouter credential (vault) of the pinned
      // model's own Layer 3 profile, as layer3-model-routing resolves it
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) {
        const prof = await rpc("layer3_routing_profile_service", { p_code: AI_MATCH_PROFILE });
        if (!prof?.id) return j({ ok: false, mode, error: "credential profile not found", workerVersion: VERSION }, 503);
        const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof.id });
        key = typeof data === "string" ? data : "";
      }
      if (!key) return j({ ok: false, mode, error: "OpenRouter credential unavailable", workerVersion: VERSION }, 503);
      const items: { id: number; title: string; code: string | null; level: string | null; provider: string; country: string; candidates: { url: string; title: string }[] }[] =
        await rpc("svc_coverage_ai_match_next", { p_limit: Math.min(Number(body.limit || 40), 80) });
      const matchTokens = answerLimit(ws, "course_page_match");
      const tally: Record<string, number> = {}; let cost = 0; const matchModel: Record<number, string> = {};  // the model that answered each item
      await pool(items, Math.min(Number(body.concurrency || 8), 12), async (it) => {
        if (!(it as any).model) { tally.no_model = (tally.no_model || 0) + 1; return }  // no model handed out (a database without the routes): nothing is recorded, the lease runs out and the item is offered again
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_coverage_ai_match_record", { p_id: it.id, p_url: null, p_answer: null, p_model: String((it as any).model), p_cost: 0, p_error: "time budget" }); return }
        let url: string | null = null, answer: unknown = null, err: string | null = null, c1 = 0;
        try {
          const r = await cascadeFetch(fetch, { models: (it as any).models, deadline: t0 + BUDGET_MS - 25000, service: "course_matching", source: "coverage_ai_match", source_id: it.id }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" },
            body: JSON.stringify(aiMatchRequest(it, matchTokens)), signal: AbortSignal.timeout(45000) });
          const d = await r.json().catch(() => ({})); matchModel[it.id] = sentModel(d, String((it as any).model || ""));
          // v0.54.0 (W32): the cost is counted before any check; a cut or empty answer fails the match, named (an empty answer was read as "{}", choice 0)
          const ans = readAnswer(d, "course_page_match", matchTokens); c1 = ans.cost;
          if (!r.ok) throw Error(`HTTP ${r.status}: ${JSON.stringify(d?.error || d).slice(0, 160)}`);
          if (d?.model && !String(d.model).startsWith(sentModel(d, String((it as any).model || "")))) throw Error(`returned model ${d.model}`);
          if (!ans.ok) throw Error(ans.error);
          const a = ans.a;
          const n = Number(a?.choice);
          answer = { choice: n, reason: String(a?.reason || "").slice(0, 400) };
          if (Number.isInteger(n) && n >= 1 && n <= it.candidates.length) url = it.candidates[n - 1].url;
        } catch (e) { err = e instanceof Error ? e.message : String(e) }
        cost += c1;
        const st = await rpc("svc_coverage_ai_match_record", { p_id: it.id, p_url: url, p_answer: answer, p_model: matchModel[it.id] || String((it as any).model || ""), p_cost: c1, p_error: err });
        tally[st] = (tally[st] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, cost_usd: cost, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    // v0.14.0 (Decision 253): a Firecrawl run (Read pages or Find pages) for target universities. Every option comes from
    // the run's settings and every call is logged (svc_fc_call_log) for the Firecrawl support report.
    // v0.14.1: read chosen pages with chosen Firecrawl options (Platform Admin test of read settings and university
    // adapters). Nothing is recorded on a course: only the call log and this reply.
    // v0.15.0 (Decision 253): university adapters, tried and applied on stored pages (no Firecrawl credits).
    if (mode === "adapter_preview") {
      const n = await rpc("svc_adapter_preview_next", { p_preview_id: String(body.preview_id || "") });
      if (!n) return j({ error: "unknown preview", worker: WORKER }, 404);
      const out: unknown[] = []; let shape: string[] | null = null;
      await pool(n.pages || [], 4, async (pg: any) => {
        try {
          const html = await storedHtml(pg.storage_path);
          const r = applyAdapter(n.adapter || {}, html, { title: pg.title, code: pg.code, country: pg.country, status: pg.status, known: pg.read_status === "read" ? pg.identity_basis : null }, VERSION);
          if (!shape && n.adapter?.json_source) { const d = pageJson(html, n.adapter.json_source); if (d) shape = n.adapter.json_find ? jsonFind(d, String(n.adapter.json_find)) : jsonShape(d, 5) }
          out.push({ course: pg.title, code: pg.code, url: pg.url, was: pg.read_status, identity_before: pg.identity_basis, identity: r.identity, how: r.how, json_found: r.json_found, course_title_seen: r.course_title_seen,
                     page: inspectPage(html), found: r.candidates ? { intakes: (r.candidates as any).intakes, intakes_by: (r.candidates as any).intakes_by ?? null, english: (r.candidates as any).english, fee: (r.candidates as any).fee?.value ?? null, fee_basis: (r.candidates as any).fee?.basis ?? null, extra: r.extra } : null, patterns_found: r.patterns_found });
        } catch (e) { out.push({ course: pg.title, url: pg.url, error: e instanceof Error ? e.message : String(e) }) }
      });
      await rpc("svc_adapter_preview_record", { p_preview_id: body.preview_id, p_result: { pages: out, json_shape: shape, worker: WORKER } });
      return j({ ok: true, mode, pages: out.length, worker: WORKER });
    }
    if (mode === "adapter_apply") {
      // v0.16.1: an edge call may use only about two seconds of processor time. Pages are read one after another and the
      // call stops after ADAPTER_CPU_MS of reading, then asks for the next call to carry on after the last page.
      const ADAPTER_CPU_MS = 900;
      const tally: Record<string, number> = {}; let after: string | null = body.after ? String(body.after) : null, pages = 0, cpu = 0, stopped = false;
      while (!stopped && Date.now() - t0 < BUDGET_MS - 20000) {
        const n = await rpc("svc_adapter_apply_next", { p_provider_id: String(body.provider_id || ""), p_after: after, p_limit: 20 });
        const list: any[] = n?.pages || []; if (!n?.adapter || !list.length) break;
        for (const pg of list) {
          try {
            const html = await storedHtml(pg.storage_path);
            const c0 = performance.now();
            const r = applyAdapter(n.adapter, html, { title: pg.title, code: pg.code, country: pg.country, status: pg.status, known: pg.read_status === "read" ? pg.identity_basis : null }, VERSION);
            cpu += performance.now() - c0;
            // a refused page the adapter confirms, or a confirmed page whose fields the adapter's mappings fill or replace
            const confirms = pg.read_status === "identity_mismatch" && !!r.identity?.startsWith("adapter_");
            const fills = pg.read_status === "read" && !!pg.identity_basis && !!r.candidates;
            const st = confirms || fills ? await rpc("svc_adapter_page_record", { p_course_id: pg.course_id, p_identity: confirms ? r.identity : "adapter_title", p_how: confirms ? r.how : `fields only, page already confirmed (${pg.identity_basis})`, p_candidates: r.candidates }) : "no_identity";
            tally[st] = (tally[st] || 0) + 1;
          } catch { tally.error = (tally.error || 0) + 1 }
          pages++; after = pg.course_id;
          if (cpu > ADAPTER_CPU_MS || Date.now() - t0 >= BUDGET_MS - 20000) { stopped = true; break }
        }
      }
      // carry on in a fresh call from the last page read (the cursor only moves forward, so the chain ends)
      const cont = stopped && after ? await rpc("svc_adapter_apply_continue", { p_provider_id: String(body.provider_id || ""), p_after: after }).catch(() => null) : null;
      return j({ ok: true, mode, pages, tally, more: stopped, continued: cont, after, cpu_ms: Math.round(cpu), worker: WORKER });
    }
    // v0.17.0 (Decision 254, Platform Admin 23:41): the visual adapter builder. Capture: Firecrawl reads each sample page
    // with a full-page screenshot; the page is kept (evidence bucket), the screenshot is kept (adapter-captures bucket) and
    // the page is shown as text blocks and page-data values. Propose: the pinned preferred model proposes the adapter from
    // the Platform Admin's marks and comments, and its output is worked out on the samples. Nothing is saved to the adapter.
    if (mode === "adapter_capture") {
      if (!fc?.secret) return j({ error: "no Firecrawl key", worker: WORKER }, 500);
      const dr = await rpc("svc_adapter_draft_get", { p_draft_id: String(body.draft_id || "") });
      if (!dr?.id) return j({ error: "unknown draft", worker: WORKER }, 404);
      const caps: any[] = [];
      const capAdapters: Record<string, any> = (await rpc("svc_uni_adapters", {}).catch(() => null)) || {};
      const prior: any[] = Array.isArray(dr.captures) ? dr.captures : [];
      for (const [i, sm] of (dr.samples || []).entries()) {
        // v0.17.15: a sample added to the draft is captured on its own; pages already captured are kept, not paid for again
        const kept = prior.find((x: any) => x && x.url === sm.url && !x.error && x.html_path);
        if (kept) { caps.push(kept); continue }
        const started = Date.now(); let http: number | null = null, d: any = null, hdrs: Headers | null = null, err: string | null = null;
        // v0.17.4: the builder captures the international view when the university's adapter names one
        const capPv = capAdapters?.[dr.provider_id]?.page_view;
        const reqBody = { proxy: FC_PROXY, url: viewApplies(sm.url, capPv) ? withView(sm.url, capPv) : sm.url, formats: ["rawHtml", { type: "screenshot", fullPage: true }], onlyMainContent: false, waitFor: Math.max(3000, Math.min(Number(capPv?.wait_ms ?? 3000), 8000)), timeout: 60000 };
        try { const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(reqBody), signal: AbortSignal.timeout(90000) }); http = r.status; hdrs = r.headers; d = await r.json().catch(() => null) } catch (e) { err = e instanceof Error ? e.message : String(e) }
        const rec = callRecord(http, d, hdrs, Date.now() - started, err);
        const used = rec.credits_used ?? 1;
        await rpc("svc_coverage_usage", { p_units: used, p_purpose: "adapter_builder", p_provider_id: dr.provider_id, p_url: sm.url }).catch(() => null);
        const { url: _u, ...opts } = reqBody;
        await rpc("svc_fc_call_log", { p: { run_id: null, item_id: null, use_case: "adapter_builder", endpoint: "scrape", provider_id: dr.provider_id, course_id: sm.course_id || null, url: sm.url, request: opts, ...rec, credits_used: used, outcome: rec.success ? "captured" : "fc_error" } }).catch(() => null);
        const html = pageHtml(d);
        if (!html) { caps.push({ ...sm, error: rec.error || "no page returned", credits: used }); continue }
        const cc = ["NZ", "CA"].includes(dr.country) ? dr.country : "AU";
        const htmlPath = `layer2/${cc}/adapters/${dr.provider_id}/${dr.id}/${i + 1}.html.gz`;
        await c.storage.from("evidence").upload(htmlPath, await gzip(html), { contentType: "application/gzip", upsert: true });
        let shot: string | null = null, shotPath: string | null = null;
        const shotUrl = d?.data?.screenshot;
        if (typeof shotUrl === "string" && /^https:/.test(shotUrl)) {
          try {
            const img = await fetch(shotUrl, { signal: AbortSignal.timeout(30000) });
            if (img.ok) {
              shotPath = `${dr.provider_id}/${dr.id}/${i + 1}.png`;
              const up = await c.storage.from("adapter-captures").upload(shotPath, new Uint8Array(await img.arrayBuffer()), { contentType: img.headers.get("content-type") || "image/png", upsert: true });
              if (!up.error) { const sg = await c.storage.from("adapter-captures").createSignedUrl(shotPath, 60 * 60 * 24 * 30); shot = sg.data?.signedUrl || null } else shotPath = null;
            }
          } catch { shotPath = null }
        }
        const src = mainJsonScript(html);
        caps.push({ ...sm, title: titleOf(html).slice(0, 200), html_path: htmlPath, screenshot_path: shotPath, screenshot_url: shot, credits: used,
                    json_source: src, blocks: textBlocks(html), leaves: src ? jsonLeaves(pageJson(html, src)) : [] });
      }
      await rpc("svc_adapter_draft_record", { p_draft_id: dr.id, p_kind: "capture", p_data: { captures: caps, worker: WORKER }, p_cost: 0, p_model: null });
      // v0.53.1 (W30): the ledger counts what a capture did (items: sample pages, failed: pages Firecrawl returned none for); it read 0 of 0 before
      const capFailed = caps.filter((x) => x.error).length;
      return j({ ok: true, mode, items: caps.length, failed: capFailed, captured: caps.length - capFailed, worker: WORKER });
    }
    if (mode === "adapter_propose") {
      const dr = await rpc("svc_adapter_draft_get", { p_draft_id: String(body.draft_id || "") });
      if (!dr?.id) return j({ error: "unknown draft", worker: WORKER }, 404);
      const model = String(dr.model || ""), profile = String(dr.model_profile || "");
      let key = Deno.env.get("OPENROUTER_API_KEY") || "";
      if (!key) {
        const prof = await rpc("layer3_routing_profile_service", { p_code: profile });
        if (prof?.model_identifier !== model) { await rpc("svc_adapter_draft_record", { p_draft_id: dr.id, p_kind: "error", p_data: { error: "the pinned model's profile was not found" }, p_cost: 0, p_model: model }); return j({ ok: false, error: "pinned model profile not found" }, 503) }
        const { data } = await c.rpc("layer3_provider_credential_resolve_service", { p_profile_id: prof.id });
        key = typeof data === "string" ? data : "";
      }
      if (!key) { await rpc("svc_adapter_draft_record", { p_draft_id: dr.id, p_kind: "error", p_data: { error: "OpenRouter credential unavailable" }, p_cost: 0, p_model: model }); return j({ ok: false, error: "no credential" }, 503) }
      // v0.19.0 (11 Oct 2026, Platform Admin Fix 4): an answer cut off at the length limit is asked again once, automatically, with a
      // larger limit (4,000 then 8,000 tokens); the tokens and cost of every attempt are recorded, so nothing is spent unseen.
      let ans: any = null, cost = 0, err: string | null = null; const attempts: { max_tokens: number; finish: string | null; prompt_tokens: number | null; completion_tokens: number | null; cost: number }[] = [];
      // v0.54.0 (W32): the two answer limits are settings (reading.answer_tokens.adapter_proposal and _retry); the second is used only when it is larger
      const firstTokens = answerLimit(ws, "adapter_proposal"), retryTokens = answerLimit(ws, "adapter_proposal_retry");
      for (const maxTokens of retryTokens > firstTokens ? [firstTokens, retryTokens] : [firstTokens]) {
        err = null;
        try {
          const req: any = builderRequest(model, dr); req.max_tokens = maxTokens;
          const r = await cascadeFetch(fetch, { service: "adapter_builder" }, "https://openrouter.ai/api/v1/chat/completions", { method: "POST", headers: { authorization: `Bearer ${key}`, "content-type": "application/json" }, body: JSON.stringify(req), signal: AbortSignal.timeout(maxTokens > firstTokens ? 150000 : 90000) });  // fixed: API time-out of one call (the larger ask gets longer)
          const out = await r.json().catch(() => null);
          const c = Number(out?.usage?.cost || 0); cost += c;
          const finish = out?.choices?.[0]?.finish_reason ?? null;
          attempts.push({ max_tokens: maxTokens, finish, prompt_tokens: out?.usage?.prompt_tokens ?? null, completion_tokens: out?.usage?.completion_tokens ?? null, cost: c });
          if (out?.model && !String(out.model).startsWith(model)) err = `answered by ${out.model}, not the pinned model`;
          else if (!r.ok) err = out?.error?.message || `HTTP ${r.status}`;
          else if (finish === "length") { err = `the model's answer was too long and was cut off at ${maxTokens.toLocaleString("en-AU")} tokens`; continue }
          else { const ra = readAnswer(out, "adapter_proposal", maxTokens, "the proposal"); if (ra.ok) ans = ra.a; else if (ra.cut) { err = `the model's answer was too long and was cut off at ${maxTokens.toLocaleString("en-AU")} tokens`; continue } else err = "the model's answer was not complete JSON" }  // v0.54.0 (W32): unreadable at the limit counts as cut
        } catch (e) { err = e instanceof Error ? e.message : String(e) }
        break;
      }
      if (!ans && err && /cut off/.test(err)) err += " twice (asked again automatically with a larger limit). Name the fields you need in a comment, or use fewer samples, and ask again";
      else if (!ans && err) err += ". Ask for a proposal again";
      if (!ans) { await rpc("svc_adapter_draft_record", { p_draft_id: dr.id, p_kind: "error", p_data: { error: err || "no answer", attempts, worker: WORKER }, p_cost: cost, p_model: model }); return j({ ok: false, error: err }) }
      const { adapter, dropped } = proposalAdapter(ans);
      const output: any[] = [];
      for (const cp of (dr.captures || []).filter((x: any) => x.html_path)) {
        try { const html = await storedHtml(cp.html_path); output.push({ course: cp.course, code: cp.code, url: cp.url, ...adapterOutput(adapter, html, { title: cp.course, code: cp.code || "", country: dr.country }) }) }
        catch (e) { output.push({ course: cp.course, url: cp.url, error: e instanceof Error ? e.message : String(e) }) }
      }
      await rpc("svc_adapter_draft_record", { p_draft_id: dr.id, p_kind: "proposal", p_data: { reason: String(ans.reason || "").slice(0, 600), adapter, dropped, output, attempts, worker: WORKER }, p_cost: cost, p_model: model });
      return j({ ok: true, mode, items: 1, cost, dropped: dropped.length, worker: WORKER });  // v0.53.1 (W30): one proposal, counted in the ledger
    }
    // v0.17.16 (CF-247, 8 Oct 2026): Storage & retention. Removes adapter builder screenshots older than 7 days for a purge run a Platform
    // Admin queued; files are removed through Storage (never by deleting storage rows), up to 20 batches of 100 a call, and every batch is reported.
    // v0.17.18 (CF-247 Rule 6, 8 Oct 2026): read the stored page of each listed course and report every CRICOS-shaped code on it
    // (six digits and a letter). Read only; the database decides whether the course's own code is there.
    // v0.17.19 (CF-247 Phase 2, 8 Oct 2026): side-by-side replay of a stored register archive. One engine per call (the
    // register adapter, or the copy of today's Layer 1 code); records are saved for the database to compare. Read only.
    if (mode === "register_replay") {
      const n = await rpc("svc_register_replay_next_v3", {});
      if (!n?.run_id) return j({ ok: true, mode, idle: true, worker: WORKER });
      try {
      // fields are compared by a cheap hash (FNV-1a, two 32-bit lanes); the full fields are sent only when the run keeps them
      const fnv = (t: string) => { let a = 0x811c9dc5, b = 0x01000193 ^ 0x5bd1e995; for (let i = 0; i < t.length; i++) { const c = t.charCodeAt(i); a = Math.imul(a ^ c, 0x01000193); b = Math.imul(b ^ c, 0x5bd1e995) } return (a >>> 0).toString(16).padStart(8, "0") + (b >>> 0).toString(16).padStart(8, "0") };
      const hashOf = (x: Record<string, string>) => fnv(JSON.stringify(Object.keys(x).sort().map((k) => [k, x[k]])));
      const save = async (recs0: any[], pos: number | null, final: boolean) => {
        const seenK = new Map<string, number>(), recs = recs0.map((r) => { const n = (seenK.get(r.k) || 0) + 1; seenK.set(r.k, n); return n === 1 ? r : { ...r, k: `${r.k}#${n}` } });
        for (let i = 0; i < recs.length; i += 1000)
          await rpc("svc_register_replay_save_v2", { p_run_id: n.run_id, p_engine: n.engine, p_rows: recs.slice(i, i + 1000), p_pos: pos, p_final: final && i + 1000 >= recs.length, p_error: null });
        if (!recs.length) await rpc("svc_register_replay_save_v2", { p_run_id: n.run_id, p_engine: n.engine, p_rows: [], p_pos: pos, p_final: final, p_error: null });
      };
      try {
        if (n.spec?.format === "html_pages") {
          // v0.17.21: a register published as web pages; the run lists its stored Layer 1 batch files, three are read a call
          const paths: string[] = Array.isArray(n.paths) ? n.paths : [];
          if (!paths.length) throw Error("replay run lists no stored files");
          const from = Number(n.pos || 0), to = Math.min(from + 3, paths.length);
          const batch: any[] = [];
          for (const path of paths.slice(from, to)) {
            const { data, error } = await c.storage.from("evidence").download(path);
            if (error || !data) throw Error(`stored file missing: ${path}`);
            const parsed = JSON.parse(await data.text());
            const list = Array.isArray(parsed) ? parsed : Array.isArray(parsed?.providers) ? parsed.providers : Array.isArray(parsed?.items) ? parsed.items : null;
            if (!list) throw Error(`stored file is not a provider batch: ${path}`);
            batch.push(...list);
          }
          const recs0 = n.engine === "adapter" ? htmlAdapterRecords(n.spec, batch) : n.code === "nz_nzqa" ? nzqaReferenceRecords(batch) : null;
          if (!recs0) throw Error(`no reference reader for ${n.code}`);
          const recs = recs0.map((r) => { const h = hashOf(r.x); return n.keep_fields ? { k: r.k, f: h, h, x: r.x } : { k: r.k, f: h, h } });
          const last = to >= paths.length;
          await save(recs, to, last);
          return j({ ok: true, mode, run_id: n.run_id, engine: n.engine, from, files: to - from, providers: batch.length, records: recs.length, total: paths.length, final: last, worker: WORKER });
        }
        if (n.spec?.format === "text_items") {
          // v0.17.26: a catalogue stored as one page or JSON file; the reference is a copy of the worker's own reader (cf247-register-ca-ref.ts)
          const path = String(n.storage_path);
          const { data, error } = await c.storage.from("evidence").download(path);
          if (error || !data) throw Error(error?.message || "stored file missing");
          const bytes = new Uint8Array(await data.arrayBuffer());
          const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) => x.toString(16).padStart(2, "0")).join("");
          if (n.zip_hash && hash !== n.zip_hash) throw Error("stored file does not match its recorded hash");
          const text = new TextDecoder().decode(bytes), key = String(n.spec.key);
          let recs0: { k: string; x: Record<string, string> }[];
          if (n.engine === "adapter") recs0 = itemsAdapterRecords(n.spec, text);
          else {
            const fn = (caRef as any)["ref_" + String(n.code || "").replace(/^ca_/, "")];
            if (typeof fn !== "function") throw Error(`no reference reader for ${n.code}`);
            recs0 = (fn(text) as any[]).map((r) => { const x = { ...r }; if (key !== "provider_code") { delete x.provider_code; delete x.provider_name } return { k: String(r[key] ?? ""), x: itemsText(x) } });
          }
          const recs = recs0.map((r) => { const h = hashOf(r.x); return n.keep_fields ? { k: r.k, f: h, h, x: r.x } : { k: r.k, f: h, h } });
          await save(recs, 1, true);
          return j({ ok: true, mode, run_id: n.run_id, engine: n.engine, records: recs.length, final: true, worker: WORKER });
        }
        if (n.spec?.format === "xlsx_tables") {
          // v0.17.22: a statistics workbook (PRISMS, QILT); the whole stored workbook is read in one call
          const path = String(n.storage_path);
          const { data, error } = await c.storage.from("evidence").download(path);
          if (error || !data) throw Error(error?.message || "stored workbook missing");
          const bytes = new Uint8Array(await data.arrayBuffer());
          const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map((x) => x.toString(16).padStart(2, "0")).join("");
          if (n.zip_hash && hash !== n.zip_hash) throw Error("stored workbook does not match its recorded hash");
          const ctx = n.spec?.lookups ? await rpc("svc_prisms_context", {}) : {};
          const recs0 = n.engine === "adapter" ? xlsxAdapterRecords(n.spec, bytes, path, ctx)
            : n.code === "au_prisms_sa4" ? prismsReferenceRecords(bytes, ctx) : String(n.code || "").startsWith("au_qilt_") ? qiltReferenceRecords(bytes, path) : null;
          if (!recs0) throw Error(`no reference reader for ${n.code}`);
          const recs = recs0.map((r) => { const h = hashOf(r.x); return n.keep_fields ? { k: r.k, f: h, h, x: r.x } : { k: r.k, f: h, h } });
          await save(recs, 1, true);
          return j({ ok: true, mode, run_id: n.run_id, engine: n.engine, records: recs.length, final: true, worker: WORKER });
        }
        const { data, error } = await c.storage.from("evidence").download(String(n.storage_path));
        if (error || !data) throw Error(error?.message || "stored archive missing");
        const zipBytes = new Uint8Array(await data.arrayBuffer());
        const hash = [...new Uint8Array(await crypto.subtle.digest("SHA-256", zipBytes))].map((x) => x.toString(16).padStart(2, "0")).join("");
        if (n.zip_hash && hash !== n.zip_hash) throw Error("stored archive does not match its recorded hash");
        const from = Number(n.pos || 0), to = from + 4000;
        const out0 = n.engine === "adapter" ? await adapterRecords(n.spec, zipBytes, from, to) : await referenceRecords(zipBytes, from, to, Boolean(n.spec?.sets)), recs0 = out0.recs;
        const recs = recs0.map((r) => { const h = hashOf(r.x); return n.keep_fields ? { k: r.k, f: r.f, h, x: r.x } : { k: r.k, f: r.f, h } });
        const last = (out0 as any).done ?? (to >= out0.total);
        await save(recs, (out0 as any).next ?? Math.min(to, out0.total), last);
        return j({ ok: true, mode, run_id: n.run_id, engine: n.engine, from, records: recs.length, total: out0.total, final: last, worker: WORKER });
      } catch (e) {
        await rpc("svc_register_replay_save_v2", { p_run_id: n.run_id, p_engine: n.engine, p_rows: [], p_pos: null, p_final: true, p_error: String((e as Error)?.message || e).slice(0, 300) }).catch(() => null);
        return j({ ok: false, mode, error: String((e as Error)?.message || e), worker: WORKER });
      }
      } finally { await rpc("svc_register_replay_release", { p_run_id: n.run_id }).catch(() => null) }
    }
    // page_codes: retired 18 Oct 2026 (nothing ran it in 30 days; Platform Admin 11:58 "retire what is not used").
    if (mode === "retention_files") {
      const runId = String(body.run_id || "");
      let removed = 0, bytes = 0, finished = false, error: string | null = null;
      for (let b = 0; b < 20; b++) {
        const next: any[] = (await rpc("svc_retention_files_next", { p_run_id: runId, p_limit: 100 }).catch(() => [])) || [];
        if (!next.length) { finished = true; break }
        // v0.17.17: each file names its bucket (adapter-captures for screenshots, evidence for unreferenced evidence)
        const buckets = [...new Set(next.map((x) => String(x.bucket || "adapter-captures")))];
        for (const bk of buckets) {
          const { error: e } = await c.storage.from(bk).remove(next.filter((x) => String(x.bucket || "adapter-captures") === bk).map((x) => x.name));
          if (e) { error = e.message || String(e); break }
        }
        if (error) break
        const n = next.length, s = next.reduce((a, x) => a + Number(x.size || 0), 0);
        removed += n; bytes += s;
        await rpc("svc_retention_files_done", { p_run_id: runId, p_removed: n, p_bytes: s, p_finished: false, p_error: null }).catch(() => null);
      }
      if (finished || error) await rpc("svc_retention_files_done", { p_run_id: runId, p_removed: 0, p_bytes: 0, p_finished: finished && !error, p_error: error }).catch(() => null);
      return j({ ok: !error, mode, removed, bytes, finished, error, worker: WORKER });
    }
    if (mode === "fc_probe") {
      if (!fc?.secret) return j({ error: "no Firecrawl key", workerVersion: WORKER }, 500);
      const pages: { url: string; course?: string; code?: string; country?: string; provider_id?: string; course_id?: string }[] = (Array.isArray(body.pages) ? body.pages : []).slice(0, 10);
      const s = { read_proxy: "auto", read_wait_ms: 3000, read_timeout_ms: 60000, read_location: true, read_formats: ["rawHtml"], ...(body.options || {}) };
      const out: unknown[] = [];
      await pool(pages, 5, async (pg) => {
        if (!isTarget(pg.provider_id || null) && pg.provider_id) { out.push({ url: pg.url, skipped: "not a target university" }); return }
        const reqBody: Record<string, unknown> = scrapeBody(pg.url, s, pg.country || "");
        if (Array.isArray(s.actions)) reqBody.actions = s.actions;
        const started = Date.now(); let http: number | null = null, d: any = null, hdrs: Headers | null = null, err: string | null = null;
        try { const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify(reqBody), signal: AbortSignal.timeout(100000) }); http = r.status; hdrs = r.headers; d = await r.json().catch(() => null) } catch (e) { err = e instanceof Error ? e.message : String(e) }
        const rec = callRecord(http, d, hdrs, Date.now() - started, err);
        const html = pageHtml(d), text = html ? htmlToText(html) : "";
        const idb = html ? identity(html, text, String(pg.course || ""), String(pg.code || ""), false, pg.country || "") : null;
        const used = rec.credits_used ?? 1;
        await rpc("svc_coverage_usage", { p_units: used, p_purpose: "fc_probe", p_provider_id: pg.provider_id || null, p_url: pg.url }).catch(() => null);
        const { url: _u, ...opts } = reqBody;
        await rpc("svc_fc_call_log", { p: { run_id: null, item_id: null, use_case: "probe", endpoint: "scrape", provider_id: pg.provider_id || null, course_id: pg.course_id || null, url: pg.url, request: opts, ...rec, credits_used: used, outcome: readOutcome(rec, html, text.length) } }).catch(() => null);
        out.push({ url: pg.url, http, page_status: rec.page_status, error: rec.error, credits: used, proxy: rec.proxy_used, scrape_id: rec.scrape_id, title: titleOf(html).slice(0, 160) || d?.data?.metadata?.title || null, h1: h1Of(html).slice(0, 160), text_chars: text.length,
                   page: html ? inspectPage(html) : null, text_found: html && s.text_find ? (() => { let r: RegExp; try { r = new RegExp(String(s.text_find), "gi") } catch { return null } return [...text.matchAll(r)].slice(0, 12).map((m) => text.slice(Math.max(0, (m.index || 0) - 120), (m.index || 0) + 240)) })() : null, json_shape: html && s.json_source ? (s.json_find ? jsonFind(s.json_root ? jsonAt(pageJson(html, String(s.json_source)), String(s.json_root)) : pageJson(html, String(s.json_source)), String(s.json_find), Number(s.json_limit || 80)) : jsonShape(pageJson(html, String(s.json_source)), 5)) : null,
                   code_found: !!(pg.code && text.includes(String(pg.code))), identity: idb, warning: d?.data?.warning || rec.meta?.warning || null, intakes: idb ? intakes(text) : null, english: idb ? english(text) : null, fee: idb ? fee(text, currencyFor(pg.country)).value : null });
      });
      return j({ ok: true, mode, options: s, pages: out, ms: Date.now() - t0, worker: WORKER });
    }
    if (mode === "fc_run") {
      const runId = String(body.run_id || "");
      if (!/^[0-9a-f-]{36}$/i.test(runId)) return j({ error: "run_id required", workerVersion: WORKER }, 400);
      if (!fc?.secret) return j({ error: "no Firecrawl key", workerVersion: WORKER }, 500);
      const tally: Record<string, number> = {}; let credits = 0, calls = 0, stopReason: string | null = null;
      const WALL_MS = 95000; // under the database's 120-second wait for a worker call, so other scheduled calls are not held up
      const fcCall = async (endpoint: "scrape" | "search", reqBody: Record<string, unknown>, ctx: { run_id: string; item_id: string; use_case: string; provider_id: string | null; course_id: string | null; url: string | null }, estimate: number) => {
        const started = Date.now(); let http: number | null = null, d: any = null, hdrs: Headers | null = null, err: string | null = null;
        try {
          const left = WALL_MS - (Date.now() - t0);
          if (reqBody.timeout) reqBody.timeout = Math.max(10000, Math.min(Number(reqBody.timeout), left - 15000));
          const r = await fetch(`https://api.firecrawl.dev/v2/${endpoint}`, { method: "POST", headers: fcHeaders, body: JSON.stringify(reqBody), signal: AbortSignal.timeout(Math.max(5000, Math.min(Number(reqBody.timeout || 45000) + 15000, left - 3000))) });
          http = r.status; hdrs = r.headers; d = await r.json().catch(() => null);
        } catch (e) { err = e instanceof Error ? `${e.name}: ${e.message}` : String(e) }
        const rec = callRecord(http, d, hdrs, Date.now() - started, err);
        const used = rec.credits_used ?? (http !== null && http < 500 && http !== 429 ? estimate : 0);
        calls++; credits += used; fcRemaining -= used;
        if (used > 0) await rpc("svc_coverage_usage", { p_units: used, p_purpose: ctx.use_case === "read_page" ? "fc_read" : "fc_search", p_provider_id: ctx.provider_id, p_url: ctx.url || String(reqBody.query || "") }).catch(() => null);
        const { url: _u, query: _q, ...opts } = reqBody as Record<string, unknown>;
        return { d, rec: { ...rec, credits_used: used }, log: { ...ctx, endpoint, url: ctx.url || null, request: { ...opts, ...(endpoint === "search" ? { query: reqBody.query } : {}) }, ...rec, credits_used: used } };
      };
      while (Date.now() - t0 < WALL_MS - 60000) {
        const next = await rpc("svc_fc_run_next", { p_run_id: runId, p_limit: 0 });
        const run = next?.run || {}; const s = run.settings || {};
        if (run.status !== "running") { stopReason = run.status || "not_running"; break }
        const batch = await rpc("svc_fc_run_next", { p_run_id: runId, p_limit: Math.min(Math.max(Number(s.run_batch_per_call || 40), 1), 200) });
        const items: { id: string; course_id: string; provider_id: string; country: string; url: string | null; input: any; result: any }[] = batch?.items || [];
        if (!items.length) { stopReason = batch?.run?.status === "running" ? "nothing_left" : batch?.run?.status || "done"; break }
        // v0.21.4: the day's Firecrawl share for reading (or the day's billed total) used: the run waits for tomorrow
        if (Number(await rpc("svc_fc_budget_left", { p_purpose: "fc_read" }).catch(() => 0)) < 10) { stopReason = "daily_budget"; for (const it of items) await rpc("svc_fc_run_record", { p_item_id: it.id, p_outcome: "retry", p_result: null, p_credits: 0 }); break }
        if (fcRemaining < 10) { stopReason = "plan_reserve"; for (const it of items) await rpc("svc_fc_run_record", { p_item_id: it.id, p_outcome: "retry", p_result: null, p_credits: 0 }); break }
        await pool(items, Math.min(Math.max(Number(s.run_concurrency || 12), 1), 50), async (it) => {
          const ctx = { run_id: runId, item_id: it.id, use_case: String(run.use_case), provider_id: it.provider_id, course_id: it.course_id, url: it.url };
          // not enough of this worker call's time left for one more Firecrawl call: back to the queue, untouched
          if (WALL_MS - (Date.now() - t0) < 30000) { await rpc("svc_fc_run_record", { p_item_id: it.id, p_outcome: "retry", p_result: it.result ?? null, p_credits: 0 }); tally.deferred = (tally.deferred || 0) + 1; return }
          let outcome = "error", result: Record<string, unknown> = {}, used = 0;
          try {
            if (run.use_case === "read_page") {
              const u = new URL(String(it.url));
              if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) {
                outcome = "robots_disallowed";
                await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: "robots_disallowed", p_http_status: null, p_fetched_via: null, p_identity_basis: null, p_storage_path: null, p_sha256: null, p_candidates: null });
              } else {
                const proxy = String(s.read_proxy || "auto").toLowerCase();
                const { d, rec, log } = await fcCall("scrape", scrapeBody(String(it.url), s, it.country), ctx, /stealth|enhanced/.test(proxy) ? 5 : 1);
                used = rec.credits_used || 0;
                const html = pageHtml(d); const text = html ? htmlToText(html) : "";
                outcome = readOutcome(rec, html, text.length);
                let identityBasis: string | null = null, path: string | null = null, sha: string | null = null, candidates: unknown = null, readStatus: string | null = null;
                const finalUrl = String(d?.data?.metadata?.sourceURL || d?.data?.metadata?.url || it.url);
                const ad = adapters[it.provider_id];
                const adHit = ad && html ? applyAdapter(ad, html, { title: String(it.input?.course || ""), code: String(it.input?.code || ""), country: it.country || "", status: it.input?.page_status }, VERSION) : null;
                if (adHit?.json_found && adHit.identity && outcome === "thin") outcome = "read";
                if (outcome === "read") {
                  identityBasis = identity(html, text, String(it.input?.course || ""), String(it.input?.code || ""), it.input?.page_status === "ambiguous", it.country || "");
                  if (identityBasis === "field_award" && staleCalendarUrl(finalUrl)) identityBasis = null;
                  if (!identityBasis && adHit?.identity) identityBasis = adHit.identity;
                  readStatus = identityBasis ? "read" : "identity_mismatch"; outcome = identityBasis ? "read_course_page" : "read_other_page";
                  const textSha = await sha256(new TextEncoder().encode(normText(text)));
                  if (identityBasis && textSha === await rpc("svc_coverage_text_sha", { p_course_id: it.course_id }).catch(() => null)) { path = null; sha = null } // v0.32.0: unchanged page, copy in use kept
                  else {
                    const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
                    path = `layer2/${["NZ", "CA"].includes(it.country) ? it.country : "AU"}/coverage/${it.provider_id}/${it.course_id}/${sha}.html.gz`;
                    const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
                    if (up.error) { path = null; sha = null }
                  }
                  candidates = identityBasis ? (adHit?.candidates && (adHit.json_found || identityBasis.startsWith("adapter_") || Object.keys(adHit.patterns_found || {}).length > 0) ? { ...(adHit.candidates as Record<string, unknown>), final_url: finalUrl }
                                                : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(it.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION })
                                             : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200) };
                  if (candidates && typeof candidates === "object") (candidates as Record<string, unknown>).text_sha = textSha;
                } else if (outcome === "blocked") readStatus = "blocked";
                else if (outcome === "not_found") readStatus = "fetch_failed";
                else if (outcome === "thin") readStatus = "too_thin";
                if (readStatus) await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: readStatus, p_http_status: rec.page_status ?? 200, p_fetched_via: "firecrawl", p_identity_basis: identityBasis, p_storage_path: path, p_sha256: sha, p_candidates: candidates });
                await rpc("svc_fc_call_log", { p: { ...log, outcome } }).catch(() => null);
                result = { page_status: rec.page_status, proxy_used: rec.proxy_used, scrape_id: rec.scrape_id, identity_basis: identityBasis, error: rec.error, final_url: finalUrl,
                           found: candidates && identityBasis ? { intakes: (candidates as any).intakes, english: (candidates as any).english?.ielts_overall ?? null, fee: (candidates as any).fee?.value ?? null } : null };
              }
            } else if (run.use_case === "find_page") {
              const { d, rec, log } = await fcCall("search", searchBody(it.input || {}, s, it.country), { ...ctx, url: null }, 2);
              used = rec.credits_used || 0;
              if (!rec.success) { outcome = rec.http === 429 ? "rate_limited" : "fc_error"; result = { error: rec.error } }
              else {
                const found = searchCandidates(it.input || {}, searchResults(d), Number(s.find_min_title_match ?? 0.6));
                outcome = found.outcome; result = { candidates: found.candidates, top: found.top };
                // v0.17.0 (Platform Admin 23:41): every search result is kept in the evidence bucket with the run
                try {
                  const body = JSON.stringify({ run_id: runId, item_id: it.id, course_id: it.course_id, query: searchBody(it.input || {}, s, it.country).query, at: new Date().toISOString(), results: searchResults(d) });
                  const sp = `layer2/${["NZ", "CA"].includes(it.country) ? it.country : "AU"}/firecrawl/search/${runId}/${it.id}.json.gz`;
                  const up = await c.storage.from("evidence").upload(sp, await gzip(body), { contentType: "application/gzip", upsert: true });
                  if (!up.error) result.search_path = sp;
                } catch { /* the run carries on; the call log keeps the outcome */ }
                if (found.candidates.length) { const b = await rpc("svc_fc_find_bind", { p_item_id: it.id, p_candidates: found.candidates }); result.bind = b; if (b !== "bound") outcome = `found_not_bound_${b}` }
              }
              await rpc("svc_fc_call_log", { p: { ...log, outcome } }).catch(() => null);
            }
          } catch (e) { outcome = "error"; result = { error: e instanceof Error ? e.message : String(e) } }
          const retry = ["rate_limited", "timeout", "fc_error", "error"].includes(outcome) && !(Number(it.result?.tries || 0) >= 1);
          if (retry) { result.tries = 1 }
          await rpc("svc_fc_run_record", { p_item_id: it.id, p_outcome: retry ? "retry" : outcome, p_result: result, p_credits: used });
          tally[outcome] = (tally[outcome] || 0) + 1;
        });
        if (tally.rate_limited && tally.rate_limited >= 3) { stopReason = "rate_limited"; break }
      }
      return j({ ok: true, mode, run_id: runId, tally, calls, credits, stop: stopReason, ms: Date.now() - t0, workerVersion: VERSION, worker: WORKER });
    }
    if (mode === "read") {
      const items: { course_id: string; provider_id: string; url: string; title: string; code: string; status: string; priority?: boolean; manual?: boolean; country?: string; basis?: string; rendered_before?: boolean; render_ok?: boolean ; direct_only?: boolean }[] = await rpc("svc_coverage_read_next", { p_limit: Math.min(Number(body.limit || 24), 200) }); // v0.44.0: up to the UI maximum of Read course pages (batch.coverage_read, 200); it was capped at 60 here // fixed: 200 is the setting's max_value
      const tally: Record<string, number> = {};
      await pool(items, Math.min(Math.max(1, wsNum("reading.pages_at_once", 8)), 32), async (it) => { // v0.44.0: pages fetched at once from Settings (reading.pages_at_once, 1 to 32; it was 8, fixed here)
        if (Date.now() - t0 > BUDGET_MS) { await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: "deferred", p_http_status: null, p_fetched_via: null, p_identity_basis: null, p_storage_path: null, p_sha256: null, p_candidates: null }); return }
        let status = "fetch_failed", http: number | null = null, via: string | null = null, html = "", finalUrl = it.url;
        // v0.13.4: a search candidate (basis title_search / cricos_search, picked by a URL recipe and often not the course's
        // page) is read directly only; it is never rendered through Firecrawl. The matcher's pages and hand-entered pages keep the fallback.
        // v0.17.6: a search page that was rendered through Firecrawl before (or sent back by a view read) keeps that fallback
        const searchCandidate = (it.basis === "title_search" || it.basis === "cricos_search") && it.rendered_before !== true;
        // v0.21.3 (Platform Admin, 12 Oct 2026 21:21): a page found by a search is read directly first; Firecrawl only when the direct read is blocked or needs a browser
        const searchFound = ["title_search", "cricos_search", "firecrawl_search", "serper_search"].includes(it.basis || "");
        // v0.21.5 (Platform Admin, 12 Oct 2026 23:54): Firecrawl reads only pages found by their CRICOS code, listed on the university's own site, or entered by a person
        // v0.36.0 (22 Oct 2026, NZ review fix 3): a page that needed a browser in a country listed in pages.render_countries is rendered once (render_ok)
        // v0.55.0 (31 Oct 2026, decision D13): a page in the re-read pilot is read directly only; it never falls back to Firecrawl or the international view render
        const fcTrusted = it.direct_only !== true && (FC_TRUSTED_BASIS.includes(it.basis || "") || it.manual === true || it.render_ok === true);
        // v0.17.4: the university's international view (adapter page_view.render) is read through Firecrawl with the view
        // applied to the bound address (kept as the page's final address); a plain fetch would only see the domestic default.
        const pv = adapters[it.provider_id]?.page_view;
        const viewRender = viewApplies(it.url, pv) && !searchCandidate && fcTrusted;
        try {
          const u = new URL(it.url);
          if (!robotsAllows(await robotsFor(u), u.pathname + u.search)) status = "robots_disallowed";
          else if (viewRender) {
            const viewUrl = withView(it.url, pv);
            if (await useFc("scrape", it.provider_id, viewUrl)) {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: viewUrl, formats: ["rawHtml"], onlyMainContent: false, waitFor: Math.max(0, Math.min(Number(pv?.wait_ms ?? 3000), 8000)) }), signal: AbortSignal.timeout(90000) }).catch(() => null);
              const d = r ? await r.json().catch(() => ({})) : {};
              if (r?.ok && pageHtml(d)) { html = pageHtml(d); via = "firecrawl"; http = d.data?.metadata?.statusCode ?? 200; finalUrl = viewUrl }
              else http = r?.status ?? null;
              status = html ? "read" : http && [401, 403, 406, 429].includes(http) ? "blocked" : "fetch_failed";
            } else status = "needs_render";
          }
          else {
            try {
              const r = await fetch(u, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) });
              http = r.status; finalUrl = r.url || it.url;
              if (r.ok && /html/i.test(r.headers.get("content-type") || "html")) { html = await r.text(); via = "direct" }
            } catch { http = null }
            const thin = html && htmlToText(html).length < 1500;
            // v0.13.4: a search candidate (basis title_search / cricos_search, picked by a URL recipe and often not the course's
            // page) is read directly only; it is never rendered through Firecrawl. The matcher's pages and hand-entered pages keep the fallback.
            // v0.15.1: no Firecrawl call when the university's adapter already reads the page's own data from the plain fetch
            const adDirect = thin && adapters[it.provider_id] ? applyAdapter(adapters[it.provider_id], html, { title: it.title, code: it.code, country: it.country || "", status: it.status }, VERSION) : null;
            if (fcTrusted && (!searchCandidate || searchFound) && !(adDirect?.json_found && adDirect.identity) && (!html || thin) && (it.status === "bound" || it.priority === true || searchFound) && (http === null || [401, 403, 406, 429, 503].includes(http) || thin) && await useFc("scrape", it.provider_id, it.url)) {
              const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["rawHtml"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) });
              const d = await r.json().catch(() => ({}));
              if (r.ok && pageHtml(d)) { html = pageHtml(d); via = "firecrawl"; http = d.data?.metadata?.statusCode ?? 200; finalUrl = d.data?.metadata?.sourceURL || it.url }
            }
            if (html && via === "direct" && htmlToText(html).length < 1500) status = "needs_render";
            else if (html) status = "read";
            else if (http && [401, 403, 406, 429].includes(http)) status = "blocked";
          }
        } catch { status = "fetch_failed" }
        // v0.15.1: a university adapter may read the page's own data (for example a handbook's __NEXT_DATA__), so a page
        // that would need a browser can be read from the plain fetch, at no Firecrawl cost.
        const ad = adapters[it.provider_id];
        const adHit = ad && html && (status === "read" || status === "needs_render") ? applyAdapter(ad, html, { title: it.title, code: it.code, country: it.country || "", status: it.status }, VERSION) : null;
        if (adHit?.json_found && adHit.identity && status === "needs_render") status = "read";
        let identityBasis: string | null = null, path: string | null = null, sha: string | null = null, candidates: unknown = null;
        if (status === "read" && via === "direct") {
          // v0.40.8 (23 Oct 2026, Platform Admin: "the university page for a course i checked had newer version link"): a page that links
          // to itself with a later year in its address (University of Auckland catalogue: p0_catalogue_year=2027), every other
          // parameter the same, is read at its newest version
          const nv = newestVersionUrl(html, finalUrl);
          if (nv) {
            const r2 = await fetch(nv, { headers: { "user-agent": UA, accept: "text/html,application/xhtml+xml" }, redirect: "follow", signal: AbortSignal.timeout(20000) }).catch(() => null);
            const h2 = r2?.ok ? await r2.text().catch(() => "") : "";
            if (h2 && htmlToText(h2).length >= 1500) { html = h2; finalUrl = r2?.url || nv; http = r2?.status ?? http }
          }
        }
        if (status === "read") {
          let text = htmlToText(html);
          // v0.6.3: a page a person entered on the course page is the course's page (Decision 179).
          // v0.17.4: a page bound by hand that the university's adapter confirms (code or title) keeps the adapter's identity,
          // so its readings go through the same admission rules as any adapter page; "manual" is the last resort.
          identityBasis = identity(html, text, it.title, it.code, it.status === "ambiguous", it.country || "") || adHit?.identity || (it.manual === true ? "manual" : null);
          // v0.6.2: a priority page read directly without the code may be a script-rendered handbook (UNSW, Melbourne):
          // render it once through Firecrawl before calling it a mismatch.
          if (!identityBasis && via === "direct" && it.priority === true && !searchCandidate && fcTrusted && await useFc("scrape", it.provider_id, it.url)) {
            const r = await fetch("https://api.firecrawl.dev/v2/scrape", { method: "POST", headers: fcHeaders, body: JSON.stringify({ proxy: FC_PROXY, url: it.url, formats: ["rawHtml"], onlyMainContent: false }), signal: AbortSignal.timeout(60000) }).catch(() => null);
            const d = r ? await r.json().catch(() => ({})) : {};
            if (r?.ok && pageHtml(d)) {
              html = pageHtml(d); via = "firecrawl"; http = d.data?.metadata?.statusCode ?? http; finalUrl = d.data?.metadata?.sourceURL || finalUrl;
              text = htmlToText(html); identityBasis = identity(html, text, it.title, it.code, it.status === "ambiguous", it.country || "");
            }
          }
          // Decision 235: a field + award match on an archived calendar page (a year in the address more than a year old) is not used
          if (identityBasis === "field_award" && staleCalendarUrl(finalUrl)) identityBasis = null;
          if (!identityBasis) status = "identity_mismatch";
          const textSha = await sha256(new TextEncoder().encode(normText(text)));
          if (identityBasis && textSha === await rpc("svc_coverage_text_sha", { p_course_id: it.course_id }).catch(() => null)) { path = null; sha = null } // v0.32.0: unchanged page, copy in use kept
          else {
            const gz = await gzip(html); sha = await sha256(new TextEncoder().encode(html));
            path = `layer2/${["NZ", "CA"].includes(it.country) ? it.country : "AU"}/coverage/${it.provider_id}/${it.course_id}/${sha}.html.gz`;
            const up = await c.storage.from("evidence").upload(path, gz, { contentType: "application/gzip", upsert: true });
            if (up.error) { path = null; sha = null }
          }
          candidates = identityBasis ? (adHit?.candidates && (adHit.json_found || identityBasis.startsWith("adapter_") || Object.keys(adHit.patterns_found || {}).length > 0) ? { ...(adHit.candidates as Record<string, unknown>), final_url: finalUrl }
                                        : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200), fee: fee(text, currencyFor(it.country)), english: english(text), intakes: intakes(text), intake_context: intakeEvidence(text), extractor: VERSION })
                                     : { final_url: finalUrl, page_title: titleOf(html).slice(0, 200), h1: h1Of(html).slice(0, 200) };
          if (candidates && typeof candidates === "object") (candidates as Record<string, unknown>).text_sha = textSha;
        }
        await rpc("svc_coverage_read_record", { p_course_id: it.course_id, p_read_status: status, p_http_status: http, p_fetched_via: via, p_identity_basis: identityBasis, p_storage_path: path, p_sha256: sha, p_candidates: candidates });
        tally[status] = (tally[status] || 0) + 1;
      });
      return j({ ok: true, mode, items: items.length, tally, firecrawlRemainingAboveReserve: fcRemaining, ms: Date.now() - t0, workerVersion: VERSION });
    }
    return j({ ok: false, error: "supported modes: credential_read, site_check, fee_ai, discover, read, central_find, ai_match, reidentify, directory_capture, id_qualify, openrouter_key, reference_capture, site_hint_verify, find_site, reextract, tuition_handoff, link_search, provider_facts, provider_facts_inspect, provider_facts_parse, scholarship_read, scholarship_discover, scholarship_reextract, scholarship_inspect, scholarship_listing, scholarship_ai, central_ai, entry_ai, entry_inspect, openrouter_balance", workerVersion: VERSION }, 422);
  } catch (e) {
    return j({ ok: false, error: e instanceof Error ? e.message : String(e), workerVersion: VERSION }, 500);
  }
}

