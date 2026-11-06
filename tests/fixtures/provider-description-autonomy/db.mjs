// Guards: Provider Description mandate §8–9. Fixed local Docker database transport; no production URL accepted.
import { execFileSync } from 'node:child_process'
export const quote = s => "'" + String(s).replaceAll("'", "''") + "'"
export function sql(statement, { rank = 6, role = 'authenticated', json = false } = {}) {
  if (!Number.isInteger(rank) || rank < 0 || rank > 6 || !['authenticated','service_role','postgres'].includes(role)) throw new Error('invalid isolated identity')
  const identity = rank===6 ? '90000000-0000-0000-0000-0000000000aa' : `90000000-0000-0000-0000-${String(rank).padStart(12,'0')}`
  const cmd = `set check_function_bodies=off; set fx.uid='${identity}'; set fx.rank='${rank}'; set fx.role='${role}'; set jit=off; set work_mem='7168kB'; set max_parallel_workers_per_gather=1; set statement_timeout='8s'; set lock_timeout='0'; ${role==='postgres'?'':`set role ${role};`} ${statement}`
  const env = { ...process.env }
  for (const k of ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH']) delete env[k]
  const out = execFileSync('docker', ['--host=unix:///var/run/docker.sock','exec','-i','pdesc-autonomy-pg','psql','-U','postgres','-X','-q','-A','-t','-v','ON_ERROR_STOP=1','-d','pdesc_autonomy'], { input:cmd, encoding:'utf8', env, maxBuffer:8*1024*1024 }).trim()
  return json ? (out ? JSON.parse(out.split('\n').at(-1)) : null) : out
}
