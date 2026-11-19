create or replace function security.course_fee_one_current_trg()
returns trigger language plpgsql security definer set search_path to 'pg_catalog','security','catalogue'
as $$
begin
  if new.fee_type='provider_current_tuition' and new.status='active' then
    perform security.course_fee_dedupe_v1(true, array[new.course_id]);
  end if;
  return null;
end $$;
revoke all on function security.course_fee_one_current_trg() from public, anon, authenticated;
drop trigger if exists course_fee_one_current on catalogue.course_fees;
create trigger course_fee_one_current after insert or update of status on catalogue.course_fees
for each row when (new.status='active' and new.fee_type='provider_current_tuition')
execute function security.course_fee_one_current_trg();
