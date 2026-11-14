// Canonical browser-visible release and recovery authority.
// New releases must change this file rather than defining competing current-version literals elsewhere.
export const UI_VERSION='2.16.2'
export const PACKAGE_VERSION='0.1.424'
export const RELEASE_STATE='candidate'
export const RELEASE={
  version:UI_VERSION,
  packageVersion:PACKAGE_VERSION,
  date:'14 Nov 2026',
  title:'Firecrawl format profiles: what every page read asks for, set per lane',
  changes:[
    'Models & services › Services & limits › Firecrawl: a new card, Format profiles, sets what every Firecrawl page read asks for. Each profile names its formats (markdown, rawHtml, html, links, screenshot), whether only the main content is kept, tags to leave out or keep, how old a Firecrawl copy may be, the wait and time allowed, optional actions before the read, and crawl options.',
    'json, summary, question, highlights and onlyCleanContent can never be asked for: the screen lists them as Never sent, and the database and the worker refuse them too. Each costs extra credits or runs an AI pass over the page.',
    'Each lane (course page reads, Run now reads, About pages, lists, register pages and so on) is mapped to a profile, and a university can have its own profile for one lane. Entry requirement lanes (AER v1, frozen) and adapter capture keep their own request.',
    'By default a page read asks for rawHtml and markdown together, in one call of one credit. Course page reads, Run now reads and About pages keep the markdown beside the stored page, and the evidence row records the profile and its version, the formats asked for, Firecrawl\'s cache state, the page\'s own status and the credits used.',
    'Run now and other on-demand reads always ask Firecrawl for a fresh page; scheduled reads may use Firecrawl\'s copy of up to 48 hours.',
    'Course pages stay whole page (not main content only) until a test read shows the stored page keeps its side-panel entry bands.',
    'Screenshots are off in every profile; a screenshot a profile asks for is kept as received, up to the size set on the card. Crawl options are checked and saved; no lane crawls yet.',
    'Every change is saved with a reason as a new version; a save made after someone else\'s is refused, so nothing is overwritten. Pipeline Operator and above can read the card; only the Platform Admin can change it.'
  ],
  bugFixes:[
    'The generic Firecrawl settings table no longer offers a set of values as a line of text to change.'
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
