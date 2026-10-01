// Decision 215 (v2.15.142): plain-English reading of an error reply a worker sent back (Live activity).
export function errorReading(e){
  const m=String(e?.message||''),st=e?.status
  if(e?.timed_out||st==null)return'The worker did not reply in time. Usually a slow page or a busy service; it is tried again on the next run.'
  if(/invalid_pilot_automation_key|automation_key/i.test(m))return'Something sent the old automation key, which expired on 30 Sep 2026. No worker accepts it any more (every job uses one-time run passes), so whatever sent it needs changing. Tell the Platform Admin.'
  if(/invalid_run_nonce/i.test(m))return'The worker refused a one-time run pass (already used or too old).'
  if(st===401||st===403)return'The worker refused the request: it was not signed in.'
  if(st===429)return'A service asked us to slow down. The job backs off and tries again.'
  if(/firecrawl/i.test(m))return'The page-reading service (Firecrawl) had an error on its side. The page is tried again later.'
  if(st>=500)return'The worker or a service it uses failed. It is tried again on the next run.'
  return'The worker could not do this request.'
}
