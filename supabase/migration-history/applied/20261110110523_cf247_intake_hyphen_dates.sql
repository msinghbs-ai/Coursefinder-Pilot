-- CF-247 intake dates: read day-month-year dates written with hyphens ("01-March-2027").
-- Platform Admin, 10 Nov 2026 22:01: "Go ahead 1 and 4" (Group 1, Swinburne).
--
-- Why: Swinburne's page adapter stores start dates as "01-March-2027 | 02-August-2027".
-- The page-date route (intake_dates.page_date_admit = 1) and its hint read only
-- "1 March 2027" (spaces), so 303 Swinburne rows fell through to month only.
-- The plan's "course page gives its own start date" guard had the same gap.
--
-- What changes (exact, guarded substitutions; logic otherwise unchanged):
--   1 security.intake_page_date_hint_v1  day-month-year: separator may be spaces or one hyphen
--   2 security.intake_page_date_v1       v_f1 (day month year): same; capture groups unchanged
--   3 security.intake_dates_plan_v3      page-date contradiction guard: same
-- Effect on re-evaluation: the hint now marks hyphen rows as ready, which adds ';pagedate=1'
-- to their inputs fingerprint, so exactly those rows (only Swinburne at 10 Nov 2026) are looked at
-- again by the hourly intake-dates-apply run. No other provider's fingerprint changes.
-- Corroboration rules are unchanged: a page date is admitted only when an approved main calendar
-- start falls on the same day (P1) or the audience is shown (P2).
--
-- Baselines (md5 of pg_get_functiondef, live 10 Nov 2026 22:0x AEDT):
--   intake_page_date_hint_v1  80990dafd24d3bb10b930402289111ab
--   intake_page_date_v1       286a59d8e14326b0d7362aaa8fcdb5e2
--   intake_dates_plan_v3      a9cf65c211ce916a7dff0ef57b42e9ab

do $mig$
declare
  v_def text; v_new text;
begin
  -- 1 hint
  v_def := pg_get_functiondef('security.intake_page_date_hint_v1(uuid,uuid,text)'::regprocedure);
  if md5(v_def) <> '80990dafd24d3bb10b930402289111ab' then
    raise exception 'intake_page_date_hint_v1 has drifted from its baseline (md5 %); not changed', md5(v_def);
  end if;
  if (length(v_def) - length(replace(v_def, $o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')$o$, ''))) / length($o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')$o$) <> 1 then
    raise exception 'intake_page_date_hint_v1: pattern not found exactly once';
  end if;
  v_new := replace(v_def,
    $o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+20\d\d\M')$o$,
    $n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)20\d\d\M')$n$);
  execute v_new;

  -- 2 page-date reader
  v_def := pg_get_functiondef('security.intake_page_date_v1(uuid,uuid,uuid,uuid,text,integer,integer,jsonb,date,integer)'::regprocedure);
  if md5(v_def) <> '286a59d8e14326b0d7362aaa8fcdb5e2' then
    raise exception 'intake_page_date_v1 has drifted from its baseline (md5 %); not changed', md5(v_def);
  end if;
  if (length(v_def) - length(replace(v_def, $o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))'$o$, ''))) / length($o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))'$o$) <> 1 then
    raise exception 'intake_page_date_v1: pattern not found exactly once';
  end if;
  v_new := replace(v_def,
    $o$(?:st|nd|rd|th)?\s+' || v_mon || '\.?,?\s+(20\d\d)\M(?!\s*:))'$o$,
    $n$(?:st|nd|rd|th)?(?:\s+|-)' || v_mon || '\.?(?:,?\s+|-)(20\d\d)\M(?!\s*:))'$n$);
  execute v_new;

  -- 3 plan v3 guard
  v_def := pg_get_functiondef('security.intake_dates_plan_v3(uuid[],integer)'::regprocedure);
  if md5(v_def) <> 'a9cf65c211ce916a7dff0ef57b42e9ab' then
    raise exception 'intake_dates_plan_v3 has drifted from its baseline (md5 %); not changed', md5(v_def);
  end if;
  if (length(v_def) - length(replace(v_def, $o$(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M'$o$, ''))) / length($o$(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M'$o$) <> 1 then
    raise exception 'intake_dates_plan_v3: pattern not found exactly once';
  end if;
  v_new := replace(v_def,
    $o$(?:st|nd|rd|th)?\s+' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*,?\s+' || v_year || '\M'$o$,
    $n$(?:st|nd|rd|th)?(?:\s+|-)' || (array['jan','feb','mar','apr','may','jun','jul','aug','sep','oct','nov','dec'])[v_m] || '[a-z]*(?:,?\s+|-)' || v_year || '\M'$n$);
  execute v_new;
end
$mig$;
