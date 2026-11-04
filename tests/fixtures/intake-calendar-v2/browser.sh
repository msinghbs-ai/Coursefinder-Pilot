#!/usr/bin/env bash
# Guards: Platform Admin decision 5 Nov 2026 §9: the #872 browser-to-PostgreSQL workflow (preview, fix cohort, governed Run Now, verify, saved
# refresh, phone) run again with migration 20261105020000 applied, so Preview, cohort and job use plan v3 end to end. Isolated database only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
F=tests/fixtures/intake-calendar-v2; P=(psql -X -q -v ON_ERROR_STOP=1 -d intake_ui_fixtures)
bash tests/fixtures/intake-preview-timeout/run.sh > /dev/null  # the #872 database with #876 applied, as in production
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/parity-tables.sql
"${P[@]}" -f $F/live-functions.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f supabase/migrations/20261105020000_cf247_intake_calendar_v2.sql
[ "$("${P[@]}" -Atc "select md5(pg_get_functiondef('security.intake_ui_selection_v1(text,integer)'::regprocedure)) || ' ' || (position('intake_dates_plan_v3' in pg_get_functiondef('security.intake_dates_apply_v1(integer,uuid[])'::regprocedure)) > 0)::text")" = '36ecb3ad4d8fbd7a398e570159dfe4c8 true' ] || { echo 'plan v3 not in place'; exit 1; }
echo 'PASS intake fixture database now on plan v3 (selection 36ecb3ad, apply uses plan v3)'
npx playwright test --config=playwright.intake.config.mjs
"${P[@]}" -f tests/fixtures/intake-ui/post.sql
"${P[@]}" -Atc "select 'PASS decisions appended for the browser run: ' || count(*) || ' events, ' || count(*) filter (where bounded) || ' from the governed Run Now' from pipeline.course_intake_date_events"
