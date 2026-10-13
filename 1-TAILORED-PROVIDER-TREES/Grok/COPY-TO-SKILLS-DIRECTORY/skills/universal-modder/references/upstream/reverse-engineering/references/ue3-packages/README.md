# Compressed UE3 packages

Work on an owned copy outside the installed game. Inspect the package version
and compression before choosing a reader: a valid header with no exports is
not proof that the package is empty.

Use a discovered community tool first:
[Gildor's Unreal Package Decompressor](https://www.gildor.org/downloads)
([source](https://github.com/gildor2/UEViewer/tree/master/Tools/PackageUnpack)).
Verify its current supported formats and the actual target; this bundle does
not certify decompression/rebuilding of a particular game.

The upstream snapshot also contains a small `unpack_upk.py` fallback. UABS does
not redistribute it: it allocates from package-declared sizes and overwrites
the supplied output without bounds or overwrite protection. It is not a
replacement for the existing RE tool bench. The retained knowledge note
`um kb search ue3` is historical evidence, not permission to run unreviewed
code or guess compression-table offsets.
