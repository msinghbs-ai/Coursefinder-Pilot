# CF-247 canonical migration squash (Platform Admin 17 Nov 2026; admin docs/platform/MIGRATION-SQUASH-RUNBOOK.md).
# Sourced by fixture scripts that apply migration files by name. migpath NAME prints the absolute path of NAME (with or without .sql)
# in supabase/migrations or, once the squash has archived it, supabase/migrations-archive. Before the squash it always prints the live path.
_mp_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
migpath() {
  local n="${1%.sql}.sql" d
  for d in supabase/migrations supabase/migrations-archive; do
    if [ -f "$_mp_root/$d/$n" ]; then printf '%s\n' "$_mp_root/$d/$n"; return 0; fi
  done
  printf '%s\n' "$_mp_root/supabase/migrations/$n"
}
