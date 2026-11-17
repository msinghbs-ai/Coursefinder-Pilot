// CF-247 Destination data › Bulk Approve Drafts (v2.16.31): the draft localities of the list shown, counted by dataset edition. Ready: a name and
// attribution text are present (the server's own rule, public.admin_destination_localities_bulk_approve); left: a draft without one of them.
export function draftEditions(rows){const m=new Map()
  for(const l of rows){if(l.status!=='draft')continue;const k=l.dataset_edition||'';if(!k)continue;const e=m.get(k)||{edition:k,ready:0,left:0};if(String(l.attribution_text||'').trim()&&String(l.name||'').trim())e.ready++;else e.left++;m.set(k,e)}
  return[...m.values()].sort((a,b)=>a.edition.localeCompare(b.edition))}
