#!/usr/bin/env python3
# Guards: Fill fields (Platform Admin 9-10 Nov 2026), database-backed tests. Writes the live facts function and the earlier page function (renamed _before) out of migration 20261109220000
# and the earlier Run & Validate service (renamed _before) out of 20261106200000, so the fixture runs the live text, not a copy. Usage: extract.py <out dir>
import re, sys, os
out = sys.argv[1]
os.makedirs(out, exist_ok=True)
m = open('supabase/migrations/20261109220000_cf247_provider_catalogue_filter_speed.sql').read()
def func(text, head):
    i = text.index(head)
    a = text.index('$function$', i) + len('$function$')
    b = text.index('$function$', a)
    return text[i:b + len('$function$')] + ';\n'
open(f'{out}/facts.sql', 'w').write(func(m, 'CREATE OR REPLACE FUNCTION security.provider_catalogue_facts_v1'))
open(f'{out}/page_live.sql', 'w').write(func(m, 'CREATE OR REPLACE FUNCTION security.admin_providers_page_v3'))
open(f'{out}/page_before.sql', 'w').write(func(m, 'CREATE OR REPLACE FUNCTION security.admin_providers_page_v3').replace('admin_providers_page_v3', 'admin_providers_page_v3_before', 1))
a = open('supabase/migrations/20261106200000_cf247_provider_description_autonomy.sql').read()
i = a.index('create or replace function public.admin_provider_description_run_v1')
x = a.index('$function$', i) + len('$function$')
y = a.index('$function$', x)
open(f'{out}/run_live.sql', 'w').write(a[i:y + len('$function$')] + ';\n')
open(f'{out}/run_before.sql', 'w').write(a[i:y + len('$function$')].replace('admin_provider_description_run_v1', 'admin_provider_description_run_v1_before', 1) + ';\n')
print('extracted')
