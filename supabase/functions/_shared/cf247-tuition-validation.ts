// CF-CHG-20260915-247
// Candidate-bound provider-current tuition validation.
// Layer 3 may validate/reject deterministic Layer 2 candidates; it must not invent,
// annualise, strengthen basis, change currency, or expand the candidate set.

export type TuitionCandidate = {
  amount: number;
  currency: string;
  basis: string;
  year?: number | string | null;
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

const normaliseBasis = (value: unknown) => String(value ?? "").trim().toLowerCase().replace(/[\s-]+/g, "_");
const normaliseCurrency = (value: unknown) => String(value ?? "").trim().toUpperCase();
const finiteAmount = (value: unknown) => {
  const n = Number(value);
  return Number.isFinite(n) && n > 0 ? n : null;
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
    const currency = normaliseCurrency(c.currency);
    const basis = normaliseBasis(c.basis);
    if (amount == null || !currency || !basis) continue;
    const year = c.year == null ? null : String(c.year).trim();
    const key = `${amount}|${currency}|${basis}|${year ?? ""}`;
    if (seen.has(key)) continue;
    seen.add(key);
    result.push({ ...c, amount, currency, basis, year });
  }
  return result;
}

export function validateProviderCurrentTuitionCandidate(
  candidate: unknown,
  context: CandidateContext | null | undefined,
): { valid: boolean; errors: string[]; matched_candidate: TuitionCandidate | null } {
  const errors: string[] = [];
  if (candidate == null) return { valid: true, errors, matched_candidate: null };
  if (!candidate || typeof candidate !== "object" || Array.isArray(candidate)) {
    return { valid: false, errors: ["tuition candidate must be an object or null"], matched_candidate: null };
  }
  const c = candidate as Record<string, unknown>;
  const amount = finiteAmount(c.amount);
  const currency = normaliseCurrency(c.currency);
  const basis = normaliseBasis(c.basis);
  const year = c.year == null ? null : String(c.year).trim();
  if (amount == null) errors.push("tuition amount must be positive and finite");
  if (!currency) errors.push("tuition currency is required");
  if (!basis) errors.push("tuition basis is required");
  if (errors.length) return { valid: false, errors, matched_candidate: null };

  const governed = governedTuitionCandidates(context);
  if (!governed.length) return { valid: false, errors: ["no governed Layer 2 tuition candidate set"], matched_candidate: null };
  const match = governed.find((g) =>
    g.amount === amount &&
    normaliseCurrency(g.currency) === currency &&
    normaliseBasis(g.basis) === basis &&
    (g.year == null ? null : String(g.year).trim()) === year
  ) ?? null;
  if (!match) errors.push("candidate is outside the deterministic Layer 2 candidate set or changes amount/currency/basis/year");
  return { valid: errors.length === 0, errors, matched_candidate: match };
}

export function tuitionValidationPromptContext(context: CandidateContext | null | undefined): string {
  const candidates = governedTuitionCandidates(context);
  return JSON.stringify({
    instruction: "Validate only one supplied deterministic Layer 2 candidate against Evidence. Return that exact candidate or null. Never invent, annualise, convert currency, change year, or strengthen basis. indicative_annual must remain indicative_annual.",
    identity_match: context?.identity_match ?? null,
    fee_ambiguous: context?.fee_ambiguous ?? null,
    expected_course_code: context?.expected_course_code ?? null,
    candidates,
  });
}
