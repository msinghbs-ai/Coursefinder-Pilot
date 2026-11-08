// Guards: Provider Description mandate §9/12, loopback-only SQL-backed browser transport. Never deploy this file.
// Test governance (G4), 8 Nov 2026: this transport answers with Connection: close so no client can reuse a socket this single-threaded
// server has closed or is blocked on (the PR #916 required check failed with ECONNRESET at a reused keep-alive socket and then, on the
// automatic retry, with a disabled button because the first attempt had already saved the only eligible cohort). Every request is
// timed and every socket error is logged, so a recurrence names its own cause. /fixture/reset returns the database to the state it
// had when this server started, so a retry begins where the first attempt began.
import http from 'node:http'
import { sql, quote, admin } from './db.mjs'
import { processNext, decideProvider } from './worker.mjs'
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const log=(...a)=>process.stdout.write(`[fixture ${new Date().toISOString()}] ${a.join(' ')}\n`)
process.on('uncaughtException',e=>{process.stderr.write(`[fixture] uncaughtException ${e&&e.stack||e}\n`)})
process.on('unhandledRejection',e=>{process.stderr.write(`[fixture] unhandledRejection ${e&&e.stack||e}\n`)})
const BASELINE='pdesc_autonomy_baseline'
let baselineReady=false
try{
  admin(`drop database if exists ${BASELINE} with (force); create database ${BASELINE} template pdesc_autonomy;`)
  baselineReady=true
  log('baseline copy ready for retries')
}catch(e){log('baseline copy NOT created; a retry cannot be reset:',String(e.stderr||e.message||e).slice(0,400))}
const server=http.createServer(async(req,res)=>{
  const started=Date.now()
  res.setHeader('content-type','application/json')
  res.setHeader('connection','close')
  res.on('finish',()=>log(req.method,req.url,res.statusCode,`${Date.now()-started}ms`))
  if(req.method==='GET'&&req.url==='/health'){res.end(JSON.stringify({ok:true,database:'isolated pdesc_autonomy'}));return}
  try {
    if(req.method!=='POST')throw new Error('POST required')
    let body='';for await(const chunk of req){body+=chunk;if(body.length>262144)throw new Error('request too large')}
    const args=JSON.parse(body||'{}')
    let result
    if(['/rest/v1/rpc/admin_provider_description_run_v1','/rest/v1/rpc/admin_provider_descriptions'].includes(req.url)){
      const rank=Number(req.headers['x-fixture-rank']||6)
      const name=req.url.endsWith('/admin_provider_descriptions')?'admin_provider_descriptions':'admin_provider_description_run_v1'
      result=sql(`select public.${name}(${quote(args.p_action)},${quote(JSON.stringify(args.p_args||{}))}::jsonb);`,{rank,json:true})
    }else if(req.url==='/fixture/reset'){
      if(!baselineReady)throw new Error('no baseline copy; the database cannot be reset')
      admin(`drop database pdesc_autonomy with (force); create database pdesc_autonomy template ${BASELINE}; alter database pdesc_autonomy set jit=off; alter database pdesc_autonomy set work_mem='7168kB'; alter database pdesc_autonomy set max_parallel_workers_per_gather=1;`)
      result={reset:true}
    }else if(['/fixture/process','/fixture/approve'].includes(req.url)){
      if(!uuid.test(args.cohort_id||''))throw new Error('isolated cohort_id required')
      const cohort=sql(`select security.provider_description_run_result_v1(${quote(args.cohort_id)}::uuid);`,{role:'postgres',json:true})
      if(req.url==='/fixture/process')result=processNext(10,args.cohort_id)
      else result=cohort.providers.filter(p=>p.state==='proposed').map(p=>decideProvider(p.provider_id))
    }else throw new Error('Unknown fixture route')
    res.end(JSON.stringify(result))
  }catch(e){res.statusCode=400;res.end(JSON.stringify({message:String(e.stderr||e.message||e).slice(0,6000),code:'FIXTURE_SQL_ERROR'}))}
})
server.on('clientError',(e,socket)=>{log('clientError',e.code||e.message);if(socket.writable)socket.end('HTTP/1.1 400 Bad Request\r\nConnection: close\r\n\r\n')})
server.on('connection',socket=>{socket.on('error',e=>log('socket error',e.code||e.message))})
server.listen(55435,'127.0.0.1',()=>process.stdout.write('Isolated provider-description SQL RPC transport http://127.0.0.1:55435\n'))
