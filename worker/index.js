import { serviceClient, rpc, safeRpc } from './lib/service'
import { runAuCricos } from './adapters/au-cricos'

const VERSION = 'layer1-v0.1.3'

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url)

    if (url.pathname === '/api/layer1/health') {
      const bindings = {
        supabaseUrl: Boolean(env.SUPABASE_URL),
        serviceRoleKey: Boolean(env.SUPABASE_SERVICE_ROLE_KEY),
        runKey: Boolean(env.LAYER1_RUN_KEY),
        assets: Boolean(env.ASSETS),
      }
      return json({ ok: true, service: 'coursefinder-layer1', version: VERSION, configured: bindings.supabaseUrl && bindings.serviceRoleKey && bindings.runKey, bindings })
    }

    if (url.pathname === '/api/layer1/run' && request.method === 'POST') {
      const client = serviceClient(env)
      const authorised = await authoriseRun(request, env, client)
      if (!authorised.ok) return json({ error: 'unauthorised' }, 401)

      let body = {}
      try { body = await request.json() } catch {}
      const country = String(body.country || 'AU').toUpperCase()
      const apply = body.apply === true
      const maxRecords = clamp(Number(body.maxRecords || 0), 0, 50000)

      try {
        const prepared = await prepareLayer1({ country, apply, maxRecords, env, requestedBy: authorised.userId })
        ctx.waitUntil(executeLayer1({ ...prepared, country, apply, maxRecords, env }))
        return json({ ok: true, accepted: true, country, jobId: prepared.jobId, status: 'running', version: VERSION }, 202)
      } catch (error) {
        return json({ error: error?.message || String(error), country, version: VERSION }, 500)
      }
    }

    return env.ASSETS ? env.ASSETS.fetch(request) : new Response('Not found', { status: 404 })
  },
}

async function authoriseRun(request, env, client) {
  const runKey = request.headers.get('x-layer1-key')
  if (env.LAYER1_RUN_KEY && runKey && runKey === env.LAYER1_RUN_KEY) return { ok: true, userId: null }

  const auth = request.headers.get('authorization') || ''
  const token = auth.toLowerCase().startsWith('bearer ') ? auth.slice(7).trim() : ''
  if (!token) return { ok: false }

  const { data, error } = await client.auth.getUser(token)
  if (error || !data?.user?.id) return { ok: false }
  const allowed = await rpc(client, 'svc_layer1_authorize_platform_admin', { p_user_id: data.user.id })
  return { ok: allowed === true, userId: data.user.id }
}

async function prepareLayer1({ country, apply, maxRecords, env, requestedBy }) {
  const client = serviceClient(env)
  const sources = await rpc(client, 'svc_layer1_resolve_sources', { p_country_code: country })
  if (!Array.isArray(sources) || !sources.length) throw new Error(`No active Layer 1 source configured for ${country}`)
  const source = sources[0]
  const jobId = await rpc(client, 'svc_layer1_start_job', {
    p_country_code: country,
    p_source_id: source.source_id,
    p_payload: { version: VERSION, apply, max_records: maxRecords || null, source_system: source.system_code, requested_by: requestedBy || null },
  })
  return { source, jobId }
}

async function executeLayer1({ country, apply, maxRecords, env, source, jobId }) {
  const client = serviceClient(env)
  try {
    let result
    if (country === 'AU' && source.system_code === 'au_cricos') result = await runAuCricos({ client, source, jobId, apply, maxRecords, version: VERSION })
    else throw new Error(`No adapter implemented yet for ${country}/${source.system_code}`)

    await rpc(client, 'svc_layer1_source_health', {
      p_source_id: source.source_id, p_success: true,
      p_metadata: { worker_version: VERSION, latest_job_id: jobId, ...result.sourceHealth },
    })
    await rpc(client, 'svc_layer1_finish_job', { p_job_id: jobId, p_status: 'completed', p_result: result, p_error: null })
  } catch (error) {
    const message = error?.message || String(error)
    await safeRpc(client, 'svc_layer1_source_health', { p_source_id: source.source_id, p_success: false, p_error: message, p_metadata: { worker_version: VERSION, latest_job_id: jobId } })
    await safeRpc(client, 'svc_layer1_finish_job', { p_job_id: jobId, p_status: 'failed', p_result: { worker_version: VERSION }, p_error: message })
  }
}

function clamp(n, min, max) { return Number.isFinite(n) ? Math.min(max, Math.max(min, Math.trunc(n))) : min }
function json(body, status = 200) { return new Response(JSON.stringify(body), { status, headers: { 'content-type': 'application/json; charset=utf-8', 'cache-control': 'no-store' } }) }
