// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "./interfaces/IDrandBeacon.sol";

/**
 * @title BLS12381DrandBeacon
 * @dev Implementation of IDrandBeacon using BLS12381 curve
 * Implements BLS signature verification compatible with drand's bls-unchained-g1-rfc9380 scheme.
 * This implementation has not been tested yet.
 */
contract BLS12381DrandBeacon is IDrandBeacon {
    // P is the BLS12-381 base field modulus encoded as 64 bytes.
    // According to EIP-2537, p =
    // 0x1a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab
    // When encoded as 64 bytes the top 16 bytes are zero.
    bytes private constant P =
        hex"000000000000000000000000000000001a0111ea397fe69a4b1ba7b6434bacd764774b84f38512bf6730d2a0f6b0f6241eabfffeb153ffffb9feffffffffaaab";

    // Precompile addresses
    address private constant BLS_MAP_G1 = address(0x10); // Hash-to-curve
    address private constant BLS_PAIRING = address(0x0f); // Pairing check
    address private constant BLS_G1_ADD = address(0x0b); // G1 point addition

    // Constants
    bytes private constant DST = "BLS_SIG_BLS12381G1_XMD:SHA-256_SSWU_RO_NUL_";
    // G2_GENERATOR is the uncompressed G2 generator (256 bytes)
    bytes private constant G2_GENERATOR =
        hex"13e02b6052719f607dacd3a088274f65596bd0d09920b61ab5da61bbdc7f5049334cf11213945d57e5ac7d055d042b7e024aa2b2f08f0a91260805272dc51051c6e47ad4fa403b02b4510b647ae3d1770bac0326a805bbefd48056c8c121bdb8";

    // Storage variables:
    // _publicKey is stored in uncompressed G2 format (256 bytes expected).
    bytes private _publicKey;
    bytes32 private immutable _publicKeyHash;
    uint256 private immutable _genesisTimestamp;
    uint256 private immutable _period;

    constructor(
        bytes memory uncompressedPublicKey_, // Uncompressed G2 public key (256 bytes expected)
        uint256 genesisTimestamp_,
        uint256 period_
    ) {
        require(uncompressedPublicKey_.length == 256, "Invalid public key length");
        _publicKey = uncompressedPublicKey_;
        _publicKeyHash = keccak256(uncompressedPublicKey_);
        _genesisTimestamp = genesisTimestamp_;
        _period = period_;
    }

    // =============== Public Interface ===============
    function publicKey() external view returns (bytes memory) {
        return _publicKey;
    }

    function publicKeyHash() external view returns (bytes32) {
        return _publicKeyHash;
    }

    function genesisTimestamp() external view returns (uint256) {
        return _genesisTimestamp;
    }

    function period() external view returns (uint256) {
        return _period;
    }

    function verifyBeaconRound(uint256 round, bytes calldata signature) external view {
        bool valid = _verifyCore(round, signature);
        require(valid, "Invalid signature");
    }

    // =============== Core Verification ===============
    // This implementation uses the pairing equation:
    // e(-H(m), G2_GENERATOR) * e(signature, pubkey) == 1
    function _verifyCore(uint256 round, bytes calldata uncompressedSig) private view returns (bool) {
        // For uncompressed G1 signatures, the expected length is 128 bytes.
        require(uncompressedSig.length == 128, "Invalid G1 point length");

        // Step 1: Hash message to G1 (output is an uncompressed G1 point, 128 bytes).
        bytes memory message = abi.encodePacked(_uint64ToBE(round));
        bytes memory hashPoint = hashToG1(message);

        // Step 2: Use the provided signature directly (already uncompressed).
        bytes memory signature = uncompressedSig;

        // Step 3: Perform the pairing check.
        return _pairingCheck(hashPoint, signature);
    }

    // Calls the MapG1 precompile with the expanded message to obtain an uncompressed G1 point.
    // The EIP specifies the output length should be 128 bytes, but if the precompile returns 96 bytes,
    // we pad it to 128 bytes.
    function hashToG1(bytes memory message) private view returns (bytes memory) {
        bytes memory uniform = expandMessageXMD(message, DST, 128);
        (bool success, bytes memory point) = BLS_MAP_G1.staticcall(uniform);
        require(success, "Hash-to-G1 failed");

        require(point.length == 128, "Invalid G1 point length from map");
        return point;
    }

    // Constructs the pairing input and calls the pairing precompile.
    // Pair 1: (-H(m)) (128 bytes) || G2_GENERATOR (256 bytes)
    // Pair 2: signature (128 bytes) || _publicKey (256 bytes)
    function _pairingCheck(bytes memory hashPoint, bytes memory signature) private view returns (bool) {
        bytes memory negatedHash = negateG1(hashPoint);
        bytes memory input = abi.encodePacked(
            negatedHash, // -H(m) (128 bytes)
            G2_GENERATOR, // G2 generator (256 bytes)
            signature, // Signature S (128 bytes)
            _publicKey // Public key PK (256 bytes)
        );
        (bool success, bytes memory result) = BLS_PAIRING.staticcall(input);
        return success && result.length == 32 && result[31] == 0x01;
    }

    // negateG1 negates an uncompressed G1 point.
    // The point is encoded as 128 bytes: first 64 bytes for x and next 64 bytes for y.
    // It returns a new uncompressed point with x unchanged and y replaced by (p - y) mod p.
    function negateG1(bytes memory point) private pure returns (bytes memory) {
        require(point.length == 128, "Invalid G1 point length");
        bytes memory result = new bytes(128);
        // Copy x coordinate unchanged.
        for (uint256 i = 0; i < 64; i++) {
            result[i] = point[i];
        }
        // Extract y coordinate.
        bytes memory y = new bytes(64);
        for (uint256 i = 0; i < 64; i++) {
            y[i] = point[64 + i];
        }
        // Compute modular negation of y.
        bytes memory negY = modNegate(y);
        for (uint256 i = 0; i < 64; i++) {
            result[64 + i] = negY[i];
        }
        return result;
    }

    // modNegate computes (P - y) mod P for a field element y encoded in 64 bytes.
    // If y is zero, returns y.
    function modNegate(bytes memory y) internal pure returns (bytes memory) {
        require(y.length == 64, "Invalid field element length");
        uint256 yHigh = loadUint256(y, 0);
        uint256 yLow = loadUint256(y, 32);
        uint256 PHigh = loadUint256(P, 0);
        uint256 PLow = loadUint256(P, 32);
        if (yHigh == 0 && yLow == 0) {
            return y;
        }
        uint256 lowResult;
        uint256 borrow;
        unchecked {
            if (PLow < yLow) {
                lowResult = PLow + (type(uint256).max - yLow + 1);
                borrow = 1;
            } else {
                lowResult = PLow - yLow;
                borrow = 0;
            }
            uint256 highResult = PHigh - yHigh - borrow;
            return combineUint256(highResult, lowResult);
        }
    }

    // loadUint256 loads a uint256 from bytes at a given offset.
    function loadUint256(bytes memory b, uint256 offset) internal pure returns (uint256 x) {
        require(b.length >= offset + 32, "Not enough bytes");
        assembly {
            x := mload(add(b, add(32, offset)))
        }
    }

    // combineUint256 combines two uint256 values (high and low) into a 64-byte big-endian bytes array.
    function combineUint256(uint256 high, uint256 low) internal pure returns (bytes memory) {
        bytes memory out = new bytes(64);
        assembly {
            mstore(add(out, 32), high)
            mstore(add(out, 96), low)
        }
        return out;
    }

    // slice returns a slice of byte array 'data' starting at 'start' of length 'len'.
    function slice(bytes memory data, uint256 start, uint256 len) internal pure returns (bytes memory) {
        require(data.length >= start + len, "Slice out of range");
        bytes memory tempBytes;

        assembly {
            switch iszero(len)
            case 0 {
                tempBytes := mload(0x40)
                let lengthmod := and(len, 31)
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, len)
                for { let cc := add(add(data, lengthmod), start) } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } { mstore(mc, mload(cc)) }
                mstore(tempBytes, len)
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            default {
                tempBytes := mload(0x40)
                mstore(tempBytes, 0)
                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return tempBytes;
    }

    // padLeft pads the byte array 'input' on the left with zeros to reach 'desired' length.
    function padLeft(bytes memory input, uint256 desired) internal pure returns (bytes memory) {
        if (input.length >= desired) {
            return input;
        }
        bytes memory padded = new bytes(desired);
        uint256 diff = desired - input.length;
        for (uint256 i = 0; i < input.length; i++) {
            padded[diff + i] = input[i];
        }
        return padded;
    }

    // =============== XMD-Hash Implementation ===============
    function expandMessageXMD(bytes memory message, bytes memory domain, uint256 len)
        private
        pure
        returns (bytes memory)
    {
        uint256 bLen = (len + 31) / 32;
        require(bLen <= 255, "Expand length too large");

        bytes memory msgPrime =
            abi.encodePacked(_leftPad(bytes32(0), 64), message, _uint16ToBE(uint16(len)), uint8(0), domain);

        bytes32 b0 = sha256(msgPrime);
        bytes32 b1 = sha256(abi.encodePacked(b0, uint8(1), domain));

        bytes memory uniform = abi.encodePacked(b1);
        for (uint256 i = 2; i <= bLen; i++) {
            bytes32 bi = sha256(abi.encodePacked(_xorBytes(b0, uniform), uint8(i), domain));
            uniform = abi.encodePacked(uniform, bi);
        }

        return _truncateBytes(uniform, len);
    }

    // =============== Utility Functions ===============
    function _uint64ToBE(uint256 x) private pure returns (bytes memory) {
        bytes memory b = new bytes(8);
        assembly {
            mstore(add(b, 32), shl(192, x))
        }
        return b;
    }

    function _uint16ToBE(uint16 x) private pure returns (bytes memory) {
        bytes memory b = new bytes(2);
        b[0] = bytes1(uint8(x >> 8));
        b[1] = bytes1(uint8(x));
        return b;
    }

    function _truncateBytes(bytes memory data, uint256 len) private pure returns (bytes memory) {
        bytes memory result = new bytes(len);
        for (uint256 i = 0; i < len; i++) {
            result[i] = data[i];
        }
        return result;
    }

    function _xorBytes(bytes32 a, bytes memory b) private pure returns (bytes32) {
        bytes32 result;
        for (uint256 i = 0; i < 32; i++) {
            result |= bytes32(uint256(uint8(b[i])) ^ uint256(uint8(a[i]))) >> (i * 8);
        }
        return result;
    }

    function _leftPad(bytes32 data, uint256 len) private pure returns (bytes memory) {
        bytes memory result = new bytes(len);
        assembly {
            mstore(add(result, 32), data)
        }
        return result;
    }
}
