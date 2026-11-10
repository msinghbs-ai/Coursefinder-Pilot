#!/usr/bin/env python3
# Guards: F-PDESC.01-.05 (sentence-subset recovery): writes the LIVE security.provider_description_fill_status_v1 out of migration 20261110030000 (the migration that made it), so the fixture edits the live text, not a copy. Usage: extract_fill_status.py <out file>
import sys
m = open('supabase/migrations/20261110030000_cf247_provider_fill_fields.sql').read()
i = m.index('create or replace function security.provider_description_fill_status_v1')
a = m.index('$function$', i) + len('$function$')
b = m.index('$function$', a) + len('$function$')
open(sys.argv[1], 'w').write(m[i:b] + ';\n')
