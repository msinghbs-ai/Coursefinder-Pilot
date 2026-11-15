// CF-247 worker v1.0.2 (audit of admitted records, Platform Admin 15 Nov 2026 11:22): checks that a value the AI gave is the one its own words state.
// Both only refuse a value (the item ends with a reason); neither adds a value, asks the model again or changes a prompt.

// Defect 2: delivery on_campus was admitted from "The qualification is delivered by distance or online modes" (Bachelor of Global Studies,
// Victoria University of Wellington). A mode is kept only when its quote says it: online needs online or distance words; on_campus is refused
// when the quote names only online or distance study and no campus, attendance or face-to-face study. Blended and on_campus_and_online keep the
// earlier rule (the quote must be on the page).
const ONLINE_WORDS = /\b(online|on-line|distance|remote(ly)?|virtual|e-?learning|correspondence|external(ly)?)\b/i;
const CAMPUS_WORDS = /\b(campus(es)?|on[- ]site|face[- ]to[- ]face|in[- ]person|classroom|attend(ance|ing)?|block\s+(courses?|weeks?)|internal(ly)?)\b/i;
export function deliveryQuoteFits(mode: string | null, quote: string) {
  const q = String(quote || "");
  if (mode === "online") return ONLINE_WORDS.test(q);
  if (mode === "on_campus") return !(ONLINE_WORDS.test(q) && !CAMPUS_WORDS.test(q));
  return true;
}

// Defect 3: a level classified from the title alone was set although the title names no award ("Te Hono ki Toi (Poutiriao)" became Bachelor;
// its page is the Master of Professional Creative Practice). A level whose name is an award family (bachelor, master, doctor, diploma,
// certificate, associate degree, foundation) is kept only when the title names the same family; levels without one (Non AQF Award, First
// Professional Degree, secondary studies) keep the earlier rule.
const FAMILIES: [string, RegExp][] = [
  ["bachelor", /\bbachelor/i], ["master", /\bmasters?\b|\bmaster\s+of\b/i], ["doctor", /\b(doctor|doctoral|doctorate|ph\.?\s?d|d\.?phil)\b/i],
  ["diploma", /\bdiploma/i], ["certificate", /\bcertificate/i], ["associate", /\bassociate\s+degree/i], ["foundation", /\b(foundation|pathway|bridging)\b/i],
];
const families = (s: string) => FAMILIES.filter(([, re]) => re.test(s)).map(([f]) => f);
export function titleNamesLevel(title: string, levelName: string) {
  const lf = families(levelName);
  if (!lf.length) return true;
  const tf = families(title);
  return lf.some((f) => tf.includes(f));
}
