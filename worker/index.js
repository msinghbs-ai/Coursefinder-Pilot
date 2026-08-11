import { serviceClient, rpc, safeRpc } from './lib/service'
import { runAuCricos } from './adapters/au-cricos'

const VERSION = 'layer1-v0.1.1'

export default {
  async fetch(request, env) {
    const url = new URL(request.url)

    if (url.pathname === '/api/layer1/health') {
      const bindings = {
        supabaseUrl: Boolean(env.SUPABASE_URL),
        serviceRoleKey: Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
        runKey: Boolean(env.LAYER1_RUN_KEY),
        assets: Boolean(env.ASSETS),
      }
      return json({
        ok: true,
        service: 'coursefinder-layer1',
        version: VERSION,
        configured: bindings.supabaseUrl && bindings.serviceRoleKey && bindings.runKey,
        bindings,
      })
    }

    if (url.pathname === '/api/layer1/run' && request.method === 'POST') {
      if (!env.LAYER1_RUN_KEY || request.headers.get('x-layer1-key') !== env.LAYER1_RUN_KEY) return json({ error: 'unauthorised' }, 401)
      let body = {}
      try { body = await request.json() } catch {}
      const country = String(body.country || 'AU').toUpperCase()
      const apply = body.apply === true
      const maxRecords = clamp(Number(body.maxRecords || 0), 0, 50000)
      try { return json(await runLayer1({ country, apply, maxRecords, env })) }
      catch (error) { return json({ error: error?.message || String(error), country, version: VERSION }, 500) }
    }

    return env.ASSETS ? env.ASSETS.fetch(request) : new Response('Not found', { status: 404 })
  },
}

async function runLayer1({ country, apply, maxRecords, env }) {
  const client = serviceClient(env)
  const sources = await rpc(client, 'svc_layer1_resolve_sources', { p_country_code: country })
  if (!Array.isArray(sources) || !sources.length) throw new Error(`No active Layer 1 source configured for ${country}`)
  const source = sources[0]
  const jobId = await rpc(client, 'svc_layer1_start_job', {
    p_country_code: country,
    p_source_id: source.source_id,
    p_payload: { version: VERSION, apply, max_records: maxRecords || null, source_system: source.system_code },
  })

  try {
    let result
    if (country === 'AU' && source.system_code === 'au_cricos') result = await runAuCricos({ client, source, jobId, apply, maxRecords, version: VERSION })
    else throw new Error(`No adapter implemented yet for ${country}/${source.system_code}`)

    await rpc(client, 'svc_layer1_source_health', {
      p_source_id: source.source_id, p_success: true,
      p_metadata: { worker_version: VERSION, latest_job_id: jobId, ...result.sourceHealth },
    })
    await rpc(client, 'svc_layer1_finish_job', { p_job_id: jobId, p_status: 'completed', p_result: result, p_error: null })
    return { ok: true, country, jobId, ...result }
  } catch (error) {
    const message = error?.message || String(error)
    await safeRpc(client, 'svc_layer1_source_health', { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION, latest_job_id: jobId } })
    await safeRpc(client, 'svc_layer1_finish_job', { p_job_id: jobId, p_status: 'failed', p_result: { worker_version: VERSION }, p_error: message })
    throw error
  }
}

function clamp(n, min, max) { return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.trunc(n))) : min }
function json(body, status = 200) { return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } }) }
