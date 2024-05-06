## Running the Crytic/ToB ERC4626 properties

Based on: https://github.com/crytic/properties?tab=readme-ov-file#erc4626-tests

```
echidna test/echidna/fuzz/vault/CryticProperties.sol --contract CryticERC4626Harness --config test/echidna/fuzz/vault/echidna.yaml --test-mode assertion --sender "0x10000" --deployer "0x10000"
```

## Autopool Interactions and Externals

Mimics interactions and environmental changes that would influence the Autopool. Safety checks around nav/share changes are disabled as we are checking to see if its possible. Possible interactions:

### Operations

#### User interactions

-   User deposit, and "deposit for"
-   User mint, and "mint for"
-   User redeem, and redeem via allowance
-   User withdraw, and withdraw via allowance
-   Known user donation
-   Random user donation
-   User transfer shares

#### Price / Slippage

-   Tweak destination vault underlyer price
-   Tweak destination vault underlyer ceiling price
-   Tweak destination vault underlying floor price
-   Tweak destination vault underlying safe price
-   Tweak destination vault underlying spot price
-   Set positive/negative slippage on destination vault underlying -> base asset swaps

#### Fees

-   Set streaming fee and sink
-   Set periodic fee and sink

#### Rewards

-   Set auto-compounded rewards for a destination

#### Pool

-   Debt reportings
-   Rebalances

### Running

```
echidna test/echidna/fuzz/vault/AutopoolETHTests.sol --contract AutopoolETHTest --config test/echidna/fuzz/vault/echidna.yaml
```

## AutopilotRouter Interactions and Externals

This set of tests verifies scenarios when user mints & owns some shares obtained via interaction with the Router and ensures that no other user is possible to obtain their shares. This is verifiable by user balance change checks.

### Running

```
echidna test/echidna/fuzz/vault/router/AutopilotRouterTests.sol --contract AutopilotRouterTest --config test/echidna/fuzz/vault/router/echidna.yaml
```
