import{test,expect}from'@playwright/test'
import fs from'node:fs'

const worker=fs.readFileSync('supabase/functions/layer2-scope-discover-scheduled/index.ts','utf8')

test('CF-093 first-party zero-result search is terminal only when profile-qualified and only after route exhaustion',()=>{
 expect(worker).toContain('layer2-scope-discover-scheduled-v1.3.9')
 expect(worker).toContain('let emptySearchResult:any=null')
 expect(worker).toContain('function qualifiedZeroResult')
 expect(worker).toContain('zero_result_markers')
 expect(worker).toContain('qualifiedZero=firstPartySearch&&qualifiedZeroResult(html,cfg)')
 expect(worker).toContain('reason=qualifiedZero?"zero_results":"extraction_failed"')
 expect(worker).toContain('p_extraction_status:qualifiedZero?"discovery_zero_results":"discovery_required_link_missing"')
 expect(worker).toContain('zero_result_marker_qualified:qualifiedZero')
 expect(worker).toContain('if(qualifiedZero){if(!emptySearchResult)emptySearchResult=')
 expect(worker).toContain('throw new Error(`route_stopped:${pc.provider_key}:unqualified_zero_result`)')
 expect(worker).toContain('if(emptySearchResult)return emptySearchResult;')
 expect(worker).toContain('throw new Error("providers_exhausted:"+JSON.stringify(failures))')
 expect(worker.indexOf('if(emptySearchResult)return emptySearchResult;')).toBeLessThan(worker.indexOf('throw new Error("providers_exhausted:"+JSON.stringify(failures))'))
 expect(worker).toContain('status:"current_page_not_found",selected:false')
 expect(worker).toContain('canonical_mutation_authorised:false')
 expect(worker).toContain('detail_cricos_verified:verified')
 expect(worker).not.toContain('insert into publishing.')
 expect(worker).not.toContain('insert into search.')
})
