// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.15.100'
export const PACKAGE_VERSION='0.1.27'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'28 Sep 2026',
  title:'Layer 1 closed: every source checks, updates and retires on its own',
  changes:[
    'NZQA runs now record every course they read; a course NZQA no longer lists is retired at the end of the run, with the same audit and approval limit as CRICOS (21 retired on the first run).',
    'Every Layer 1 source, including the QS and THE rankings, is now checked on its schedule. Licensed ranking uploads are checked against the stored upload.',
    'Statistics datasets find their own new editions: a monthly check reads each publisher page, finds new files and test-reads them without writing anything. The Layer 1 card shows the new edition with an Apply action. QILT appears as one card with a tab per survey.',
    'THE rankings 2016 to 2024 are now applied, so THE has every edition from 2016 to 2026; QS has every edition from 2021 to 2027.',
    'Layer 4 has a Provider departures list: providers whose courses have all left the register are decided as closed, merged into a successor, or reviewed.',
    'Australian and New Zealand register codes are recorded as country-scoped identifiers, kept in step automatically (Decision 149).'
  ],
  bugFixes:[
    'The run summary counted retired registrations as current (26,787 instead of 25,978 CRICOS courses).',
    'Scheduled QILT and PRISMS checks failed because the worker called functions it did not define.',
    'QS and THE sources could not be queued or checked on schedule because they have no country.',
    'The current QS 2025 edition had been loaded from a workbook read with the region in the country column, so no university was matched; the correct load of the same edition is current again.',
    'The THE "2015" edition was the 2021 file under the wrong year (all 1,526 rows identical); it is withdrawn.',
    'The Zoho course lookup now applies the Layer 4 search block to matches by course code as well.'
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
