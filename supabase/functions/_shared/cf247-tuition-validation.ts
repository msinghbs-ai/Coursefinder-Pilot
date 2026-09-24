// CF-CHG-20260915-247
// Candidate-bound provider-current tuition validation.
// Layer 3 may validate/reject deterministic Layer 2 candidates; it must not invent,
// annualise amounts, change currency/year/audience, or expand the candidate set.
// The only bounded semantic resolution allowed here is the explicit Layer 2 ambiguity
// annual_or_indicative_requires_validation -> annual|indicative_annual, with Evidence
// still required to support the chosen basis in the caller.
//
// CF-247 candidate-contract: candidate_context.provider_current_tuition is the sole
// positive validation target. candidate_context.fee_candidates is competing context
// only (surfaced to the model for awareness) and must never be accepted as a
// substitute for the target. A non-null result also fails closed unless
// candidate_context.identity_match === true, and both the target and the returned
// candidate must carry an explicit audience of "international".

// CF-247 Slice 3A1: stable, explicit string identifiers for the shared candidate
// validator contract and the shared strict model response JSON schema below.
// These identifiers are exported so callers (e.g. the benchmark) can assert they
// are calling/consuming the same shared contract, without re-deriving equality or
// schema authority of their own.
export const CF247_TUITION_CANDIDATE_VALIDATOR_CONTRACT_ID =
  "cf247-tuition-candidate-validator-v1";
export const CF247_TUITION_RESPONSE_SCHEMA_CONTRACT_ID =
  "cf247-tuition-response-schema-v1";

// CF-247 Slice 3A1: the strict model response JSON schema, previously duplicated
// inline by the benchmark. Semantics are unchanged: object, additionalProperties
// false, required candidate_value/confidence/rationale/evidence_quotes;
// candidate_value is null or the exact five-field tuition object; confidence is a
// 0..1 number; rationale is a string; evidence_quotes is a string array.
export const CF247_TUITION_RESPONSE_SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["candidate_value", "confidence", "rationale", "evidence_quotes"],
  properties: {
    candidate_value: {
      anyOf: [
        { type: "null" },
        {
          type: "object",
          additionalProperties: false,
          required: [
            "amount",
            "currency_code",
            "basis",
            "fee_year",
            "audience",
          ],
          properties: {
            amount: { type: "number" },
            currency_code: { type: "string" },
            basis: { type: "string" },
            fee_year: { anyOf: [{ type: "integer" }, { type: "null" }] },
            audience: { type: "string" },
          },
        },
      ],
    },
    confidence: { type: "number", minimum: 0, maximum: 1 },
    rationale: { type: "string" },
    evidence_quotes: { type: "array", items: { type: "string" } },
  },
} as const;

export type TuitionCandidate = {
  amount: number;
  currency?: string;
  currency_code?: string;
  basis: string;
  year?: number | string | null;
  fee_year?: number | string | null;
  audience?: string | null;
  [key: string]: unknown;
};

export type CandidateContext = {
  provider_current_tuition?: TuitionCandidate | null;
  fee_candidates?: TuitionCandidate[] | null;
  fee_ambiguous?: boolean;
  identity_match?: boolean;
  expected_course_code?: unknown;
  source_record_id?: unknown;
  [key: string]: unknown;
};

const AMBIGUOUS_BASIS = "annual_or_indicative_requires_validation";
const RESOLVED_AMBIGUOUS_BASES = new Set(["annual", "indicative_annual"]);
const PLAUSIBLE_FEE_YEAR = /^20(2[4-9]|30)$/;

