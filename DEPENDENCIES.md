# Vendored dependencies

These files are shipped directly in `lib/`. They are not submodules and need no
installation step or network access during compilation. Upstream source files are
unmodified.

| Dependency | Release | Exact upstream commit | Included scope |
| --- | --- | --- | --- |
| [OpenZeppelin Contracts](https://github.com/OpenZeppelin/openzeppelin-contracts/tree/dbb6104ce834628e473d2173bbc9d47f81a9eec3) | v5.0.2 | `dbb6104ce834628e473d2173bbc9d47f81a9eec3` | ERC20 and its four Solidity imports, MIT license |
| [forge-std](https://github.com/foundry-rs/forge-std/tree/77041d2ce690e692d6e03cc812b57d1ddaa4d505) | v1.9.7 | `77041d2ce690e692d6e03cc812b57d1ddaa4d505` | `src/`, MIT and Apache-2.0 licenses; used only by tests |

OpenZeppelin's license is at `lib/openzeppelin-contracts/LICENSE`. forge-std's
licenses are at `lib/forge-std/LICENSE-MIT` and `lib/forge-std/LICENSE-APACHE`.
`DEPENDENCIES.sha256` records every vendored file's SHA-256 digest. Verify from the
repository root with:

```sh
sha256sum --check DEPENDENCIES.sha256
```

Dependency updates require an explicit version change, review of the source and
behavior differences, regeneration of checksums, and rerunning the complete test
suite. The compiler binary and Foundry executable are tooling supplied by the build
environment and are not vendored here.
