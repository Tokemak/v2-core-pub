# How to Deploy the System

ℹ️ To get a picture of the system at any moment, use the following hardhat task:

```shell
npx hardhat system --rpc-url <fork-url> --system-registry-address 0x0406d2D96871f798fcf54d5969F69F55F803eEA4
```



Outlined below are the necessary steps for deploying the system, using specific forge scripts.

## Register Reward Tokens

Registers WETH and TOKE as reward tokens in the Tokemak system.

```shell
forge script script/destination/RegisterRewardTokens.s.sol --rpc-url <fork-url> --broadcast --slow
```

## Destination System Setup

Deploys and registers the `DestinationRegistry`, `DestinationVaultRegistry`and `DestinationVaultFactory`.
Grants the `CREATE_DESTINATION_VAULT_ROLE` role to the deploying wallet.

```shell
forge script script/destination/DestinationSystem.s.sol --rpc-url <fork-url> --broadcast --slow
```

## Curve Destination Vault Template Deployment

Creates and registers a CurveConvexDestinationVault of type `curve-convex` within the system

```shell
forge script script/destination/curve/CurveDestinationVaultTemplate.s.sol --rpc-url <fork-url> --broadcast --slow
```

## Destination Vault for Curve Deployment

Deploys specific Curve Destination Vaults for different Curve pools

Curve StEthEth Original:

```shell
forge script script/destination/curve/CurveStEthEthOriginal.s.sol --rpc-url <fork-url> --broadcast --slow
```

Curve StEthEth Concentrated:

```shell
forge script script/destination/curve/CurveStEthEthConcentrated.s.sol --rpc-url <fork-url> --broadcast --slow
```

Curve StEthEth Ng:

```shell
forge script script/destination/curve/CurveStEthEthNg.s.sol --rpc-url <fork-url> --broadcast --slow
```

Curve RethWstEth:

```shell
forge script script/destination/curve/CurveRethWstEth.s.sol --rpc-url <fork-url> --broadcast --slow
```

Curve CbethEth:

```shell
forge script script/destination/curve/CurveCbethEth.s.sol --rpc-url <fork-url> --broadcast --slow
```

## LMP Vault System Deployment

Facilitates the setup of the LMP Vault System and the creation of a strategy tailored for the LMP Vault.

## LMP System:

Deploys and registers the `LMPVaultRegistry`, `LMPVaultFactory` with `weth-vault` type and `LMPVaultRouter`.
Grants the `REGISTRY_UPDATER` role to the new lmp factory.

```shell
forge script script/lmp/LMPSystem.s.sol --rpc-url <fork-url> --broadcast --slow
```

## Create LMP Strategy:

Deploys and registers a new LMP strategy template for type `weth-vault`.

StrategyConfig must be set in the file.

```shell
forge script script/lmp/CreateLMPStrategy.s.sol --rpc-url <fork-url> --broadcast --slow
```

# Create a LMP Vault

Creates a new LMP Vault using the `weth-vault` LMP Vault Factory and the specified strategy template.

Strategy template must be set in the file.

```shell
forge script script/lmp/CreateLMPVault.s.sol --rpc-url <fork-url> --broadcast --slow
```


# Create the Root Oracle and oracles

Creates a new RootOracle with a bunch of oracles

```shell
forge script script/oracle/SetUpOracles.s.sol --rpc-url <fork-url> --broadcast --slow
```
