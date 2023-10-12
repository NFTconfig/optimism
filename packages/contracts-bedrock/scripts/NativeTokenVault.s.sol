// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import { Script } from "forge-std/Script.sol";

import { console2 as console } from "forge-std/console2.sol";
import { stdJson } from "forge-std/StdJson.sol";

import { Deployer } from "./Deployer.sol";
import { DeployConfig } from "./DeployConfig.s.sol";
import { OptimismPortal } from "src/L1/OptimismPortal.sol";

import { ZkBridgeNativeTokenVault } from "src/universal/ZkBridgeNativeTokenVault.sol";
import { ProxyAdmin } from "@openzeppelin/contracts/proxy/transparent/ProxyAdmin.sol";
import { TransparentUpgradeableProxy } from "@openzeppelin/contracts/proxy/transparent/TransparentUpgradeableProxy.sol";

/// @title Deploy
/// @notice Script used to deploy a bedrock system. The entire system is deployed within the `run` function.
///         To add a new contract to the system, add a public function that deploys that individual contract.
///         Then add a call to that function inside of `run`. Be sure to call the `save` function after each
///         deployment so that hardhat-deploy style artifacts can be generated using a call to `sync()`.
contract NativeTokenVaultScipt is Deployer {
    DeployConfig cfg;

    /// @notice Modifier that wraps a function in broadcasting.
    modifier broadcast() {
        vm.startBroadcast();
        _;
        vm.stopBroadcast();
    }

    function setUp() public override {
        super.setUp();

        string memory path = string.concat(vm.projectRoot(), "/deploy-config/", deploymentContext, ".json");
        cfg = new DeployConfig(path);
    }

    function name() public pure override returns (string memory name_) {
        name_ = "NativeTokenVault";
    }

    function deployProxyAdmin() public returns (address) {
        vm.broadcast();
        ProxyAdmin admin = new ProxyAdmin();

        transferProxyAdminOwnership(address(admin));

        // save("ZkProxyAdmin", address(admin));
        console.log("ProxyAdmin deployed at %s", address(admin));
        return address(admin);
    }

    function deployZkBridgeNativeTokenVault(
        address proxyAdmin_,
        address[] memory optimismPortalProxys_
    )
        public
        broadcast
        returns (address)
    {
        console.log("finalSystemOwner", cfg.finalSystemOwner());
        ZkBridgeNativeTokenVault impl = new ZkBridgeNativeTokenVault();

        bytes memory payload = abi.encodeWithSignature("initialize(address)", cfg.finalSystemOwner());

        TransparentUpgradeableProxy proxy = new TransparentUpgradeableProxy(
            address(impl),
            proxyAdmin_,
            payload
        );

        ZkBridgeNativeTokenVault vault = ZkBridgeNativeTokenVault(payable(address(proxy)));

        // save("ZkBridgeNativeTokenVault", address(vault));

        for (uint256 i = 0; i < optimismPortalProxys_.length; i++) {
            address optimismPortalProxy = optimismPortalProxys_[i];
            if (!vault.managements(optimismPortalProxy)) {
                vault.setManager(optimismPortalProxy, true);
            }
            require(vault.managements(optimismPortalProxy) == true);
        }

        require(vault.governor() == cfg.finalSystemOwner());

        console.log("ZkBridgeNativeTokenVault deployed at %s", address(vault));

        return address(vault);
    }

    function zkBridgeNativeTokenVaultUpgrade(
        address addmin_,
        address payable nativeTokenVaultProxy_
    )
        public
        broadcast
    {
        ProxyAdmin admin = ProxyAdmin(addmin_);
        ZkBridgeNativeTokenVault impl = new ZkBridgeNativeTokenVault();
        admin.upgrade(TransparentUpgradeableProxy(nativeTokenVaultProxy_), address(impl));
    }

    function transferProxyAdminOwnership(address proxyAdmin_) public broadcast {
        ProxyAdmin proxyAdmin = ProxyAdmin(proxyAdmin_);
        address owner = proxyAdmin.owner();
        address finalSystemOwner = cfg.finalSystemOwner();
        if (owner != finalSystemOwner) {
            proxyAdmin.transferOwnership(finalSystemOwner);
            console.log("ProxyAdmin ownership transferred to: %s", finalSystemOwner);
        }
    }
}
