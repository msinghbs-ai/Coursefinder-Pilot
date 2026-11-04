// Guards: Provider Description §8, exact production pg_get_functiondef hashes including stored CRLF bodies.
// psql stdin/file mode normalises CRLF; one -c argument retains the authoritative body bytes.
import fs from 'node:fs'
import {execFileSync}from'node:child_process'
const rows=JSON.parse(fs.readFileSync(new URL('./production-crlf-functions.json',import.meta.url)))
const env={...process.env};for(const k of ['DOCKER_HOST','DOCKER_CONTEXT','DOCKER_TLS','DOCKER_TLS_VERIFY','DOCKER_CERT_PATH'])delete env[k]
for(const r of rows)execFileSync('docker',['--host=unix:///var/run/docker.sock','exec','pdesc-autonomy-pg','psql','-U','postgres','-X','-q','-v','ON_ERROR_STOP=1','-d','pdesc_autonomy','-c','set check_function_bodies=off;'+r.definition+';'],{env,stdio:['pipe','pipe','pipe']})
