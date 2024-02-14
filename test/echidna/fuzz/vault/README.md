## Running the Crytic/ToB ERC4626 properties

Based on: https://github.com/crytic/properties?tab=readme-ov-file#erc4626-tests

```
echidna test/echidna/fuzz/vault/CryticProperties.sol --contract CryticERC4626Harness --config echidna.yaml --test-mode assertion --sender "0x10000" --deployer "0x10000"
```

## AutoPool Interactions and Externals

Mimics interactions and environmental changes that would influence the AutoPool. Safety checks around nav/share changes are disabled as we are checking to see if its possible. Possible interactions:

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
echidna test/echidna/fuzz/vault/LMPVaultTests.sol --contract LMPVaultTest --config test/echidna/fuzz/vault/echidna.yaml
```
