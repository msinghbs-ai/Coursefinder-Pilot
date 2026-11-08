#!/usr/bin/env bash
# prints the live definition of security.course_entry_shared_page_v1 as the D-R2 migration created it (checked against the live md5 read 8 Nov 2026 by run.sh)
sed -n '/^create or replace function security.course_entry_shared_page_v1/,/^\$\$;/p' "$1/supabase/migrations/20261103070000_cf247_aer_dr2_dr3_supersede_and_matrix_gate.sql"
