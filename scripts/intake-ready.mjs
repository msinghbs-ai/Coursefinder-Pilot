// CF-247 s1359 (S1-Build; SS-Programme-Control PC-20261128-CONTINUOUS-BUILD-EXECUTE and DOT-EVENING-INTAKE-BOUNDARY-20261128): readiness of a
// file collected from a submitter's pickup folder is enforced at run time, before anything is sent. The submitter marks a file ready by its
// name (<package>-READY_FOR_PICKUP.jsonl); a file the submitter has not released (PRECHECK, PENDING, DO_NOT_SUBMIT, HELD, DRAFT, PARKED) is
// refused whatever its bytes. A record that states its own readiness (state, status or readiness) is sent only when it says READY; the others
// are left out and counted. Admission is unchanged: the writer still proves every quote on the stored copies and the existing rules decide.
export const READY_MARK = /-READY_FOR_PICKUP$/  // fixed: the submitter's release mark (DOT pickup naming)
export const HOLD_MARK = /(PRECHECK|PENDING|DO[_-]?NOT[_-]?SUBMIT|HELD|DRAFT|PARKED|NOT[_-]?READY)/i
export function readyBatch(batch) {
  const b = String(batch || '')
  if (HOLD_MARK.test(b)) return { ok: false, reason: `the file is marked not released (${b.match(HOLD_MARK)[0]}); nothing was sent` }
  if (!READY_MARK.test(b)) return { ok: false, reason: 'the file is not marked READY_FOR_PICKUP by its submitter; nothing was sent' }
  return { ok: true }
}
const READY_STATE = /^READY(_FOR_PICKUP)?$/i
export function readyItems(items) {
  const send = [], held = []
  for (const [i, x] of (Array.isArray(items) ? items : []).entries()) {
    const st = x && typeof x === 'object' ? (x.state ?? x.status ?? x.readiness) : undefined
    if (st === undefined || st === null || READY_STATE.test(String(st))) send.push(x)
    else held.push({ line: i + 1, state: String(st).slice(0, 40), key: String(x?.provisional_key || x?.course_code || '').slice(0, 80) })
  }
  return { send, held }
}
