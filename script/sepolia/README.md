## Commands

Deploy TOKE

```
forge script script/sepolia/01_InitToke.s.sol --rpc-url sepolia --sender $SENDER_SEPOLIA --tc InitToke --broadcast --verify --slow --account v2-sepolia
```

Add TOKE address to the constants tokens for the chain

```
forge script script/sepolia/02_SystemDeploy.s.sol --rpc-url sepolia --sender $SENDER_SEPOLIA --broadcast --verify --slow --account v2-sepolia
```

```
forge script script/sepolia/03_PoolAndStrategy.s.sol --rpc-url sepolia --sender $SENDER_SEPOLIA --broadcast --verify --slow --account v2-sepolia
```
