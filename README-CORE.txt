Core release: the vendored third-party offline payloads are omitted and
installed from source or downloaded when absent. Full-Offline carries
archive/wheel snapshots; uncached runtimes and dependencies may need network.

Skyrim Forge is one of those payloads: it is downloaded from its pinned
GitHub release (SHA-256 checked) only when the Skyrim pack is on.
