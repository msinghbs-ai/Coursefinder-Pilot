// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.107'
export const PACKAGE_VERSION='0.1.34'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'29 Sep 2026',
  title:'Simpler menu, one page layout, Platform health, Layer 3 at a glance, sources side by side',
  changes:[
    'The menu has five plain sections: Catalogue, Data pipeline, Operations, Platform settings and Administration. Screens that were near-duplicates are now tabs of one page (for example Jobs and Schedules, Providers and Campuses, Rankings, Compare, QILT and PRISMS). Old links still open the right page.',
    'Every screen now sits inside the same frame: the same side menu, top bar, page title and tabs. Coverage & completeness no longer opens as a separate full-screen view with its own menu.',
    'New Platform health page (Operations): overall status, open issues by area, every automatic check and the last 14 days. A coloured dot in the top bar and the menu shows the status at a glance.',
    'Layer 3 AI validation is one page with tabs: Routing (the model used for each task, today\'s calls and spend), Models & profiles (active, candidates, retired), Test results (stated exact, wrong admitted, withheld, cost) and Spend (per day and profile against ceilings). The existing work queue is its own tab.',
    'Scholarship detail shows the provider\'s own page next to Study Australia, and course detail shows the provider page next to the regulator (CRICOS). Values that differ are highlighted; both sources are kept.',
    'Environment & integrations lists the external services (configured or not), stored keys by name only, and usage against budgets.'
  ],
  bugFixes:[
    'Coverage & completeness did not show the main menu and had a different sub-menu.',
    'The scheduled-workflow builder only appeared on the old Scheduled Tasks address, not on the Schedules tab.',
    'Layer 3 cost ceilings read "$US$0.0500" (doubled currency sign).'
  ]
}

// Ordered accepted releases. The first item is the only recovery baseline for a new candidate.
// Historical releases before this central manifest remain retained by the legacy release-history source.
export const ACCEPTED_RELEASES=[
  {
    version:'2.15.79',
    packageVersion:'0.1.6',
    date:'14 Sep 2026',
    pilotMain:'32be4e96a8df342deba3011f9740dc1230a672b2',
    title:'Dispatcher tuning & run metrics',
    changes:[
      'Administration > Scraper Config now separates vendor controls from governed Layer 2 dispatcher tuning.',
      'Admins can compare recent runs using throughput, response/extraction latency, retries, Evidence, field resolution and Layer 2/Layer 3/blocked outcomes.',
      'PIM/Data Admins can tune batch size, run concurrency, stale recovery and paid-attempt limits for subsequent runs with an auditable governance reason.',
      'Running batches retain their immutable policy snapshot; tuning never rewrites work already in flight.',
      'Hourly CourseFinder metrics track dispatcher continuations, provider performance, Evidence and policy snapshots for evidence-based tuning.'
    ],
    bugFixes:[
      'Retains the Layer 2 runner transport safety cap introduced by PR #84: ordinary invocations remain capped at four items and scraper-first invocations at two.',
      'Dispatcher metrics are sanitized and do not expose raw payloads, result/error text, target URLs, Storage paths or provider credentials.',
      'Preserves Layer 1 authority, Layer 3 Evidence/profile/model governance, Layer 4 human authority and separate Search/Publication admission.'
    ]
  }
]

export const RECOVERY_RELEASE=ACCEPTED_RELEASES[0]
