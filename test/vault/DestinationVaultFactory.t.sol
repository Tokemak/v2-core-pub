// SPDX-License-Identifier: UNLICENSED
// Copyright (c) 2023 Tokemak Foundation. All rights reserved.
pragma solidity >=0.8.7;

/* solhint-disable func-name-mixedcase */

import { Roles } from "src/libs/Roles.sol";
import { Errors } from "src/utils/Errors.sol";
import { SystemRegistry } from "src/SystemRegistry.sol";
import { ISystemComponent } from "src/interfaces/ISystemComponent.sol";
import { Test, StdCheats, StdUtils } from "forge-std/Test.sol";
import { Clones } from "openzeppelin-contracts/proxy/Clones.sol";
import { DestinationVault } from "src/vault/DestinationVault.sol";
import { ISystemRegistry } from "src/interfaces/ISystemRegistry.sol";
import { IMainRewarder } from "src/interfaces/rewarders/IMainRewarder.sol";
import { IStakeTracking } from "src/interfaces/rewarders/IStakeTracking.sol";
import { IDestinationVault } from "src/interfaces/vault/IDestinationVault.sol";
import { DestinationVaultFactory } from "src/vault/DestinationVaultFactory.sol";
import { IAccessController, AccessController } from "src/security/AccessController.sol";
import { IDestinationRegistry } from "src/interfaces/destinations/IDestinationRegistry.sol";
import { IDestinationVaultRegistry } from "src/interfaces/vault/IDestinationVaultRegistry.sol";
import { IERC20Metadata as IERC20 } from "openzeppelin-contracts/token/ERC20/extensions/IERC20Metadata.sol";
import { TOKE_MAINNET, WETH_MAINNET } from "test/utils/Addresses.sol";
import { TestIncentiveCalculator } from "test/mocks/TestIncentiveCalculator.sol";

