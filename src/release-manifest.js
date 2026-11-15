// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.5'
export const PACKAGE_VERSION='0.1.427'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'16 Nov 2026',
  title:'Settings tidy-up: retiring settings set apart, every setting says what reads it and its unit, fewer sections',
  changes:[
    'Settings: 46 settings nothing live needs any more are marked Retiring, each with what replaced it: the 39 Serper and ScrapingBee settings (both services were dropped on 4 Oct 2026; their cards were already gone), four settings read only by switched-off jobs or retiring functions, and three AI model pins that the AI routes on Models & services replaced. The pipeline ones show in the Retiring group on Pipeline settings. A paste file removes them after the 14-day retirement period.',
    'Seven settings that were tied to retiring functions are still read by the functions that replaced them; their Used by now names the new readers (alerts, intake dates, calendar re-read).',
    'Every setting outside the Website API and Zoho API sections now says what reads it (Used by) and its unit; switches show on/off, lists and text say what they hold.',
    'Pipeline settings has 51 sections instead of 64: sections that overlapped are merged (for example the six scholarship sections are one, Scholarships). Only the headings changed; no setting key or value changed.',
    'Each of these changes is in the settings change log with its value before and after and the reason, like a change made on the screen.'
  ],
  bugFixes:[
    'The Serper and ScrapingBee sample-run notice check no longer reads their retiring tables and settings, so it keeps working when they are removed.',
    'The website and Zoho APIs are unchanged (checked against their baseline before and after the change).'
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