// CF-247 option A: does any Evidence quote state this amount (tolerating
// thousands separators such as "38,400" or "38 400") and, when given, this year?
export function tuitionQuoteSupports(
  quotes: unknown,
  amount: unknown,
  year?: string | number | null,
): boolean {
  const n = Number(amount);
  if (!Array.isArray(quotes) || !Number.isFinite(n) || n <= 0) return false;
  const amountText = Number.isInteger(n) ? String(n) : n.toFixed(2);
  const amountPattern = new RegExp(`(^|\\D)${amountText.replace(".", "\\.")}(\\D|$)`);
  const yearText = year == null || String(year).trim() === "" ? null : String(year).trim();
  return quotes.some((q) => {
    if (typeof q !== "string") return false;
    const compact = q.replace(/(\d)[,\s](?=\d{3}(\D|$))/g, "$1");
    if (!amountPattern.test(compact)) return false;
    return yearText === null || new RegExp(`(^|\\D)${yearText}(\\D|$)`).test(compact);
  });
}
// CF-247 option A: a resolved basis must be stated in a returned quote that also
// carries the amount. "Indicative" alone does not mean annual; totals and
// per-semester/per-unit figures are never annual.
const ANNUAL_WORDING = /\b(annual|annually|per\s+year|per\s+annum|a\s+year|yearly|each\s+year)\b/i;
const NOT_ANNUAL_WORDING = /\b(total|whole[\s-]course|full[\s-]course|entire\s+course|per\s+semester|per\s+trimester|per\s+unit|per\s+credit|per\s+subject)\b/i;
export function tuitionQuoteSupportsBasis(
  quotes: unknown,
  amount: unknown,
  basis: unknown,
): boolean {
  const wanted = String(basis ?? "").trim().toLowerCase();
  if (!Array.isArray(quotes)) return false;
  return quotes.some((q) => {
    if (typeof q !== "string" || !tuitionQuoteSupports([q], amount)) return false;
    if (NOT_ANNUAL_WORDING.test(q) || !ANNUAL_WORDING.test(q)) return false;
    if (wanted === "indicative_annual") return /\bindicative\b/i.test(q);
    return wanted === "annual" || wanted === "per_year_explicit";
  });
}
const normaliseBasis = (value: unknown) =>
  String(value ?? "")
    .trim()
    .toLowerCase()
    .replace(/[\s-]+/g, "_");
const normaliseCurrency = (value: unknown) =>
  String(value ?? "")
    .trim()
    .toUpperCase();
const normaliseAudience = (value: unknown) =>
  String(value ?? "")
    .trim()
    .toLowerCase();
const finiteAmount = (value: unknown) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
};
const candidateCurrency = (c: TuitionCandidate | Record<string, unknown>) =>
  normaliseCurrency(c.currency_code ?? c.currency);
const candidateYear = (c: TuitionCandidate | Record<string, unknown>) => {
  const raw = c.fee_year ?? c.year;
  return raw == null || String(raw).trim() === "" ? null : String(raw).trim();
};

const normaliseGoverned = (item: unknown): TuitionCandidate | null => {
  if (!item || typeof item !== "object") return null;
  const c = item as TuitionCandidate;
  const amount = finiteAmount(c.amount);
  const currency = candidateCurrency(c);
  const basis = normaliseBasis(c.basis);
  if (amount == null || !currency || !basis) return null;
  const year = candidateYear(c);
  const audience = normaliseAudience(c.audience) || null;
  return {
    ...c,
    amount,
    currency_code: currency,
    basis,
    fee_year: year,
    audience,
  };
};

// The sole positive validation target: candidate_context.provider_current_tuition.
// This is the only candidate a non-null model result may ever be matched against.
export function governedTuitionTarget(
  context: CandidateContext | null | undefined,
): TuitionCandidate | null {
  if (!context || typeof context !== "object") return null;
  return normaliseGoverned(context.provider_current_tuition);
}

const tuitionCandidateKey = (candidate: TuitionCandidate) =>
  `${candidate.amount}|${candidate.currency_code}|${candidate.basis}|${candidate.fee_year ?? ""}|${candidate.audience ?? ""}`;

