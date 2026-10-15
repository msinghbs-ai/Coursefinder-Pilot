#!/usr/bin/env python3
"""Export row sets to the private Storage bucket before a paste file purges or drops them (CF-247, 15 Oct 2026).

Used by .github/workflows/db-archive-export.yml. Reads one definition file from supabase/archive/<name>.json. For each set:
  1. counts the rows and hashes their keys in the database (the same count and hash the paste file checks before removing anything);
  2. reads the rows page by page as JSON (read-only selects through the Supabase Management API);
  3. writes them as gzipped JSON lines, uploads them to Storage, downloads each object again and checks its sha256, line count and
     key hash against the database figures.
A manifest (counts, key hashes, objects, sha256) is uploaded last and printed. Nothing in the database is changed.
Environment: SUPABASE_ACCESS_TOKEN, PROJECT_REF, DEFINITION, RUN_ID, GIT_SHA.
"""
import gzip, hashlib, io, json, os, re, sys, time, urllib.error, urllib.request

TOKEN = os.environ['SUPABASE_ACCESS_TOKEN']
REF = os.environ['PROJECT_REF']
DEF = os.environ['DEFINITION']
RUN = os.environ.get('RUN_ID', 'local')
SHA = os.environ.get('GIT_SHA', '')
PAGE = int(os.environ.get('PAGE_ROWS', '1000'))
STORAGE = f'https://{REF}.supabase.co/storage/v1'


def http(method, url, body=None, headers=None, raw=False):
    data = body if isinstance(body, (bytes, type(None))) else json.dumps(body).encode()
    h = {'Content-Type': 'application/json'}
    h.update(headers or {})
    for attempt in range(5):
        req = urllib.request.Request(url, data=data, method=method, headers=h)
        try:
            with urllib.request.urlopen(req, timeout=300) as r:
                b = r.read()
                return r.status, (b if raw else (json.loads(b) if b else None))
        except urllib.error.HTTPError as e:
            b = e.read()
            if e.code in (429, 502, 503, 504) and attempt < 4:
                time.sleep(5 * (attempt + 1)); continue
            return e.code, b.decode('utf-8', 'replace')[:800]
        except urllib.error.URLError:
            if attempt < 4:
                time.sleep(5 * (attempt + 1)); continue
            raise


def q(sql):
    code, out = http('POST', f'https://api.supabase.com/v1/projects/{REF}/database/query', {'query': sql},
                     {'Authorization': f'Bearer {TOKEN}'})
    if code >= 300:
        sys.exit(f'::error::query failed ({code}): {out}')
    return out


def keyexpr(key):
    return '(z.%s)::text' % key if key else 'md5(to_jsonb(z)::text)'


def pykey(key, line):
    if not key:
        return hashlib.md5(line.encode()).hexdigest()
    v = json.loads(line)[key]
    return ('true' if v else 'false') if isinstance(v, bool) else str(v)


