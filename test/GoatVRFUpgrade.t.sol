// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {Test, console2} from "forge-std/Test.sol";
import {GoatVRF} from "../src/GoatVRF.sol";
import {GoatVRFV2UpgradeTest} from "../src/mocks/GoatVRFV2UpgradeTest.sol";
import {IGoatVRF} from "../src/interfaces/IGoatVRF.sol";
import {IFeeRule} from "../src/interfaces/IFeeRule.sol";
import {IDrandBeacon} from "../src/interfaces/IDrandBeacon.sol";
import {MockDrandBeacon, MockFeeRule, MockWGOATBTC, MockCallback} from "./GoatVRF.t.sol";
import {Upgrades} from "openzeppelin-foundry-upgrades/Upgrades.sol";
import {Options} from "openzeppelin-foundry-upgrades/Options.sol";

/**
 * @title GoatVRFUpgradeTest
 * @dev Test contract for verifying UUPS upgrade functionality of GoatVRF
 */
contract GoatVRFUpgradeTest is Test {
    GoatVRF public goatVRFProxy;
    address public proxyAddress;

    MockDrandBeacon public mockBeacon;
    MockWGOATBTC public token;
    MockFeeRule public feeRule;

    address public owner = address(1);
    address public relayer = address(2);
    address public feeRecipient = address(3);
    address public user = address(4);
    address public unauthorized = address(5);

    uint256 public constant FIXED_FEE = 1 ether;
    uint256 public constant OVERHEAD_GAS = 50000;
    uint256 public constant MAX_DEADLINE_DELTA = 7 days;
    uint256 public constant REQUEST_EXPIRE_TIME = 7 days;

    // Implementation slot from ERC1967
    bytes32 internal constant _IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    event Upgraded(address indexed implementation);

    function setUp() public {
        vm.startPrank(owner);

        // Deploy mock contracts
        mockBeacon = new MockDrandBeacon();
        token = new MockWGOATBTC();
        feeRule = new MockFeeRule(FIXED_FEE);

        // Create Options struct and specify allowed validations to skip
        Options memory opts;
        opts.unsafeAllow = "state-variable-immutable";

        // Deploy UUPS proxy using OpenZeppelin Upgrades library
        proxyAddress = Upgrades.deployUUPSProxy(
            "GoatVRF.sol:GoatVRF",
            abi.encodeWithSelector(
                GoatVRF.initialize.selector,
                address(mockBeacon),
                address(token),
                feeRecipient,
                relayer,
                address(feeRule),
                MAX_DEADLINE_DELTA,
                OVERHEAD_GAS,
                REQUEST_EXPIRE_TIME
            ),
            opts
        );

        // Access GoatVRF functionality through proxy
        goatVRFProxy = GoatVRF(proxyAddress);

        vm.stopPrank();
    }

    // Test successful upgrade with OZ Foundry Upgrades library
    function testUpgradeWithOZFoundryUpgrades() public {
        vm.startPrank(owner);

        // Create Options struct and specify allowed validations to skip
        Options memory opts;
        opts.unsafeAllow = "state-variable-immutable";
        opts.referenceContract = "GoatVRF.sol:GoatVRF";

        // Create a request
        uint256 deadline = block.timestamp + 1 days;
        uint256 maxGasPrice = 100 gwei;
        uint256 callbackGas = 200000;

        // Fund user for request
        vm.stopPrank();
        vm.startPrank(user);
        token.mint(user, 10 ether);
        token.approve(proxyAddress, 10 ether);

        // Make request
        uint256 requestId = goatVRFProxy.getNewRandom(deadline, maxGasPrice, callbackGas);
        vm.stopPrank();

        // Verify request state
        assertEq(uint256(goatVRFProxy.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Pending));

        // Upgrade using Foundry Upgrades library
        vm.startPrank(owner);

        // Use correct contract path for upgrade with same options
        Upgrades.upgradeProxy(
            proxyAddress,
            "GoatVRFV2UpgradeTest.sol:GoatVRFV2UpgradeTest",
            abi.encodeWithSelector(GoatVRFV2UpgradeTest.initialize.selector, "2.0.0"),
            opts
        );
        vm.stopPrank();

        // Test upgraded contract
        GoatVRFV2UpgradeTest upgradedContract = GoatVRFV2UpgradeTest(proxyAddress);

        // Verify state preserved
        assertEq(uint256(upgradedContract.getRequestState(requestId)), uint256(IGoatVRF.RequestState.Pending));
        assertEq(upgradedContract.feeRecipient(), feeRecipient);
        assertEq(upgradedContract.relayer(), relayer);

        // Verify new functionality
        assertEq(upgradedContract.getVersion(), "2.0.0");
    }

    // Test failed upgrade when non-owner tries to upgrade
    function testUpgradeFailsForNonOwner() public {
        // First deploy the implementation contract with owner account
        vm.startPrank(owner);
        Options memory opts;
        opts.unsafeAllow = "state-variable-immutable";
        opts.referenceContract = "GoatVRF.sol:GoatVRF";

        // Prepare the upgrade - This step deploys the implementation without upgrading
        address v2Implementation = Upgrades.prepareUpgrade("GoatVRFV2UpgradeTest.sol:GoatVRFV2UpgradeTest", opts);
        vm.stopPrank();

        // Now try to upgrade with unauthorized account
        vm.startPrank(unauthorized);

        // Create the data for initialization
        bytes memory data = abi.encodeWithSelector(GoatVRFV2UpgradeTest.initialize.selector, "2.0.0");

        // Expect revert when unauthorized user tries to upgrade
        vm.expectRevert(abi.encodeWithSignature("OwnableUnauthorizedAccount(address)", unauthorized));

        // Try to directly call upgradeToAndCall on the proxy
        // This is UUPSUpgradeable's method that will fail for non-owners
        GoatVRF(proxyAddress).upgradeToAndCall(v2Implementation, data);

        vm.stopPrank();
    }
}
