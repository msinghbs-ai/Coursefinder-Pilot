// CF-247 (2 Oct 2026): AI page-identity check, contract cf247-page-identity-v1.0.0. Pure functions (no I/O).
// The model reads a stored course page (every CRICOS-style code masked) and a course from the register, copies the name of
// the qualification the page is for, and says whether it is the same course. A "yes" is accepted only when deterministic
// checks pass: the copied name is on the page, its qualification type is the course's, and the titles share their words.
import { clean, h1Of, htmlToText, titleOf } from "./extract.ts";

export const PAGE_ID_CONTRACT = "cf247-page-identity-v1.0.0";
export const PAGE_ID_SYSTEM = `You check whether a page on an education provider's website is the page for one specific course from a government register.
You get the course (title, level, provider) and the page (its heading, its title and its text; course codes are hidden as [code]).
1. page_course_name: copy, character for character from the page, the name of the qualification this page is about (usually the heading). If the page is a list, a search page, a faculty or subject-area page, or is not about one qualification, copy the heading and answer same_course false.
2. same_course: true only when the page is about this exact qualification at this level. A different level is a different course (Diploma and Advanced Diploma; Certificate III and Certificate IV; Graduate Certificate and Graduate Diploma; Bachelor and Bachelor (Honours) when the register lists them apart). A double degree is different from either single degree. A different major, specialisation or stream named in the register title is a different course. The register title may add "(International)", a short code in brackets, or a training-package code; the page may leave these out. Small wording differences (and, &, plural or singular) are the same course.
3. If unsure, answer false.
Answer JSON only, fields in order: reason, page_course_name, same_course.`;

const STOP = new Set(["of", "and", "in", "the", "with", "for", "a", "an", "to", "international", "course", "program", "programme", "online", "on", "campus"]);
const words = (s: string) => clean(s).toLowerCase().replace(/&/g, " and ").replace(/\([^)]*\)/g, (m) => /international|^\(\s*level\s+\d+\s*\)$|^\([A-Z0-9]{2,8}\)$/i.test(m) ? " " : m)
  .replace(/\b(?:[a-z]{3,4}\d{5}|\d{5}nat)\b/g, " ").replace(/[^a-z0-9]+/g, " ").trim().split(" ").filter((w) => w && !STOP.has(w))
  .map((w) => w.length > 4 && w.endsWith("s") && !w.endsWith("ss") ? w.slice(0, -1) : w);

// qualification type of a title: the most specific phrase it contains
const TYPES: [string, RegExp][] = [
  ["advanced diploma", /\badvanced diploma\b/i], ["graduate diploma", /\bgraduate diploma\b/i], ["graduate certificate", /\bgraduate certificate\b/i],
  ["associate degree", /\bassociate degree\b/i], ["diploma", /\bdiploma\b/i], ["certificate iv", /\bcertificate (?:iv|4)\b/i], ["certificate iii", /\bcertificate (?:iii|3)\b/i],
  ["certificate ii", /\bcertificate (?:ii|2)\b/i], ["certificate i", /\bcertificate (?:i|1)\b/i], ["certificate", /\bcertificate\b/i],
  ["bachelor honours", /\bbachelor\b[^/]*\bhonours\b/i], ["bachelor", /\bbachelor\b/i], ["master", /\bmaster\b/i], ["doctor", /\bdoctor|\bphd\b/i],
];
export const qualType = (s: string) => TYPES.find(([, re]) => re.test(s))?.[0] ?? null;
const isDouble = (s: string) => (s.match(/\b(bachelor|master|diploma|certificate|doctor)\b/gi) || []).length >= 2;

export function maskCodes(text: string) { return text.replace(/\b\d{6}[0-9A-Z]\b/g, "[code]").replace(/\b\d{5}[A-Z]\b/g, "[code]") }

export function pageIdInput(html: string, mainTextFn: (h: string) => string) {
  const text = maskCodes(mainTextFn(html)).slice(0, 6000);
  return { h1: maskCodes(h1Of(html)).slice(0, 200), title: maskCodes(titleOf(html)).slice(0, 200), text, fullText: maskCodes(htmlToText(html)) };
}

export function pageIdRequest(model: string, course: { title: string; level: string | null; provider: string }, page: { h1: string; title: string; text: string }) {
  return {
    model, temperature: 0, max_tokens: 500, usage: { include: true }, provider: { require_parameters: true },
    response_format: { type: "json_schema", json_schema: { name: "page_identity", strict: true, schema: { type: "object", additionalProperties: false, required: ["reason", "page_course_name", "same_course"],
      properties: { reason: { type: "string" }, page_course_name: { type: "string" }, same_course: { type: "boolean" } } } } },
    messages: [{ role: "system", content: PAGE_ID_SYSTEM },
      { role: "user", content: `Course: ${course.title}\nLevel: ${course.level || "not given"}\nProvider: ${course.provider}\n\nPage heading: ${page.h1 || "(none)"}\nPage title: ${page.title || "(none)"}\nPage text:\n${page.text}` }],
  };
}

// deterministic checks on a "yes"; every one must hold
export function pageIdChecks(courseTitle: string, answer: { page_course_name?: unknown; same_course?: unknown }, fullText: string) {
  const name = clean(String(answer?.page_course_name ?? ""));
  const flat = (s: string) => s.toLowerCase().replace(/&/g, "and").replace(/[^a-z0-9]+/g, "");
  const onPage = name.length >= 6 && flat(fullText).includes(flat(name));
  const ct = qualType(courseTitle), nt = qualType(name);
  const sameType = ct !== null && ct === nt && isDouble(courseTitle) === isDouble(name);
  const cw = [...new Set(words(courseTitle))], nw = new Set(words(name));
  const covered = cw.length ? cw.filter((w) => nw.has(w)).length / cw.length : 0;
  const back = nw.size ? [...nw].filter((w) => cw.includes(w)).length / nw.size : 0;
  const wordsMatch = covered >= 0.75 && back >= 0.85;
  const yes = answer?.same_course === true;
  return { accepted: yes && onPage && sameType && wordsMatch, said_yes: yes, on_page: onPage, course_type: ct, page_type: nt, same_type: sameType, covered: Math.round(covered * 100) / 100, back: Math.round(back * 100) / 100 };
}