contract DestinationVaultFactoryBaseTests is Test {
    address private _testUser1;
    address private _templateRegistry;
    address private _vaultRegistry;

    SystemRegistry private _systemRegistry;
    IAccessController private _accessController;
    DestinationVaultFactory private _factory;

    address private _fakeUnderlyer;
    address[] private _fakeTracked;
    TestIncentiveCalculator private _fakeIncentiveCalculator;

    event Initialized(ISystemRegistry registry, bytes params);

    function setUp() public {
        _testUser1 = vm.addr(1);

        _systemRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        _templateRegistry = _generateTemplateRegistry(_systemRegistry);
        _vaultRegistry = _generateVaultRegistry(_systemRegistry);
        _accessController = new AccessController(address(_systemRegistry));
        _systemRegistry.setAccessController(address(_accessController));
        _systemRegistry.setDestinationTemplateRegistry(_templateRegistry);
        _systemRegistry.setDestinationVaultRegistry(_vaultRegistry);

        _factory = new DestinationVaultFactory(_systemRegistry, 1, 1000);

        _fakeUnderlyer = vm.addr(10);
        _fakeTracked = new address[](0);

        _fakeIncentiveCalculator = new TestIncentiveCalculator(_fakeUnderlyer);

        _systemRegistry.addRewardToken(address(8));
    }

    function testRequiresValidRegistry() public {
        vm.expectRevert();
        new DestinationVaultFactory(ISystemRegistry(address(0)), 1, 1000);

        SystemRegistry incompleteRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        vm.expectRevert();
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);
    }

    function testRequiresTemplateRegistryOnSetup() public {
        SystemRegistry incompleteRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController access = new AccessController(address(incompleteRegistry));
        incompleteRegistry.setAccessController(address(access));

        // Try with nothing
        vm.expectRevert();
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);

        // Try with the vault, still missing template
        incompleteRegistry.setDestinationVaultRegistry(_generateVaultRegistry(incompleteRegistry));
        vm.expectRevert();
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);

        // Should have everything now
        incompleteRegistry.setDestinationTemplateRegistry(_generateTemplateRegistry(incompleteRegistry));
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);
    }

    function testRequiresVaultRegistryOnSetup() public {
        SystemRegistry incompleteRegistry = new SystemRegistry(TOKE_MAINNET, WETH_MAINNET);
        AccessController access = new AccessController(address(incompleteRegistry));
        incompleteRegistry.setAccessController(address(access));

        // Try with nothing
        vm.expectRevert();
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);

        // Try with template still missing the vault
        incompleteRegistry.setDestinationTemplateRegistry(_generateTemplateRegistry(incompleteRegistry));
        vm.expectRevert();
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);

        // Should have everything now
        incompleteRegistry.setDestinationVaultRegistry(_generateVaultRegistry(incompleteRegistry));
        new DestinationVaultFactory(incompleteRegistry, 1, 1000);
    }

    function testOnlyVaultCreatorCanCallCreate() public {
        vm.expectRevert(
            abi.encodeWithSelector(Errors.MissingRole.selector, Roles.CREATE_DESTINATION_VAULT_ROLE, address(this))
        );
        _factory.create(
            "x",
            address(8),
            _fakeUnderlyer,
            address(_fakeIncentiveCalculator),
            _fakeTracked,
            keccak256("abc"),
            abi.encode("")
        );

        bytes32 key = keccak256(abi.encode("x"));
        address template = vm.addr(6);
        _registerTemplate(_templateRegistry, key, template);
        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));
        _factory.create(
            "x",
            address(8),
            _fakeUnderlyer,
            address(_fakeIncentiveCalculator),
            _fakeTracked,
            keccak256("abc"),
            abi.encode("")
        );
    }

    function testVaultTypeMustBeRegistered() public {
        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        // Fails when it gets address(0)
        bytes32 badKey = keccak256(abi.encode("y"));
        _registerTemplate(_templateRegistry, badKey, address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "template"));
        _factory.create(
            "y",
            address(8),
            _fakeUnderlyer,
            address(_fakeIncentiveCalculator),
            _fakeTracked,
            keccak256("abc"),
            abi.encode("")
        );

        // Succeeds when a template is registered
        _registerTemplate(_templateRegistry, badKey, address(1));
        _factory.create(
            "y",
            address(8),
            _fakeUnderlyer,
            address(_fakeIncentiveCalculator),
            _fakeTracked,
            keccak256("abc"),
            abi.encode("")
        );
    }

    function testCallsInitializeWithProvidedParams() public {
        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        // Fails when it gets address(0)
        bytes32 badKey = keccak256(abi.encode("y"));
        _registerTemplate(_templateRegistry, badKey, address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "template"));
        _factory.create(
            "y",
            address(8),
            _fakeUnderlyer,
            address(_fakeIncentiveCalculator),
            _fakeTracked,
            keccak256("abc"),
            abi.encode("")
        );

        // Succeeds when a template is registered
        TestVault tv = new TestVault(_systemRegistry);
        _registerTemplate(_templateRegistry, badKey, address(tv));
        bytes memory data = abi.encode("h");

        vm.expectEmit(true, true, true, true);
        emit Initialized(_systemRegistry, data);
        _factory.create(
            "y", address(8), _fakeUnderlyer, address(_fakeIncentiveCalculator), _fakeTracked, keccak256("abc"), data
        );
    }

    function testAddsToRegistry() public {
        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));

        bytes32 badKey = keccak256(abi.encode("y"));
        bytes32 salt = keccak256("abc");
        _registerTemplate(_templateRegistry, badKey, address(0));
        vm.expectRevert(abi.encodeWithSelector(Errors.ZeroAddress.selector, "template"));
        _factory.create(
            "y", address(8), _fakeUnderlyer, address(_fakeIncentiveCalculator), _fakeTracked, salt, abi.encode("")
        );

        TestVault tv = new TestVault(_systemRegistry);
        _registerTemplate(_templateRegistry, badKey, address(tv));
        bytes memory data = abi.encode("h");

        address nextAddress = Clones.predictDeterministicAddress(address(tv), salt, address(_factory));
        vm.expectCall(_vaultRegistry, abi.encodeCall(IDestinationVaultRegistry.register, nextAddress));
        _factory.create("y", address(8), _fakeUnderlyer, address(_fakeIncentiveCalculator), _fakeTracked, salt, data);
    }

    function testRewarderEndsUpWithCorrectStakeToken() public {
        _accessController.grantRole(Roles.CREATE_DESTINATION_VAULT_ROLE, address(this));
        bytes32 salt = keccak256("abc");
        bytes32 key = keccak256(abi.encode("y"));
        TestVault tv = new TestVault(_systemRegistry);
        _registerTemplate(_templateRegistry, key, address(tv));
        bytes memory data = abi.encode("h");

        address nextAddress = Clones.predictDeterministicAddress(address(tv), salt, address(_factory));
        vm.expectCall(_vaultRegistry, abi.encodeCall(IDestinationVaultRegistry.register, nextAddress));
        address newVault = _factory.create(
            "y", address(8), address(_fakeIncentiveCalculator), _fakeUnderlyer, _fakeTracked, salt, data
        );
    }

    function _registerTemplate(address templateReg, bytes32 key, address template) internal {
        vm.mockCall(
            templateReg, abi.encodeWithSelector(IDestinationRegistry.getAdapter.selector, key), abi.encode(template)
        );
    }

    function _generateTemplateRegistry(ISystemRegistry sysRegistry) internal returns (address) {
        address reg = vm.addr(1001);
        vm.mockCall(reg, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(sysRegistry));
        return reg;
    }

    function _generateVaultRegistry(ISystemRegistry sysRegistry) internal returns (address) {
        address reg = vm.addr(1002);
        vm.mockCall(reg, abi.encodeWithSelector(ISystemComponent.getSystemRegistry.selector), abi.encode(sysRegistry));
        return reg;
    }
}

contract TestVault {
    ISystemRegistry public immutable _systemRegistry;

    event Initialized(ISystemRegistry registry, bytes params);

    address public rewarder;

    constructor(ISystemRegistry _systemRegistry_) {
        _systemRegistry = _systemRegistry_;
    }

    function initialize(
        IERC20,
        IERC20,
        IMainRewarder _rewarder,
        address,
        address[] memory,
        bytes memory params
    ) external {
        emit Initialized(_systemRegistry, params);

        rewarder = address(_rewarder);
    }
}
