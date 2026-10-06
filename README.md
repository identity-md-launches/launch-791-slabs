# Slabs (SLABS)

Slabs is an immutable ERC-20 with no transfer fee. Its constructor mints the entire
supply to `msg.sender`, the immediate deployer. If a factory deploys it, the factory
receives everything; the account calling the factory receives nothing automatically.

| Deployment parameter | Value |
| --- | --- |
| Contract | `src/Slabs.sol:Slabs` |
| Name / symbol | `Slabs` / `SLABS` |
| Decimals | `18` |
| Human supply | `1,000,000,000 SLABS` |
| Supply in minor units | `1000000000000000000000000000` (`10^27`) |
| Constructor arguments | None (`[]`; encoded as `0x`) |
| Native value at construction | `0` |
| Solidity | `0.8.26` |
| EVM target | `paris` |
| Optimizer | Enabled, 200 runs |
| Metadata bytecode hash | `none` |
| Application contracts | None |

## Behavior and assumptions

The contract inherits the vendored OpenZeppelin ERC-20 implementation and adds only
the constructor mint and an `INITIAL_SUPPLY` constant. There is no owner, later mint,
external burn, fee, pause, blacklist, seizure, proxy, initialization, or upgrade
mechanism. Supply remains exactly `10^27`. Transfers make no external calls and need
no address exemptions, oracles, timing assumptions, or chain-specific configuration.

Successful `transfer`, `approve`, and `transferFrom` calls return `true`; invalid
operations revert with ERC-20 custom errors. Transfers emit `Transfer`; construction
emits one `Transfer` from the zero address. Approvals emit `Approval`. Finite
allowances decrease on spending; a maximum `uint256` allowance is unlimited and does
not decrease. Spending an allowance does not emit another `Approval` in this version,
so integrations should read `allowance` for its current value.

Zero-value transfers between valid addresses succeed and emit an event. Self
transfers preserve balances. Transfers to the zero address and approvals for the
zero spender revert. `transferFrom` requires allowance even if the spender is also
the holder or original deployer. Ordinary accounts, factories, distributors, and
pool managers all receive exactly the requested transfer amount.

## Build and verify

Foundry and Solidity 0.8.26 must be installed in the verification environment.
All Solidity dependencies and their licenses are included as ordinary files in
`lib/`; no dependency downloads, submodules, environment variables, fork, RPC, or
wallet are needed to run the tests. FFI and filesystem cheatcode permissions are
disabled.

```sh
forge build
forge test
forge fmt --check
```

Tests cover metadata, constructor events, factory CREATE2 deployment, exact launch
token movements, transfers and approvals, zero and maximum values, finite and
unlimited allowances, failure rollback, unauthorized spending, absent administrative
entry points, and forbidden runtime opcodes. Three fuzz tests run 512 cases each.
A stateful invariant checks exact balance changes and total supply across 128
sequences of 64 transfer, approval, and delegated-transfer actions. Each test starts
with a fresh token and is independent of test order and environment.

The launch movement test uses example allocations solely to exercise transfers; it
does not set actual pool economics or execute Uniswap swaps. The supplied protected
launch suite needs network-owned factory/liquidity helpers and launch parameters
that are not part of this token repository. Its complete pool initialization and
swap checks remain the launch verifier's responsibility.

## Deployment and operation

Deploy the compiled creation bytecode with no constructor arguments and no native
value, using the intended EOA or launch factory. Both CREATE and CREATE2 are supported;
CREATE2 also requires the launch operator's factory address and salt. Those inputs,
the target chain, recipient, pool configuration, and launch economics were not given
in this assignment and are not invented here. There is no post-deployment setup.
No transactions are broadcast by this project.

For an IdentityMD custom-token launch, the separate launch manifest should identify
`src/Slabs.sol:Slabs`, the metadata and exact minor-unit supply above, empty constructor
arguments, and no application contracts. Distribution, contributor shares, liquidity
seeding, and forwarding the remainder belong to the launch factory; the token does
not duplicate those operations or embed recipients. The launch operator must provide
and verify those external parameters and execute the protected integration checks.

Before release, the operator must verify chain compatibility with the Paris EVM
target, reproduce the pinned build, verify deployed source/bytecode and metadata,
and confirm that the immediate deployer received the full supply. The project uses
standard Solidity EVM bytecode; a target requiring a different compiler such as
zkSync Era needs separate work. There are no admin keys to hand over and no token
maintenance transactions. Holders and approved spenders control transfers; holders
are responsible for approval limits and revocation. Changing a nonzero allowance
can race with spending, so clients should use a confirmed zero reset when replacing
an existing approval.

No recovery function exists: tokens sent to the token contract itself, or to another
contract that cannot transfer them, may be permanently inaccessible. Deployment
operators remain responsible for custody and distribution of the initial supply.
Foundry unit, fuzz, and invariant tests are local verification, not a security audit;
an independent adversarial review remains a release responsibility. Slither and
Mythril have not been run.

Dependency versions, source provenance, licenses, and integrity instructions are
recorded in [DEPENDENCIES.md](DEPENDENCIES.md).
