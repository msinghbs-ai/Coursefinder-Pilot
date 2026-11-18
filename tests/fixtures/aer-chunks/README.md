# AER table row chunker fixtures (CF-247 S744 to S746)

- `national-qualifications.json`: the national qualification alias list the chunker is given in tests (code, country, aliases). In the worker the same list comes from a setting; it is data, never a word list in code (G2, Decision 276).
- `held/`: stored copies of entry-matrix pages whose reads wait in Layer 4, exported read only by workflow `aer-entry-inspect.yml` (S742; worker mode `entry_inspect`: title, h1 and table markup). Each file is gzipped HTML named by the source's address; `held/manifest.json` gives the source, content hash, run and the counts the export recorded. Used by spec S745.
