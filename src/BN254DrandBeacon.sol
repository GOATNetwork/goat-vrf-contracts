// SPDX-License-Identifier: MIT
pragma solidity 0.8.28;

import "./interfaces/IDrandBeacon.sol";

/**
 * @title BN254DrandBeacon
 * @dev Implementation of IDrandBeacon using BN254 curve
 * Implements BLS signature verification compatible with drand's bls-bn254-unchained-on-g1 scheme
 */
contract BN254DrandBeacon is IDrandBeacon {
    // Field order
    uint256 private constant N = 21888242871839275222246405745257275088696311157297823662689037894645226208583;

    // Negated generator of G2
    uint256 private constant N_G2_X1 = 11559732032986387107991004021392285783925812861821192530917403151452391805634;
    uint256 private constant N_G2_X0 = 10857046999023057135944570762232829481370756359578518086990519993285655852781;
    uint256 private constant N_G2_Y1 = 17805874995975841540914202342111839520379459829704422454583296818431106115052;
    uint256 private constant N_G2_Y0 = 13392588948715843804641432497768002650278120570034223513918757245338268106653;

    // Constants for hash-to-curve
    uint256 private constant T24 = 0x1000000000000000000000000000000000000000000000000;
    uint256 private constant MASK24 = 0xffffffffffffffffffffffffffffffffffffffffffffffff;

    // BN254 parameters
    uint256 private constant A = 0;
    uint256 private constant B = 3;
    uint256 private constant Z = 1;
    uint256 private constant C1 = 0x4;
    uint256 private constant C2 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3;
    uint256 private constant C3 = 0x16789af3a83522eb353c98fc6b36d713d5d8d1cc5dffffffa;
    uint256 private constant C4 = 0x10216f7ba065e00de81ac1e7808072c9dd2b2385cd7b438469602eb24829a9bd;
    uint256 private constant C5 = 0x183227397098d014dc2822db40c0ac2ecbc0b548b438e5469e10460b6c3e7ea3;

    // Domain separation tag for BN254
    bytes public constant BN254_DST = bytes("BLS_SIG_BN254G1_XMD:KECCAK-256_SVDW_RO_NUL_");

    // Beacon data storage
    uint256 private immutable _publicKey0;
    uint256 private immutable _publicKey1;
    uint256 private immutable _publicKey2;
    uint256 private immutable _publicKey3;
    bytes32 private immutable _publicKeyHash;
    uint256 private immutable _genesisTimestamp;
    uint256 private immutable _period;

    error InvalidPublicKey();
    error InvalidBeaconConfig(uint256 genesisTimestamp, uint256 period);
    error InvalidSignature(uint256 round, bytes signature);
    error BNAddFailed(uint256[4] input);
    error InvalidFieldElement(uint256 x);
    error MapToPointFailed(uint256 noSqrt);
    error InvalidDSTLength(bytes dst);
    error ModExpFailed(uint256 base, uint256 exponent, uint256 modulus);

    constructor(bytes memory publicKey_, uint256 genesisTimestamp_, uint256 period_) {
        // Validate inputs
        if (publicKey_.length != 128) revert InvalidPublicKey();
        if (genesisTimestamp_ == 0 || period_ == 0) revert InvalidBeaconConfig(genesisTimestamp_, period_);

        // Deserialize public key
        (uint256 pk0, uint256 pk1, uint256 pk2, uint256 pk3) =
            abi.decode(publicKey_, (uint256, uint256, uint256, uint256));

        // Validate public key
        uint256[4] memory pubKey = [pk0, pk1, pk2, pk3];
        if (!isValidPublicKey(pubKey)) revert InvalidPublicKey();

        // Store beacon data
        _publicKey0 = pk0;
        _publicKey1 = pk1;
        _publicKey2 = pk2;
        _publicKey3 = pk3;
        _publicKeyHash = keccak256(publicKey_);
        _genesisTimestamp = genesisTimestamp_;
        _period = period_;
    }

    function publicKeyHash() external view returns (bytes32) {
        return _publicKeyHash;
    }

    function publicKey() external view returns (bytes memory) {
        return abi.encode(_publicKey0, _publicKey1, _publicKey2, _publicKey3);
    }

    function genesisTimestamp() external view returns (uint256) {
        return _genesisTimestamp;
    }

    function period() external view returns (uint256) {
        return _period;
    }

    function verifyBeaconRound(uint256 round, bytes calldata signature) external view {
        if (signature.length != 64) revert InvalidSignature(round, signature);

        uint256[2] memory sigPoint;
        assembly {
            let sigPointPtr := sigPoint
            let sig0 := calldataload(signature.offset)
            let sig1 := calldataload(add(signature.offset, 32))
            mstore(sigPointPtr, sig0)
            mstore(add(sigPointPtr, 32), sig1)
        }

        if (!isValidSignature(sigPoint)) revert InvalidSignature(round, signature);

        bytes memory roundBytes = new bytes(32);
        assembly {
            mstore(0x00, round)
            let hashedRound := keccak256(0x18, 0x08)
            mstore(add(32, roundBytes), hashedRound)
        }

        uint256[2] memory message = hashToPoint(BN254_DST, roundBytes);
        uint256[4] memory pubKey = [_publicKey0, _publicKey1, _publicKey2, _publicKey3];

        (bool pairingSuccess, bool callSuccess) = verifySingle(sigPoint, pubKey, message);
        if (!callSuccess || !pairingSuccess) revert InvalidSignature(round, signature);
    }

    function isValidPublicKey(uint256[4] memory pubKey) internal pure returns (bool) {
        // Check that public key coordinates are valid field elements
        if (pubKey[0] >= N || pubKey[1] >= N || pubKey[2] >= N || pubKey[3] >= N) {
            return false;
        }

        // Check if the point is on the G2 curve
        return isOnCurveG2(pubKey);
    }

    function isOnCurveG2(uint256[4] memory point) internal pure returns (bool _isOnCurve) {
        assembly {
            // x0, x1
            let t1 := mload(point)
            let t0 := mload(add(point, 32))
            // x0 ^ 2
            let t2 := mulmod(t0, t0, N)
            // x1 ^ 2
            let t3 := mulmod(t1, t1, N)
            // 3 * x0 ^ 2
            let t4 := add(add(t2, t2), t2)
            // 3 * x1 ^ 2
            let t5 := addmod(add(t3, t3), t3, N)
            // x0 * (x0 ^ 2 - 3 * x1 ^ 2)
            t2 := mulmod(add(t2, sub(N, t5)), t0, N)
            // x1 * (3 * x0 ^ 2 - x1 ^ 2)
            t3 := mulmod(add(t4, sub(N, t3)), t1, N)

            // x ^ 3 + b
            t0 := addmod(t2, 0x2b149d40ceb8aaae81be18991be06ac3b5b4c5e559dbefa33267e6dc24a138e5, N)
            t1 := addmod(t3, 0x009713b03af0fed4cd2cafadeed8fdf4a74fa084e52d1852e4a2bd0685c315d2, N)

            // y0, y1
            t2 := mload(add(point, 96))
            t3 := mload(add(point, 64))
            // y ^ 2
            t4 := mulmod(addmod(t2, t3, N), addmod(t2, sub(N, t3), N), N)
            t3 := mulmod(shl(1, t2), t3, N)

            // y ^ 2 == x ^ 3 + b
            _isOnCurve := and(eq(t0, t4), eq(t1, t3))
        }
    }

    function verifySingle(uint256[2] memory signature, uint256[4] memory pubkey, uint256[2] memory message)
        internal
        view
        returns (bool pairingSuccess, bool callSuccess)
    {
        uint256[12] memory input = [
            signature[0],
            signature[1],
            N_G2_X1,
            N_G2_X0,
            N_G2_Y1,
            N_G2_Y0,
            message[0],
            message[1],
            pubkey[0],
            pubkey[1],
            pubkey[2],
            pubkey[3]
        ];
        uint256[1] memory out;
        assembly {
            callSuccess := staticcall(sub(gas(), 2000), 8, input, 384, out, 0x20)
        }
        return (out[0] != 0, callSuccess);
    }

    function hashToPoint(bytes memory domain, bytes memory message) internal view returns (uint256[2] memory) {
        uint256[2] memory u = hashToField(domain, message);
        uint256[2] memory p0 = mapToPoint(u[0]);
        uint256[2] memory p1 = mapToPoint(u[1]);
        uint256[4] memory bnAddInput;
        bnAddInput[0] = p0[0];
        bnAddInput[1] = p0[1];
        bnAddInput[2] = p1[0];
        bnAddInput[3] = p1[1];
        bool success;
        assembly {
            success := staticcall(sub(gas(), 2000), 6, bnAddInput, 128, p0, 64)
        }
        if (!success) revert BNAddFailed(bnAddInput);
        return p0;
    }

    function isValidSignature(uint256[2] memory signature) internal pure returns (bool) {
        if ((signature[0] >= N) || (signature[1] >= N)) return false;
        else return isOnCurveG1(signature);
    }

    function isOnCurveG1(uint256[2] memory point) internal pure returns (bool _isOnCurve) {
        assembly {
            let t0 := mload(point)
            let t1 := mload(add(point, 32))
            let t2 := mulmod(t0, t0, N)
            t2 := mulmod(t2, t0, N)
            t2 := addmod(t2, 3, N)
            t1 := mulmod(t1, t1, N)
            _isOnCurve := eq(t1, t2)
        }
    }

    function hashToField(bytes memory domain, bytes memory message) internal pure returns (uint256[2] memory) {
        bytes memory _msg = expandMsgTo96(domain, message);
        uint256 u0;
        uint256 u1;
        uint256 a0;
        uint256 a1;
        assembly {
            let p := add(_msg, 24)
            u1 := and(mload(p), MASK24)
            p := add(_msg, 48)
            u0 := and(mload(p), MASK24)
            a0 := addmod(mulmod(u1, T24, N), u0, N)
            p := add(_msg, 72)
            u1 := and(mload(p), MASK24)
            p := add(_msg, 96)
            u0 := and(mload(p), MASK24)
            a1 := addmod(mulmod(u1, T24, N), u0, N)
        }
        return [a0, a1];
    }

    function expandMsgTo96(bytes memory DST, bytes memory message) internal pure returns (bytes memory) {
        uint256 domainLen = DST.length;
        if (domainLen > 255) revert InvalidDSTLength(DST);
        bytes memory zpad = new bytes(136);
        bytes memory b_0 = abi.encodePacked(zpad, message, uint8(0), uint8(96), uint8(0), DST, uint8(domainLen));
        bytes32 b0 = keccak256(b_0);
        bytes memory b_i = abi.encodePacked(b0, uint8(1), DST, uint8(domainLen));
        bytes32 bi = keccak256(b_i);
        bytes memory out = new bytes(96);
        uint256 ell = 3;
        for (uint256 i = 1; i < ell; i++) {
            b_i = abi.encodePacked(b0 ^ bi, uint8(1 + i), DST, uint8(domainLen));
            assembly {
                let p := add(32, out)
                p := add(p, mul(32, sub(i, 1)))
                mstore(p, bi)
            }
            bi = keccak256(b_i);
        }
        assembly {
            let p := add(32, out)
            p := add(p, mul(32, sub(ell, 1)))
            mstore(p, bi)
        }
        return out;
    }

    function mapToPoint(uint256 u) internal view returns (uint256[2] memory p) {
        if (u >= N) revert InvalidFieldElement(u);
        uint256 tv1 = mulmod(mulmod(u, u, N), C1, N);
        uint256 tv2 = addmod(1, tv1, N);
        tv1 = addmod(1, N - tv1, N);
        uint256 tv3 = inverse(mulmod(tv1, tv2, N));
        uint256 tv5 = mulmod(mulmod(mulmod(u, tv1, N), tv3, N), C3, N);
        uint256 x1 = addmod(C2, N - tv5, N);
        uint256 x2 = addmod(C2, tv5, N);
        uint256 tv7 = mulmod(tv2, tv2, N);
        uint256 tv8 = mulmod(tv7, tv3, N);
        uint256 x3 = addmod(Z, mulmod(C4, mulmod(tv8, tv8, N), N), N);
        bool hasRoot;
        uint256 gx;
        if (legendre(g(x1)) == 1) {
            p[0] = x1;
            gx = g(x1);
            (p[1], hasRoot) = sqrt(gx);
            if (!hasRoot) revert MapToPointFailed(gx);
        } else if (legendre(g(x2)) == 1) {
            p[0] = x2;
            gx = g(x2);
            (p[1], hasRoot) = sqrt(gx);
            if (!hasRoot) revert MapToPointFailed(gx);
        } else {
            p[0] = x3;
            gx = g(x3);
            (p[1], hasRoot) = sqrt(gx);
            if (!hasRoot) revert MapToPointFailed(gx);
        }
        if (sgn0(u) != sgn0(p[1])) {
            p[1] = N - p[1];
        }
    }

    function g(uint256 x) private pure returns (uint256) {
        return addmod(mulmod(mulmod(x, x, N), x, N), B, N);
    }

    function sgn0(uint256 x) private pure returns (uint256) {
        return x % 2;
    }

    function legendre(uint256 u) private view returns (int8) {
        uint256 x = modexpLegendre(u);
        if (x == N - 1) return -1;
        if (x != 0 && x != 1) revert MapToPointFailed(u);
        return int8(int256(x));
    }

    function modexpLegendre(uint256 u) private view returns (uint256 output) {
        bytes memory input = new bytes(192);
        bool success;
        assembly {
            let p := add(input, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, u)
            p := add(p, 32)
            mstore(p, C5)
            p := add(p, 32)
            mstore(p, N)
            success := staticcall(sub(gas(), 2000), 5, add(input, 32), 192, 0x00, 32)
            output := mload(0x00)
        }
        if (!success) revert ModExpFailed(u, C5, N);
    }

    function sqrt(uint256 xx) internal view returns (uint256 x, bool hasRoot) {
        x = modexpSqrt(xx);
        hasRoot = mulmod(x, x, N) == xx;
    }

    function modexpSqrt(uint256 a) private view returns (uint256 output) {
        uint256 exponent = (N + 1) / 4;
        bytes memory input = new bytes(192);
        bool success;
        assembly {
            let p := add(input, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, a)
            p := add(p, 32)
            mstore(p, exponent)
            p := add(p, 32)
            mstore(p, N)
            success := staticcall(sub(gas(), 2000), 5, add(input, 32), 192, 0x00, 32)
            output := mload(0x00)
        }
        if (!success) revert ModExpFailed(a, exponent, N);
    }

    function inverse(uint256 a) internal view returns (uint256) {
        return modexpInverse(a);
    }

    function modexpInverse(uint256 a) private view returns (uint256 output) {
        uint256 exponent = N - 2;
        bytes memory input = new bytes(192);
        bool success;
        assembly {
            let p := add(input, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, 32)
            p := add(p, 32)
            mstore(p, a)
            p := add(p, 32)
            mstore(p, exponent)
            p := add(p, 32)
            mstore(p, N)
            success := staticcall(sub(gas(), 2000), 5, add(input, 32), 192, 0x00, 32)
            output := mload(0x00)
        }
        if (!success) revert ModExpFailed(a, exponent, N);
    }
}
