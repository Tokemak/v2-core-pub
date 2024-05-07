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
 foundryup --version nightly-de33b6af53005037b463318d2628b5cfcaf39916
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

## Running Tests

Basic unit tests, integrations tests, and Foundry based fuzz tests with a low default run count can be execute via:

```
forge test
```

ERC4626 prop fuzz tests from a16z can be executed against the Autopool with:

```
forge test --match-path test/fuzz/vault/Autopool.t.sol --fuzz-runs 10000
```
