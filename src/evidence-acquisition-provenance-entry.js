import{adminRead}from'./lib/supabase'

const UUID=/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}/i
let pending=false
function esc(v){return String(v??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]))}
function installStyle(){if(document.getElementById('cf-evidence-acq-style'))return;const s=document.createElement('style');s.id='cf-evidence-acq-style';s.textContent=`.cf-evidence-acq{margin:12px 0;padding:12px 14px;border:1px solid #dbe5ef;border-radius:10px;background:#f8fafc;display:grid;gap:8px}.cf-evidence-acq h4{margin:0;font-size:12px}.cf-evidence-acq-grid{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:8px}.cf-evidence-acq-item{display:grid;gap:2px}.cf-evidence-acq-item small{font-size:10px;color:#6b7280;text-transform:uppercase;letter-spacing:.04em}.cf-evidence-acq-item strong,.cf-evidence-acq-item span{font-size:11px;overflow-wrap:anywhere}.cf-evidence-acq-mode{display:inline-flex;align-items:center;width:max-content;max-width:100%;padding:4px 8px;border-radius:999px;background:#eef2ff;color:#3730a3;font-size:10px;font-weight:700}.cf-evidence-acq-note{font-size:10px;color:#64748b}@media(max-width:760px){.cf-evidence-acq-grid{grid-template-columns:1fr}}`;document.head.appendChild(s)}
async function reconcile(){
 const drawer=document.querySelector('.evidence-drawer');if(!drawer)return
 const id=(drawer.querySelector('.evidence-drawer-head')?.textContent||'').match(UUID)?.[0];if(!id)return
 if(drawer.dataset.cfAcqEvidenceId===id&&drawer.querySelector('.cf-evidence-acq'))return
 drawer.dataset.cfAcqEvidenceId=id
 const old=drawer.querySelector('.cf-evidence-acq');if(old)old.remove()
 try{
  const data=await adminRead('evidence_detail',{id});const p=data?.acquisition_provenance;if(!p)return
  const host=drawer.querySelector('.evidence-detail-hero')||drawer.querySelector('.evidence-drawer-body');if(!host)return
  const box=document.createElement('section');box.className='cf-evidence-acq';box.innerHTML=`<div><h4>Acquisition provenance</h4><span class="cf-evidence-acq-mode">${esc(p.mode_label||p.mode||'Recorded')}</span></div><div class="cf-evidence-acq-grid"><div class="cf-evidence-acq-item"><small>Acquisition provider</small><strong>${esc(p.provider_name||p.provider_key||'Recorded source')}</strong><span>${esc(p.adapter_type||'')}</span></div><div class="cf-evidence-acq-item"><small>Evidence origin</small><strong>${p.source_evidence_id?'Stored Evidence':'Live source acquisition'}</strong><span>${esc(p.origin_evidence_id||'')}</span></div><div class="cf-evidence-acq-item"><small>Storage reuse</small><strong>${Number(p.reuse_count||0)} reuse${Number(p.reuse_count||0)===1?'':'s'}</strong><span>${p.last_reused_at?esc(new Date(p.last_reused_at).toLocaleString()):'No recorded shared-storage reuse'}</span></div><div class="cf-evidence-acq-item"><small>Runtime</small><strong>${esc(p.runtime_version||p.response_adapter||'—')}</strong><span>${esc(p.origin_storage_path||'')}</span></div></div><div class="cf-evidence-acq-note">This distinguishes a live scraper/direct call from an artifact produced from Evidence already retained in private storage. Original Evidence lineage is preserved.</div>`
  host.insertAdjacentElement('afterend',box)
 }catch{}
}
function schedule(){if(pending)return;pending=true;setTimeout(()=>{pending=false;reconcile()},80)}
installStyle();new MutationObserver(schedule).observe(document.documentElement,{childList:true,subtree:true});addEventListener('hashchange',schedule);schedule()
