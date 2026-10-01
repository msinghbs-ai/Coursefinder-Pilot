// Plain-words schedules for the Automations tab (v2.15.110). pg_cron runs in UTC; times are shown in Melbourne time
// (with daylight saving) from v2.15.131, and weekly/monthly days are shifted when Melbourne is already on the next day.
import{utcClockToMelbourne}from'./lib/format.js'
export const EVERY=[[1,'Every minute'],[2,'Every 2 minutes'],[3,'Every 3 minutes'],[5,'Every 5 minutes'],[10,'Every 10 minutes'],[15,'Every 15 minutes'],[20,'Every 20 minutes'],[30,'Every 30 minutes'],[60,'Every hour'],[120,'Every 2 hours'],[360,'Every 6 hours'],[1440,'Once a day']]
const DAYS=['Sunday','Monday','Tuesday','Wednesday','Thursday','Friday','Saturday']
const MONTHS=['','Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec']
const pad=n=>String(n).padStart(2,'0')
const at=(h,m)=>utcClockToMelbourne(h,m)

// Plain-words schedule, and the matching "every N minutes" value when there is one.
export function describeSchedule(s){
  s=String(s||'').trim()
  let m=s.match(/^(\d+) seconds$/);if(m)return{text:`Every ${m[1]} seconds`,every:null}
  const f=s.split(/\s+/);if(f.length!==5)return{text:s,every:null}
  const[mi,h,dom,mon,dow]=f,rest=dom==='*'&&mon==='*'&&dow==='*'
  if(s==='* * * * *')return{text:'Every minute',every:1}
  m=mi.match(/^(?:\*|\d+-59)\/(\d+)$/);if(m&&h==='*'&&rest){const n=Number(m[1]);return{text:`Every ${n} minutes`,every:n}}
  if(/^\d+$/.test(mi)&&h==='*'&&rest)return{text:`Every hour (at :${pad(mi)})`,every:60}
  if(/^\d+(,\d+)+$/.test(mi)&&h==='*'&&rest){const n=mi.split(',').length;return{text:`${n} times an hour`,every:60/n}}
  m=h.match(/^\*\/(\d+)$/);if(/^\d+$/.test(mi)&&m&&rest){const n=Number(m[1]);return{text:`Every ${n} hours`,every:n*60}}
  if(/^\d+$/.test(mi)&&/^\d+$/.test(h)){
    const t=at(h,mi)
    if(rest)return{text:`Daily at ${t.time}`,every:1440}
    if(dom==='*'&&mon==='*'&&/^\d$/.test(dow))return{text:`Weekly, ${DAYS[(Number(dow)+t.dayShift)%7]} ${t.time}`,every:null}
    if(/^\d+$/.test(dom)&&mon==='*'&&dow==='*')return{text:`Monthly on day ${Number(dom)+t.dayShift}, ${t.time}`,every:null}
    m=mon.match(/^(\d+)-(\d+)$/);if(m&&dom==='*'&&/^\d$/.test(dow))return{text:`Weekly on ${DAYS[(Number(dow)+t.dayShift)%7]}, ${MONTHS[m[1]]}–${MONTHS[m[2]]} only`,every:null}
  }
  return{text:s,every:null}
}
