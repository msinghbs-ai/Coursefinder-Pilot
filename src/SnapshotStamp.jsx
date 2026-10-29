// CF-247 decision W35 (Platform Admin 30 Oct 2026 06:53): "Show snapshot generation time and staleness." A cached figure says when it was
// counted, how long ago (the server's age, so every screen agrees) and, past the setting (snapshots.stale_after_minutes, or
// gaps.causes_stale_after_minutes for Why values are missing), a Stale marker. Read live (no snapshot yet): "counted now".
import React from'react'
import{fmtAge,fmtDateTime}from'./lib/format.js'
export{fmtAge}

export default function SnapshotStamp({meta,label='Counted',what=''}){
  if(!meta)return null
  if(meta.source==='live')return <small className="sd-desc cf-snapshot" data-snapshot-stamp={what} data-stale="no">{label} now</small>
  if(!meta.generated_at)return null
  const stale=Boolean(meta.stale)
  const every=meta.refresh_every_minutes?` Counted again every ${meta.refresh_every_minutes} min.`:''
  return <small className="sd-desc cf-snapshot" data-snapshot-stamp={what} data-stale={stale?'yes':'no'}
    title={`${label} ${fmtDateTime(meta.generated_at)}.${every}${meta.last_error?` The last rebuild failed: ${meta.last_error}`:''}`}>
    {label} {fmtDateTime(meta.generated_at)} ({fmtAge(meta.age_seconds)})
    {stale&&<> <span className="cf-chip tone-warning" data-stale-marker>Stale: older than {Number(meta.stale_after_minutes)} min</span></>}
  </small>
}
