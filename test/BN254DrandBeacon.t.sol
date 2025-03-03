// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Test.sol";
import "../src/BN254DrandBeacon.sol";

contract BN254DrandBeaconTest is Test {
    BN254DrandBeacon public beacon;

    // Test data from drand network
    bytes constant TEST_PUBLIC_KEY =
        hex"07e1d1d335df83fa98462005690372c643340060d205306a9aa8106b6bd0b3820557ec32c2ad488e4d4f6008f89a346f18492092ccc0d594610de2732c8b808f0095685ae3a85ba243747b1b2f426049010f6b73a0cf1d389351d5aaaa1047f6297d3a4f9749b33eb2d904c9d9ebf17224150ddd7abd7567a9bec6c74480ee0b";
    uint256 constant TEST_GENESIS_TIME = 1727521075;
    uint256 constant TEST_PERIOD = 3;

    function setUp() public {
        beacon = new BN254DrandBeacon(TEST_PUBLIC_KEY, TEST_GENESIS_TIME, TEST_PERIOD);
    }

    function testInitialization() public view {
        assertEq(beacon.genesisTimestamp(), TEST_GENESIS_TIME);
        assertEq(beacon.period(), TEST_PERIOD);
        assertEq(beacon.publicKey(), TEST_PUBLIC_KEY);
        assertEq(beacon.publicKeyHash(), keccak256(TEST_PUBLIC_KEY));
    }

    function testCannotInitializeWithInvalidPublicKeyLength() public {
        bytes memory invalidPubKey = hex"1234";
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidPublicKey.selector));
        new BN254DrandBeacon(invalidPubKey, TEST_GENESIS_TIME, TEST_PERIOD);
    }

    function testCannotInitializeWithZeroGenesisTime() public {
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidBeaconConfig.selector, 0, TEST_PERIOD));
        new BN254DrandBeacon(TEST_PUBLIC_KEY, 0, TEST_PERIOD);
    }

    function testCannotInitializeWithZeroPeriod() public {
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidBeaconConfig.selector, TEST_GENESIS_TIME, 0));
        new BN254DrandBeacon(TEST_PUBLIC_KEY, TEST_GENESIS_TIME, 0);
    }

    function testVerifyBeaconRoundWithInvalidSignatureLength() public {
        bytes memory invalidSig = hex"1234";
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, 1, invalidSig));
        beacon.verifyBeaconRound(1, invalidSig);
    }

    // Test real beacon round verification
    function testVerifyBeaconRound() public view {
        uint256 round = 4347331;
        bytes memory signature =
            hex"1678b29abd57c39ef4b7009f7bff4f2707f6269e82be4c4aa151b21f0e41abdb1fb7bbf9aed70e08307b823f3d1e4002c424d939e9bfbfef2bfd9541b59a5410";
        beacon.verifyBeaconRound(round, signature);
    }

    function testVerifyBeaconRoundWithInvalidSignature() public {
        uint256 round = 4347331;
        // Modified last byte of a valid signature
        bytes memory invalidSig =
            hex"1678b29abd57c39ef4b7009f7bff4f2707f6269e82be4c4aa151b21f0e41abdb1fb7bbf9aed70e08307b823f3d1e4002c424d939e9bfbfef2bfd9541b59a5411";
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, round, invalidSig));
        beacon.verifyBeaconRound(round, invalidSig);
    }

    // New test cases for verifyBeaconRound function
    function testVerifyBeaconRoundZero() public {
        bytes memory signature = new bytes(96); // 96 bytes of zeros
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, 0, signature));
        beacon.verifyBeaconRound(0, signature);
    }

    function testVerifyBeaconRoundWithMaxRound() public {
        uint256 maxRound = type(uint256).max;
        bytes memory signature = new bytes(96); // 96 bytes of zeros
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, maxRound, signature));
        beacon.verifyBeaconRound(maxRound, signature);
    }

    function testVerifyBeaconRoundWithDifferentInvalidSignatureLengths() public {
        uint256 round = 1;

        // Test with empty signature
        bytes memory emptySig = new bytes(0);
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, round, emptySig));
        beacon.verifyBeaconRound(round, emptySig);

        // Test with signature length 95 (one byte less than required)
        bytes memory shortSig = new bytes(95);
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, round, shortSig));
        beacon.verifyBeaconRound(round, shortSig);

        // Test with signature length 97 (one byte more than required)
        bytes memory longSig = new bytes(97);
        vm.expectRevert(abi.encodeWithSelector(BN254DrandBeacon.InvalidSignature.selector, round, longSig));
        beacon.verifyBeaconRound(round, longSig);
    }
}