// Competing context only: candidate_context.fee_candidates. Surfaced to the model for
// awareness of alternative fees that must be distinguished from, and never accepted as
// a substitute for, the sole target above.
export function competingFeeCandidates(
  context: CandidateContext | null | undefined,
): TuitionCandidate[] {
  if (
    !context ||
    typeof context !== "object" ||
    !Array.isArray(context.fee_candidates)
  )
    return [];
  const target = governedTuitionTarget(context);
  const targetKey = target ? tuitionCandidateKey(target) : null;
  const seen = new Set<string>();
  const result: TuitionCandidate[] = [];
  for (const item of context.fee_candidates) {
    const c = normaliseGoverned(item);
    if (!c) continue;
    const key = tuitionCandidateKey(c);
    if (key === targetKey || seen.has(key)) continue;
    seen.add(key);
    result.push(c);
  }
  return result;
}

// Retained for callers/tests that want the full governed pool (target + competing
// context) deduplicated together, e.g. for display/diagnostics. This is NOT used to
// decide validity: only governedTuitionTarget is ever matched against.
export function governedTuitionCandidates(
  context: CandidateContext | null | undefined,
): TuitionCandidate[] {
  const target = governedTuitionTarget(context);
  const competing = competingFeeCandidates(context);
  const seen = new Set<string>();
  const result: TuitionCandidate[] = [];
  for (const c of target ? [target, ...competing] : competing) {
    const key = tuitionCandidateKey(c);
    if (seen.has(key)) continue;
    seen.add(key);
    result.push(c);
  }
  return result;
}

export function validateProviderCurrentTuitionCandidate(
  candidate: unknown,
  context: CandidateContext | null | undefined,
): {
  valid: boolean;
  errors: string[];
  matched_candidate: TuitionCandidate | null;
  basis_resolution: boolean;
  year_resolution: boolean;
  provider_rule_basis?: boolean;
} {
  const errors: string[] = [];
  if (candidate == null)
    return {
      valid: true,
      errors,
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return {
      valid: false,
      errors: ["tuition candidate must be an object or null"],
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };
  }
  if (context?.identity_match !== true) {
    return {
      valid: false,
      errors: [
        "a non-null tuition candidate requires confirmed candidate_context.identity_match",
      ],
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };
  }
  const c = candidate as Record<string, unknown>;
  const amount = finiteAmount(c.amount);
  const currency = candidateCurrency(c);
  const basis = normaliseBasis(c.basis);
  const year = candidateYear(c);
  const audience = normaliseAudience(c.audience);
  if (amount == null) errors.push("tuition amount must be positive and finite");
  if (!currency) errors.push("tuition currency is required");
  if (!basis) errors.push("tuition basis is required");
  if (audience !== "international")
    errors.push("tuition audience must be explicitly international");
  if (errors.length)
    return {
      valid: false,
      errors,
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };

  const target = governedTuitionTarget(context);
  if (!target)
    return {
      valid: false,
      errors: ["no governed Layer 2 provider_current_tuition target"],
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };
  const targetAudience = normaliseAudience(target.audience);
  if (targetAudience !== "international") {
    return {
      valid: false,
      errors: [
        "governed provider_current_tuition target must be explicitly international",
      ],
      matched_candidate: null,
      basis_resolution: false,
      year_resolution: false,
    };
  }

  let basisResolution = false;
  let providerRuleBasis = false;
  // CF-247 option A: when Layer 2 captured no fee year, Layer 3 may supply one.
  // Callers must additionally require an Evidence quote stating that year with
  // the amount (tuitionQuoteSupports) before accepting it.
  const yearResolution = candidateYear(target) === null && year !== null;
  let match: TuitionCandidate | null = null;
  if (
    target.amount === amount &&
    candidateCurrency(target) === currency &&
    (candidateYear(target) === year ||
      (candidateYear(target) === null && year !== null && PLAUSIBLE_FEE_YEAR.test(year))) &&
    targetAudience === audience
  ) {
    const targetBasis = normaliseBasis(target.basis);
    if (targetBasis === basis) {
      match = target;
    } else if (
      targetBasis === AMBIGUOUS_BASIS &&
      RESOLVED_AMBIGUOUS_BASES.has(basis)
    ) {
      basisResolution = true;
      match = target;
    } else if (
      // Package 2: an approved provider fee rule set the target basis (e.g. UQ program
      // pages = indicative annual). The AI may call the same yearly fee "annual"; accept it
      // and keep the rule's basis. Only when the target is stamped by a provider rule.
      targetBasis === "indicative_annual" &&
      basis === "annual" &&
      String((target as any)?.basis_source ?? "").startsWith("provider_fee_rule:")
    ) {
      providerRuleBasis = true;
      match = target;
    }
  }
  if (!match)
    errors.push(
      "candidate does not match the sole governed provider_current_tuition target, or changes amount/currency/year/audience/basis beyond the governed ambiguity; competing fee_candidates are never a valid substitute",
    );
  return {
    valid: errors.length === 0,
    errors,
    matched_candidate: match,
    basis_resolution: Boolean(match && basisResolution),
    year_resolution: Boolean(match && yearResolution),
    provider_rule_basis: providerRuleBasis,
  };
}

