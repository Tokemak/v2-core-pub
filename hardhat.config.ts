import * as dotenv from "dotenv";

import { HardhatUserConfig, task } from "hardhat/config";

import "@nomiclabs/hardhat-ethers";
import "@nomicfoundation/hardhat-toolbox";
import "@nomicfoundation/hardhat-foundry";

dotenv.config();

const config: HardhatUserConfig = {
	solidity: "0.8.17",
};

async function destination(systemRegistry, hre, provider) {
	const registryArtifact = await hre.artifacts.readArtifact("DestinationVaultRegistry");
	const factoryArtifact = await hre.artifacts.readArtifact("DestinationVaultFactory");
	const destinationVaultArtifact = await hre.artifacts.readArtifact("IDestinationVault");

	const registry = new hre.ethers.Contract(
		await systemRegistry.destinationVaultRegistry(),
		registryArtifact.abi,
		provider,
	);

	const destinationTemplateRegistry = await systemRegistry.destinationTemplateRegistry();

	console.log(`Destination Vault Registry: ${registry.address}`);
	console.log(`Destination Template Registry: ${destinationTemplateRegistry}`);

	if (registry.address !== "0x0000000000000000000000000000000000000000") {
		const destinationVaultFactory = new hre.ethers.Contract(
			await registry.factory(),
			factoryArtifact.abi,
			provider,
		);
		const defaultRewardRatio = await destinationVaultFactory.defaultRewardRatio();
		const defaultRewardBlockDuration = await destinationVaultFactory.defaultRewardBlockDuration();
		console.log(`Destination Vault Factory: ${destinationVaultFactory.address}`);
		console.log(`- default Reward Ratio: ${defaultRewardRatio}`);
		console.log(`- default Reward Block Duration: ${defaultRewardBlockDuration}`);

		const vaults = await registry.listVaults();
		console.log("Destination Vaults:");
		for (let i = 0; i < vaults.length; i++) {
			const vaultAddress = vaults[i];
			const vault = new hre.ethers.Contract(vaultAddress, destinationVaultArtifact.abi, provider);
			const vaultName = await vault.name();
			console.log(`- ${vaultName} (${vaultAddress})`);
		}
	} else {
		console.log("Destination Vault Factory: not found.");
	}

	console.log("");
}

async function lmpVaults(systemRegistry, hre, provider) {
	const lmpVaultType = hre.ethers.utils.keccak256(hre.ethers.utils.toUtf8Bytes("lst-guarded-r1"));

	const lmpVaultArtifact = await hre.artifacts.readArtifact("ILMPVault");

	const lmpVaultRouter = await systemRegistry.lmpVaultRouter();

	const registryArtifact = await hre.artifacts.readArtifact("LMPVaultRegistry");
	const registry = new hre.ethers.Contract(await systemRegistry.lmpVaultRegistry(), registryArtifact.abi, provider);

	try {
		const factoryArtifact = await hre.artifacts.readArtifact("LMPVaultFactory");
		const factory = new hre.ethers.Contract(
			await systemRegistry.getLMPVaultFactoryByType(lmpVaultType),
			factoryArtifact.abi,
			provider,
		);
		console.log(`LMP Vault Factory: ${factory.address}`);
		console.log(`- template: ${await factory.template()}`);
	} catch (e) {
		console.log("LMP Vault Factory: not found for the lst-guarded-r1 type.");
	}

	console.log(`LMP Vault Registry: ${registry.address}`);
	console.log(`LMP Vault Router: ${lmpVaultRouter}`);

	try {
		const vaults = await registry.listVaults();
		console.log("LMP Vaults:");
		for (let i = 0; i < vaults.length; i++) {
			const vaultAddress = vaults[i];
			const vault = new hre.ethers.Contract(vaultAddress, lmpVaultArtifact.abi, provider);
			const vaultName = await vault.name();
			console.log(`- ${vaultName} (${vaultAddress})`);
		}
	} catch (e) {
		console.log("LMP Vaults: not found.");
	}

	console.log("");
	console.log("");
}

task("system", "Displays the system information")
	.addParam("rpcUrl", "The RPC URL")
	.addParam("systemRegistryAddress", "The System Registry Address")
	.setAction(async (taskArgs, hre) => {
		const rpcUrl = taskArgs.rpcUrl;

		const provider = new hre.ethers.providers.JsonRpcProvider(rpcUrl);

		const blockNumber = await provider.getBlockNumber();
		console.log(`Current Block Number: ${blockNumber}`);

		const ISystemRegistry = await hre.artifacts.readArtifact("ISystemRegistry");
		const systemRegistry = new hre.ethers.Contract(taskArgs.systemRegistryAddress, ISystemRegistry.abi, provider);

		await destination(systemRegistry, hre, provider);

		await lmpVaults(systemRegistry, hre, provider);

		const rootPriceOracle = await systemRegistry.rootPriceOracle();
		const asyncSwapperRegistry = await systemRegistry.asyncSwapperRegistry();
		const swapRouter = await systemRegistry.swapRouter();
		const curveResolver = await systemRegistry.curveResolver();
		const systemSecurity = await systemRegistry.systemSecurity();
		const statsCalculatorRegistry = await systemRegistry.statsCalculatorRegistry();
		const incentivePricingStats = await systemRegistry.incentivePricing();
		const accessController = await systemRegistry.accessController();

		console.log(`Access Controller: ${accessController}`);
		console.log(`Root Price Oracle: ${rootPriceOracle}`);
		console.log(`Async Swapper Registry: ${asyncSwapperRegistry}`);
		console.log(`Swap Router: ${swapRouter}`);
		console.log(`Curve Resolver: ${curveResolver}`);
		console.log(`System Security: ${systemSecurity}`);
		console.log(`Stats Calculator Registry: ${statsCalculatorRegistry}`);
		console.log(`Incentive Pricing Stats: ${incentivePricingStats}`);
	});

export default config;
