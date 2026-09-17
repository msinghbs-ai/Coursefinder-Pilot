// CF-CHG-20260915-247
// Candidate-bound provider-current tuition validation.
// Layer 3 may validate/reject deterministic Layer 2 candidates; it must not invent,
// annualise amounts, change currency/year/audience, or expand the candidate set.
// The only bounded semantic resolution allowed here is the explicit Layer 2 ambiguity
// annual_or_indicative_requires_validation -> annual|indicative_annual, with Evidence
// still required to support the chosen basis in the caller.

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
const normaliseBasis = (value: unknown) => String(value ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
const normaliseCurrency = (value: unknown) => String(value ?? "").trim().toUpperCase();
const normaliseAudience = (value: unknown) => String(value ?? "").trim().toLowerCase();
const finiteAmount = (value: unknown) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
};
const candidateCurrency = (c: TuitionCandidate | Record<string, unknown>) => normaliseCurrency(c.currency_code ?? c.currency);
const candidateYear = (c: TuitionCandidate | Record<string, unknown>) => {
  const raw = c.fee_year ?? c.year;
  return raw == null || String(raw).trim() === "" ? null : String(raw).trim();
};

export function governedTuitionCandidates(context: CandidateContext | null | undefined): TuitionCandidate[] {
  if (!context || typeof context !== "object") return [];
  const raw: unknown[] = [];
  if (context.provider_current_tuition && typeof context.provider_current_tuition === "object") raw.push(context.provider_current_tuition);
  if (Array.isArray(context.fee_candidates)) raw.push(...context.fee_candidates);
  const seen = new Set<string>();
  const result: TuitionCandidate[] = [];
  for (const item of raw) {
    if (!item || typeof item !== "object") continue;
    const c = item as TuitionCandidate;
    const amount = finiteAmount(c.amount);
    const currency = candidateCurrency(c);
    const basis = normaliseBasis(c.basis);
    if (amount == null || !currency || !basis) continue;
    const year = candidateYear(c);
    const audience = normaliseAudience(c.audience) || null;
    const key = `${amount}|${currency}|${basis}|${year ?? ""}|${audience ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ ...c, amount, currency_code: currency, basis, fee_year: year, audience });
  }
  return result;
}

export function validateProviderCurrentTuitionCandidate(
  candidate: unknown,
  context: CandidateContext | null | undefined,
): { valid: boolean; errors: string[]; matched_candidate: TuitionCandidate | null; basis_resolution: boolean } {
  const errors: string[] = [];
  if (candidate == null) return { valid: true, errors, matched_candidate: null, basis_resolution: false };
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return { valid: false, errors: ["tuition candidate must be an object or null"], matched_candidate: null, basis_resolution: false };
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
  if (audience && audience !== "international") errors.push("tuition audience must remain international");
  if (errors.length) return { valid: false, errors, matched_candidate: null, basis_resolution: false };

  const governed = governedTuitionCandidates(context);
  if (!governed.length) return { valid: false, errors: ["no governed Layer 2 tuition candidate set"], matched_candidate: null, basis_resolution: false };

  let basisResolution = false;
  const match = governed.find((g) => {
    if (g.amount !== amount || candidateCurrency(g) !== currency) return false;
    if (candidateYear(g) !== year) return false;
    const governedAudience = normaliseAudience(g.audience);
    if (governedAudience && audience && governedAudience !== audience) return false;
    if (governedAudience === "international" && audience && audience !== "international") return false;
    const governedBasis = normaliseBasis(g.basis);
    if (governedBasis === basis) return true;
    if (governedBasis === AMBIGUOUS_BASIS && RESOLVED_AMBIGUOUS_BASES.has(basis)) {
      basisResolution = true;
      return true;
    }
    return false;
  }) ?? null;
  if (!match) errors.push("candidate is outside the deterministic Layer 2 candidate set or changes amount/currency/year/audience/basis beyond the governed ambiguity");
  return { valid: errors.length === 0, errors, matched_candidate: match, basis_resolution: Boolean(match && basisResolution) };
}

export function tuitionValidationPromptContext(context: CandidateContext | null | undefined): string {
  const candidates = governedTuitionCandidates(context);
  return JSON.stringify({
    instruction: "Validate only the supplied deterministic Layer 2 tuition candidate against Evidence. Keep amount, currency, year and audience unchanged. If Layer 2 basis is annual_or_indicative_requires_validation, Evidence may resolve only to annual or indicative_annual; otherwise basis must remain unchanged. Return null when Evidence does not explicitly support the candidate. Never invent or annualise an amount, convert currency, infer a year, change audience, or select a different fee.",
    identity_match: context?.identity_match ?? null,
    fee_ambiguous: context?.fee_ambiguous ?? null,
    expected_course_code: context?.expected_course_code ?? null,
    candidates,
  });
}
