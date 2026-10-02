// Decision 215 (v2.15.142): plain-English reading of an error reply a worker sent back (Live activity).
// Decision 222 (v2.15.149): each reading also says what to do (errorSteps), and names the cases that need nothing.
export function errorReading(e){
  const m=String(e?.message||''),st=e?.status,fn=String(e?.function||'')
  if((e?.timed_out||st==null)&&fn==='layer3-work-dispatch')return'The caller stopped waiting before the AI tuition check finished. The check itself carries on and records its answer, so nothing was lost.'
  if(e?.timed_out||st==null)return'The worker did not reply in time. Usually a slow page or a busy service; it is tried again on the next run.'
  if(/BOOT_ERROR|failed to start/i.test(m))return'The worker could not start. This happens for a minute while a new version of it is being released.'
  if(/statement timeout|canceling statement/i.test(m))return'The database took too long to choose the next batch of work, so this run did nothing. The next run tries again.'
  if(/invalid_pilot_automation_key|automation_key/i.test(m))return'Something sent the old automation key, which expired on 30 Sep 2026. No worker accepts it any more (every job uses one-time run passes), so whatever sent it needs changing. Tell the Platform Admin.'
  if(/invalid_run_nonce/i.test(m))return'The worker refused a one-time run pass (already used or too old).'
  if(st===401||st===403)return'The worker refused the request: it was not signed in.'
  if(/WORKER_RESOURCE_LIMIT|compute resources/i.test(m))return'The worker ran out of memory or time on this run. Nothing was lost: the next run picks up where it stopped. If it keeps happening, the job is made lighter.'
  if(st===429)return'A service asked us to slow down. The job backs off and tries again.'
  if(/firecrawl/i.test(m))return'The page-reading service (Firecrawl) had an error on its side. The page is tried again later.'
  if(st>=500)return'The worker or a service it uses failed. It is tried again on the next run.'
  return'The worker could not do this request.'
}
// What a person should do about it, in order. "Nothing" is said plainly when nothing is needed.
export function errorSteps(e){
  const m=String(e?.message||''),st=e?.status,fn=String(e?.function||''),many=Number(e?.count||0)>3
  if((e?.timed_out||st==null)&&fn==='layer3-work-dispatch')return'Nothing to do. The caller now waits 5 minutes, so this should stop. If it still appears, check that Layer 3 › Control › Tuition "Last 24 hours" keeps growing, then mark it as seen.'
  if(/BOOT_ERROR|failed to start/i.test(m))return many?'It has happened several times, so it is not just a release. Open Scheduled jobs, switch this job off and tell the Platform Admin that the worker needs redeploying.':'Nothing to do if it happened once during a release. Mark it as seen; if it comes back, tell the Platform Admin.'
  if(/statement timeout|canceling statement/i.test(m))return many?'It keeps happening: tell the Platform Admin which job it is; the query needs speeding up. Work is not lost meanwhile.':'Nothing to do if it is rare. Mark it as seen.'
  if(/invalid_pilot_automation_key|automation_key/i.test(m))return'Tell the Platform Admin which job it is.'
  if(st===401||st===403||/invalid_run_nonce/i.test(m))return'If it repeats, tell the Platform Admin: the job’s run pass needs checking.'
  if(/WORKER_RESOURCE_LIMIT|compute resources/i.test(m))return many?'Tell the Platform Admin: the job needs smaller batches.':'Nothing to do; mark it as seen.'
  if(st===429)return'Nothing to do; the job slows down by itself.'
  if(/firecrawl/i.test(m))return'Nothing to do unless Firecrawl’s own status page shows an outage; the page is retried.'
  if(e?.timed_out||st==null)return many?'It keeps timing out: open Live activity, check this job’s queue is still going down, and tell the Platform Admin if it is not.':'Nothing to do if it is occasional; mark it as seen.'
  return many?'It keeps failing: open Scheduled jobs, switch the job off if it is doing harm, and tell the Platform Admin.':'Mark it as seen once understood; it shows again only if it happens again.'
}