export function tuitionValidationPromptContext(
  context: CandidateContext | null | undefined,
): string {
  const target = governedTuitionTarget(context);
  const competing = competingFeeCandidates(context);
  return JSON.stringify({
    instruction:
      'Validate only the supplied provider_current_tuition target against Evidence — it is the sole positive candidate. The listed competing_fee_candidates are other fees mentioned in context for awareness only; they must never be returned or substituted for the target, even if Evidence supports one of them instead. Keep amount, currency and audience unchanged from the target. Keep fee_year unchanged when the target has one; when the target\'s fee_year is null you may set it only if an evidence quote you return states that year together with the amount, otherwise keep it null. If the target\'s basis is annual_or_indicative_requires_validation, Evidence may resolve only to annual or indicative_annual; otherwise basis must remain unchanged. Before resolving the basis, read the words immediately beside the amount. If they say total, total course, whole course, full course, per semester or per unit, the amount is NOT annual and you must return null, even if a heading nearby says indicative or mentions a year — for example, "A$60,952 (total course fee)" must return null. "Indicative" alone does not mean annual: choose indicative_annual only when the words beside the amount say it is both indicative and annual or per year. If they do not say annual or per year, return null. Both the target and any returned candidate must have audience explicitly "international"; missing, blank or other audience is invalid. A non-null result additionally requires identity_match to be true. Return null when Evidence does not explicitly support the target, when identity_match is not true, or when no positive target can be admitted — null is always a safe abstention. Never invent or annualise an amount, convert currency, infer a year that is not quoted with the amount, change audience, or select a different fee. Year selectors: when the page offers a list of selectable years (for example "Select a year 2026 2027 or 2028") instead of one year printed beside the fee, the year is NOT stated with the amount, so keep fee_year null. Every evidence quote must be copied exactly as one continuous passage from the page; never join words from different parts of the page into one quote.',
    identity_match: context?.identity_match ?? null,
    fee_ambiguous: context?.fee_ambiguous ?? null,
    expected_course_code: context?.expected_course_code ?? null,
    provider_current_tuition_target: target,
    competing_fee_candidates: competing,
  });
}

// CF-247 queue relief: Evidence is often saved as JSON holding the page as marked-up
// text, e.g. "Fees[A$56,800](https://...)Duration". The AI quotes the visible words
// ("Fees A$56,800 Duration"). Compare visible text on BOTH sides: drop link targets and
// JSON escapes, formatting symbols and whitespace. Characters must still match exactly
// and in order; nothing is added to either side.
export function quoteComparable(value: unknown): string {
  return String(value ?? "")
    .replace(/\\[nrt]/g, " ")
    .replace(/\\\//g, "/")
    .replace(/\\"/g, '"')
    .replace(/!?\[([^\]]*)\]\([^)]*\)/g, "$1")
    .replace(/[*_`#>|]/g, "")
    .replace(/\s+/g, "")
    .toLowerCase();
}

export function evidenceQuotePresent(quote: unknown, evidence: unknown): boolean {
  const q = quoteComparable(quote);
  return q.length > 0 && quoteComparable(evidence).includes(q);
}

