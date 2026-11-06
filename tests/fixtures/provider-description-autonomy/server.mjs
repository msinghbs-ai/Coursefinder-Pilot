// Guards: Provider Description mandate §9/12, loopback-only SQL-backed browser transport. Never deploy this file.
import http from 'node:http'
import { sql, quote } from './db.mjs'
import { processNext, decideProvider } from './worker.mjs'
const uuid=/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i
const server=http.createServer(async(req,res)=>{
  res.setHeader('content-type','application/json')
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
    }else if(['/fixture/process','/fixture/approve'].includes(req.url)){
      if(!uuid.test(args.cohort_id||''))throw new Error('isolated cohort_id required')
      const cohort=sql(`select security.provider_description_run_result_v1(${quote(args.cohort_id)}::uuid);`,{role:'postgres',json:true})
      if(req.url==='/fixture/process')result=processNext(10,args.cohort_id)
      else result=cohort.providers.filter(p=>p.state==='proposed').map(p=>decideProvider(p.provider_id))
    }else throw new Error('Unknown fixture route')
    res.end(JSON.stringify(result))
  }catch(e){res.statusCode=400;res.end(JSON.stringify({message:String(e.stderr||e.message||e).slice(0,6000),code:'FIXTURE_SQL_ERROR'}))}
})
server.listen(55435,'127.0.0.1',()=>process.stdout.write('Isolated provider-description SQL RPC transport http://127.0.0.1:55435\n'))
