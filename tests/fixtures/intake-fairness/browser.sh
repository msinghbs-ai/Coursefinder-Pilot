#!/usr/bin/env bash
# Guards: Platform Admin direction 5 Nov 2026 15:50 §6 (test the corrected workflow against the older mechanisms before release): the #872
# browser-to-PostgreSQL workflow (preview, fix cohort, governed Run Now, verify, saved refresh, phone) run with migrations 20261105020000,
# 20261105040000 and 20261105060000 applied: provider-fair plan, evidence gate and obsolete-edition rule in place end to end. Isolated only.
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
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -f tests/fixtures/intake-fairness/parity-tables.sql
PGOPTIONS='-c client_min_messages=warning' "${P[@]}" -1 -o /dev/null -f supabase/migrations/20261105060000_cf247_intake_fairness_precedence.sql
[ "$("${P[@]}" -Atc "select (position('intake_dates.provider_share' in pg_get_functiondef('security.intake_dates_plan_v3(uuid[],integer)'::regprocedure)) > 0)::text || ' ' || (select count(*) from pg_trigger where tgname = 'intake_failure_class')")" = 'true 2' ] || { echo 'fairness and precedence not in place'; exit 1; }
echo 'PASS intake fixture database with the provider-fair plan, evidence gate, obsolete-edition rule, failure classes and publication check'
npx playwright test --config=playwright.intake.config.mjs
"${P[@]}" -f tests/fixtures/intake-ui/post.sql
"${P[@]}" -Atc "select 'PASS browser run decisions classified: ' || count(*) || ' events, ' || count(*) filter (where failure_class is not null or outcome = 'filled') || ' with a class or filled' from pipeline.course_intake_date_events"
"${P[@]}" -Atc "select 'PASS publication check after the browser run: ' || security.intake_publication_check_v1()::text"
