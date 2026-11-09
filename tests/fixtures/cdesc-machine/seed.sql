-- Guards: F-CDESC (Platform Admin decision 10 Nov 2026): the live settings the machine rule reads, with the live values read on 10 Nov 2026 (project fxcwkweaxjtknorudmwp), added where the course-description fixture does not carry them.
\set ON_ERROR_STOP 1
insert into pipeline.platform_toolset_settings(toolset_key, key, label, help, kind, value, min_value, max_value, unit, sort, section, used_by) values
 ('pipeline', 'gaps.recheck_days', 'r', 'h', 'number', '60', 7, 365, 'days', 104, 'Re-read and retry', 'security.field_gap_queue_tick_v1'),
 ('pipeline', 'pdesc.evidence_claim_words', 'e', 'h', 'list', '["campus", "scholarship", "guarantee"]', null, null, 'words', 993, 'Provider descriptions', 'x'),
 ('pipeline', 'pdesc.machine_refused_words', 'm', 'h', 'list', '["visa", "visas", "migration", "immigration", "fee", "fees", "tuition", "funding", "loan", "loans", "bursary", "bursaries", "scholarships", "pathway", "pathways", "guaranteed", "accredited", "partner", "partners", "partnership", "campuses"]', 0, null, 'words', 1001, 'Provider descriptions', 'x'),
 ('pipeline', 'pdesc.machine_refused_words_fr', 'f', 'h', 'list', '["classement", "meilleur", "excellence", "campus", "bourse", "visa", "frais", "tuition"]', 0, null, 'words', 1017, 'Provider descriptions', 'x'),
 ('pipeline', 'pdesc.machine_neutral_words', 'n', 'h', 'list', '["students", "staff", "alumni"]', 0, null, 'words', 1022, 'Provider descriptions', 'x'),
 ('pipeline', 'pdesc.machine_numbers_allowed', 'nu', 'h', 'number', '0', 0, 1, 'on/off', 1002, 'Provider descriptions', 'x'),
 ('pipeline', 'pdesc.founded_year_min', 'y', 'h', 'number', '1800', 1000, 2000, 'year', 1011, 'Provider descriptions', 'x')
on conflict (toolset_key, key) do nothing;
