// CF-247 Destination data › Bulk Approve Drafts (v2.16.31): the draft localities of the list shown, counted by dataset edition. Ready: a name and
// attribution text are present (the server's own rule, public.admin_destination_localities_bulk_approve); left: a draft without one of them.
// v2.16.32: kind 'figure' counts draft city figures the same way; a figure is ready when it has a value and attribution text
// (public.admin_destination_figures_bulk_approve).
export function draftEditions(rows,kind='locality'){const m=new Map(),ok=l=>String(l.attribution_text||'').trim()&&(kind==='figure'?l.numeric_value!=null:String(l.name||'').trim())
  for(const l of rows){if(l.status!=='draft')continue;const k=l.dataset_edition||'';if(!k)continue;const e=m.get(k)||{edition:k,ready:0,left:0};if(ok(l))e.ready++;else e.left++;m.set(k,e)}
  return[...m.values()].sort((a,b)=>a.edition.localeCompare(b.edition))}
