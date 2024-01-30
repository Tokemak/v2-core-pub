# Tokemak Autopilot

[![Github Actions][gha-badge]][gha] [![Foundry][foundry-badge]][foundry] [![semantic-release: conventional commits][commits-badge]][commits] [![protected by: gitleaks][gitleaks-badge]][gitleaks] [![License: MIT][license-badge]][license]

[gha]: https://github.com/codenutt/foundry-template/actions
[gha-badge]: https://github.com/codenutt/foundry-template/actions/workflows/ci.yml/badge.svg
[foundry]: https://getfoundry.sh/
[foundry-badge]: https://img.shields.io/badge/Built%20with-Foundry-FFDB1C.svg
[commits]: https://github.com/semantic-release/semantic-release
[commits-badge]: https://img.shields.io/badge/semantic--release-conventialcommits-e10079?logo=semantic-release
[license]: https://opensource.org/licenses/MIT
[license-badge]: https://img.shields.io/badge/License-MIT-blue.svg
[gitleaks-badge]: https://img.shields.io/badge/protected%20by-gitleaks-blue
[gitleaks]: https://gitleaks.io/

Contracts for the Tokemak Autopilot System
Details on the system can be found [here](https://medium.com/tokemak/tokemak-v2-introducing-lmps-autopilot-and-the-dao-liquidity-marketplace-86b8ec0656a).

## Getting Started

Install the same version of foundry that the CI will use. Ensures formatting stays consistent

```
 foundryup --version nightly-293fad73670b7b59ca901c7f2105bf7a29165a90
```

From there:

```
npm install
```

Additional setup info:

-   If you are going to be making commits, you will want to install Gitleaks locally. For details: https://github.com/zricethezav/gitleaks#installing.
-   This repo also enforces [Conventional Commits](https://www.conventionalcommits.org/). Locally, this is enforced via Husky. GitHub CI is setup to enforce it there as well.
    If a commit does not follow the guidelines, the build/PR will be rejected.
-   Formatting for Solidity files is provided via `forge`. Other files are formatted via `prettier`. Linting is provided by `solhint` and `eslint`.
-   Semantic versioning drives tag and release information when commits are pushed to main. Your commit will automatically tagged with the version number,
    and a release will be created in GitHub with the change log.
-   Slither will run automatically in CI. To run the `scan:slither` command locally you'll need to ensure you have Slither installed: https://github.com/crytic/slither#how-to-install. If slither reports any issue, your PR will not pass.

## Glossary

Some common terms that are used in our documentation:

-   `Autopilot Vault` - Or, LMP Vault. This the contract that will initially hold users funds before they are deployed.
-   `Destination Vault` - A Vault that sits in from of any DEX pool, or other location, we plan to deploy assets to
-   `Base Asset` - The asset the entire system is based on. For an Autopilot Vault this is the asset users deposit. For the Destination Vault, it is the one that the destination is related to. All Vaults, Autopilot or Destination, must have matching Base Assets to be used together. For our initial launch, this is WETH.
-   `Strategy` - A set of logic, signals, and calculations that govern the deployment of assets. An Autopilot Vault has a 'type'. For initial launch, that type is 'LST' for Liquid Staking Tokens. The accompanying strategy on the Autopilot Vault is one that understands the risks, behaviors, and how to value that particular asset class.
-   `Rewarder` - A block-height + rate reward contract much like that of Synthetix / Convex.

## System Overview

There are many pieces to the system, but they can largely be broken down and thought of as smaller subsystems. We will try to break them down here, explore them piece by piece, and look at the system from the view of various actors.

### End-Users View

A user will largely only interact with the Router directly (the exception being rewards+staking) The Router includes safety and convenience methods for interacting with the ERC4626 compatible Autopilot Vaults. From a safety perspective, this includes slippage-based variants of `deposit/mint/redeem/withdraw()`, and for migrating between vaults, `redeemToDeposit()`.

<p align="center">
    <img style="border: 10px solid white" alt="basic user flow" src="./docs/images/root-user-view-1.svg">
</p>

The only time a user should be interacting with the vault directly is when claiming rewards. Each Autopilot Vault has a Rewarder paired to it. The main reward token for every Autopilot Rewarder is TOKE. We expect that additional reward tokens will be added later. A user can claim directly from the Rewarder or through the Autopilot Vault itself

<p align="center">
    <img style="border: 10px solid white" alt="basic user flow" src="./docs/images/root-user-view-2.svg">
</p>

Upon claiming from the Rewarder, regardless of how, the path those reward tokens take depend on what they are. If the rewarder token is TOKE, then it is goes into accToke to be unlocked at a later point. Any other reward token is sent directly to the user. Once the lock is up, the user may go to the accToke contract and pick up their tokens.

<p align="center">
    <img style="border: 10px solid white" alt="basic user flow" src="./docs/images/root-user-view-3.svg">
</p>

### System View

The entire system revolves around a single contract, the `SystemRegistry`. This is the contract that ties all other contracts together and from this contract we should be able to enumerate every other contract in the system. A registry of registries almost. It is our plan that there will be multiple "Systems" running concurrently on the same chain. One for ETH based assets, LSTs and such. Another for USD stable-coins. Etc. Given the configuration complexity of these contracts, having a central reference that two contracts must agree upon will save in accidental mis-configurations down the line.

The System Registry can be thought of holding two types of references: supporting contracts, sub-system entry points:

<p align="center">
    <img style="border: 10px solid white" alt="basic user flow" src="./docs/images/root-system-view-1.svg">
</p>

For a new contract to be configured in the system, it only needs to be given a reference to the SystemRegistry. The subsystem entry points would be

-   RootPriceOracle - `src/oracles/RootPriceOracle.sol`
-   SwapRouter - `src/swapper/SwapRouter.sol`
-   Reward Liquidations - `src/liquidation/AsyncSwapperRegistry.sol`
-   Stats - `src/stats/StatsCalculatorRegistry.sol`
-   Vaults - `src/vault/*`

Readmes should be available in the folders of those areas
