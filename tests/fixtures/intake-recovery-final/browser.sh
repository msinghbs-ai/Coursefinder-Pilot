#!/usr/bin/env bash
# Guards: Platform Admin mandate 5 Nov 2026 12:44 §11, §12: the #872 browser-to-PostgreSQL workflow (preview, fix cohort, governed Run Now,
# verify, saved refresh, phone) run with migrations 20261105020000 and 20261105040000 applied: the failure-class trigger, the publication
# check and the plan v3 label in place end to end. Isolated database only.
set -euo pipefail
cd "$(dirname "$0")/../../.."
case "${PGHOST:-127.0.0.1}" in 127.0.0.1|localhost|/tmp|/var/run/postgresql) ;; *) echo 'Refusing a remote database: use isolated local PostgreSQL' >&2; exit 1;; esac
F=tests/fixtures/intake-calendar-v2; P=(psql -X -q -v ON_ERROR_STOP=1 -d intake_ui_fixtures)
bash tests/fixtures/intake-preview-timeout/run.sh > /dev/null  # the #872 database with #876 applied, as in production
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f $F/parity-tables.sql
"${P[@]}" -f $F/live-functions.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f supabase/migrations/20261105020000_cf247_intake_calendar_v2.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f tests/fixtures/intake-recovery-final/parity-tables.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f supabase/migrations/20261105040000_cf247_intake_recovery_final.sql
[ "$("${P[@]}" -Atc "select (position('intake-dates-plan-v3' in pg_get_functiondef('security.intake_ui_selection_v1(text,integer)'::regprocedure)) > 0)::text || ' ' || (select count(*) from pg_trigger where tgname = 'intake_failure_class')")" = 'true 2' ] || { echo 'final recovery not in place'; exit 1; }
echo 'PASS intake fixture database on plan v3 with the failure classes, publication check and plan v3 label'
npx playwright test --config=playwright.intake.config.mjs
"${P[@]}" -f tests/fixtures/intake-ui/post.sql
"${P[@]}" -Atc "select 'PASS browser run decisions classified: ' || count(*) || ' events, ' || count(*) filter (where failure_class is not null or outcome = 'filled') || ' with a class or filled' from pipeline.course_intake_date_events"
"${P[@]}" -Atc "select 'PASS publication check after the browser run: ' || security.intake_publication_check_v1()::text"
