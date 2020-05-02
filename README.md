# GBWT

Graph BWT is an independent implementation of the graph extension (gPBWT) of the positional Burrows-Wheeler transform (PBWT). Its initial purpose is to embed observed haplotypes in a [variation graph](https://github.com/vgteam/vg).
Haplotypes are essentially sequences of nodes in the variation graph, and GBWT is best seen as the multi-string BWT of the node sequences.

See [the wiki](https://github.com/jltsiren/gbwt/wiki) for further documentation.

## Overview

GBWT is a multi-string FM-index for indexing large collections of similar paths over a graph. The paths are interpreted as sequences of node identifiers, and the sequences are stored in the FM-index. The index is stored in a number of records corresponding to the nodes of the graph. Hence the GBWT can often take advantage memory locality when the queries traverse adjacent nodes.

There are three variants of the GBWT:

* Compressed GBWT is space-efficient and reasonably fast.
* Dynamic GBWT is a faster and larger variant intended for index construction.
* Cached GBWT is a cache layer on top of the compressed GBWT. It improves the performance when we repeatedly traverse se same subset of nodes.

The GBWT uses three main construction algorithms:

* An algorithm inspired by [RopeBWT2](https://github.com/lh3/ropebwt2) that inserts a batch of new paths into a dynamic GBWT.
* A variant of [BWT-merge](https://github.com/jltsiren/bwt-merge) for merging multiple indexes.
* An algorithm for quickly merging multiple indexes when the node identifiers do not overlap.

## Compiling GBWT

The implementation is based on [Succinct Data Structure Library 2.0](https://github.com/simongog/sdsl-lite) (SDSL). As the implementation uses C++11, OpenMP, and libstdc++ parallel mode, you need g++ 4.9 or newer to compile. On Apple systems, GBWT can also be built with Apple Clang 9.1, but libomp must be installed via Macports or Homebrew, and the lack of libstdc++'s parallel mode extensions will result in slower index construction.

Before compiling, set `SDSL_DIR` in the Makefile to point to your SDSL directory (the default is `../sdsl-lite`). To compile, simply run `make`. Use `install.sh` to compile GBWT and install the headers and library to your home directory, or `install.sh prefix` to specify another install prefix.

GBWT is compiled with `-DNDEBUG` by default. Using this option is highly recommended. There are several cases, where SDSL code works correctly but the assertions are incorrect. As SDSL 2.0 is no longer actively supported, we have to wait until the release of SDSL 3.0 to fix these issues.

## Citing GBWT

Jouni Sirén, Erik Garrison, Adam M. Novak, Benedict Paten, and Richard Durbin: **Haplotype-aware graph indexes**.
Bioinformatics 36(2):400-407, 2020.
DOI: [10.1093/bioinformatics/btz575](https://doi.org/10.1093/bioinformatics/btz575)

## Other references

Richard Durbin: **Efficient haplotype matching and storage using the Positional Burrows-Wheeler Transform (PBWT)**.
Bioinformatics 30(9):1266-1272, 2014.
DOI: [10.1093/bioinformatics/btu014](https://doi.org/10.1093/bioinformatics/btu014)

Adam M. Novak, Erik Garrison, and Benedict Paten: **A graph extension of the positional Burrows-Wheeler transform and its applications**.
Algorithms for Molecular Biology 12:18, 2017.
DOI: [10.1186/s13015-017-0109-9](https://doi.org/10.1186/s13015-017-0109-9)
