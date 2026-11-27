// CF-247 s1303 (S2-Build, autonomous PIM reader lifecycle): a reader configuration is data, never code. It may override only registered reader settings
// whose key starts with "reading.entry_" and whose value is a number, a boolean or a list of short strings; anything else is ignored. The database
// (security.reader_config_for_v1) hands the configuration out; qualification and activation are decided there. Pure function: no network, no write.
const KEY = /^reading\.entry_[a-z0-9_]+$/;
const okValue = (v: unknown) => (typeof v === "number" && Number.isFinite(v)) || typeof v === "boolean"
  || (Array.isArray(v) && v.length <= 200 && v.every((x) => typeof x === "string" && x.length <= 200));  // fixed: bounds of a list a configuration may carry
export function readerSettings(ws: Record<string, unknown>, cfg: unknown): Record<string, unknown> {
  const o = cfg && typeof cfg === "object" ? (cfg as Record<string, unknown>).settings : null;
  if (!o || typeof o !== "object" || Array.isArray(o)) return ws;
  const out: Record<string, unknown> = { ...ws };
  for (const [k, v] of Object.entries(o as Record<string, unknown>)) if (KEY.test(k) && okValue(v)) out[k] = v;
  return out;
}