def main():
    d = json.load(open(DEF))
    for s in d['sets']:
        sel = s['select'].strip()
        if not re.match(r'(?is)^select\s', sel) or ';' in sel or re.search(r'(?i)\b(insert|update|delete|drop|truncate|alter|grant|create)\b', sel):
            sys.exit(f"::error::set {s['name']}: only a single read-only select is allowed")
    code, keys = http('GET', f'https://api.supabase.com/v1/projects/{REF}/api-keys?reveal=true', None, {'Authorization': f'Bearer {TOKEN}'})
    if code >= 300:
        sys.exit(f'::error::could not read the project keys ({code})')
    svc = next((k['api_key'] for k in keys if k.get('name') == 'service_role' and k.get('api_key')), None)
    if not svc:
        sys.exit('::error::no service_role key returned')
    print(f'::add-mask::{svc}')
    auth = {'Authorization': f'Bearer {svc}', 'apikey': svc}
    code, out = http('POST', f'{STORAGE}/bucket', {'id': d['bucket'], 'name': d['bucket'], 'public': False}, auth)
    if code >= 300 and 'already exists' not in str(out).lower() and 'duplicate' not in str(out).lower():
        sys.exit(f'::error::bucket {d["bucket"]}: {code} {out}')
    base = f"{d['prefix']}/{RUN}"
    manifest = {'definition': os.path.basename(DEF), 'definition_sha256': hashlib.sha256(open(DEF, 'rb').read()).hexdigest(), 'git_sha': SHA,
                'run_id': RUN, 'bucket': d['bucket'], 'prefix': base, 'exported_at': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()), 'sets': []}
    for s in d['sets']:
        sel, key = s['select'].strip(), s.get('key')
        k = keyexpr(key)
        head = q(f"select count(*)::bigint n, md5(coalesce(string_agg(k, ',' order by k collate \"C\"), '')) h from (select {k} k from ({sel}) z) y")[0]
        n, h = int(head['n']), head['h']
        lines, off = [], 0
        while off < n:
            rows = q(f"select to_jsonb(z)::text j from ({sel}) z order by {k} collate \"C\" limit {PAGE} offset {off}")
            if not rows:
                break
            lines += [r['j'] for r in rows]
            off += len(rows)
        if len(lines) != n:
            sys.exit(f"::error::{s['name']}: read {len(lines)} rows, database counts {n}")
        if hashlib.md5(','.join(sorted(pykey(key, l) for l in lines)).encode()).hexdigest() != h:
            sys.exit(f"::error::{s['name']}: key hash of the rows read differs from the database")
        parts = []
        per = int(d.get('part_rows', 20000))
        for i in range(0, max(n, 1), per):
            chunk = lines[i:i + per]
            buf = gzip.compress(('\n'.join(chunk) + ('\n' if chunk else '')).encode(), 9, mtime=0)
            path = f"{base}/{s['name']}/part-{i // per:03d}.jsonl.gz"
            code, out = http('POST', f"{STORAGE}/object/{d['bucket']}/{path}", buf, dict(auth, **{'Content-Type': 'application/gzip', 'x-upsert': 'false'}))
            if code >= 300:
                sys.exit(f"::error::upload {path}: {code} {out}")
            parts.append({'path': path, 'rows': len(chunk), 'bytes': len(buf), 'sha256': hashlib.sha256(buf).hexdigest()})
        # read back every object and check it
        back = []
        for p in parts:
            code, b = http('GET', f"{STORAGE}/object/{d['bucket']}/{p['path']}", None, auth, raw=True)
            if code >= 300 or hashlib.sha256(b).hexdigest() != p['sha256']:
                sys.exit(f"::error::read-back {p['path']}: {code} sha256 differs")
            t = gzip.decompress(b).decode()
            got = [l for l in t.split('\n') if l]
            if len(got) != p['rows']:
                sys.exit(f"::error::read-back {p['path']}: {len(got)} lines, expected {p['rows']}")
            back += got
        if hashlib.md5(','.join(sorted(pykey(key, l) for l in back)).encode()).hexdigest() != h:
            sys.exit(f"::error::{s['name']}: key hash of the stored objects differs from the database")
        manifest['sets'].append({'name': s['name'], 'select_md5': hashlib.md5(sel.encode()).hexdigest(), 'key': key, 'rows': n, 'key_hash': h, 'parts': parts})
        print(f"{s['name']}: {n} rows, key hash {h}, {len(parts)} object(s), {sum(p['bytes'] for p in parts)} bytes; read back and checked")
    mb = json.dumps(manifest, indent=1).encode()
    code, out = http('POST', f"{STORAGE}/object/{d['bucket']}/{base}/manifest.json", mb, dict(auth, **{'Content-Type': 'application/json', 'x-upsert': 'false'}))
    if code >= 300:
        sys.exit(f'::error::manifest upload: {code} {out}')
    code, b = http('GET', f"{STORAGE}/object/{d['bucket']}/{base}/manifest.json", None, auth, raw=True)
    if code >= 300 or b != mb:
        sys.exit('::error::manifest read-back differs')
    print('MANIFEST ' + json.dumps(manifest))


if __name__ == '__main__':
    main()
