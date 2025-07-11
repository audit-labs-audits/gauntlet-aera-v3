// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import { CallbackData } from "src/core/Types.sol";
import { Encoder } from "test/core/utils/Encoder.sol";
/// @title MerkleHelper
/// @notice Copied and modified from https://github.com/dmfxyz/murky

library MerkleHelper {
    function getLeaf(
        address target,
        bytes4 selector,
        bool hasValue,
        uint16[] memory configurableHooksOffsets,
        address hooks,
        CallbackData memory callbackData,
        bytes memory extractedData
    ) internal pure returns (bytes32) {
        uint256 calldataOffsetsPacked;
        if (configurableHooksOffsets.length > 0) {
            calldataOffsetsPacked = Encoder.packExtractionOffsets(configurableHooksOffsets);
        }

        return keccak256(
            abi.encodePacked(
                target, selector, hasValue, hooks, calldataOffsetsPacked, _packCallbackData(callbackData), extractedData
            )
        );
    }

    function _packCallbackData(CallbackData memory callbackData) internal pure returns (uint208) {
        return uint208(
            uint256(uint32(callbackData.selector)) << 176 | uint256(callbackData.calldataOffset) << 160
                | uint256(uint160(callbackData.caller))
        );
    }

    function hashLeafPairs(bytes32 left, bytes32 right) internal pure returns (bytes32 _hash) {
        assembly ("memory-safe") {
            switch lt(left, right)
            case 0 {
                mstore(0x0, right)
                mstore(0x20, left)
            }
            default {
                mstore(0x0, left)
                mstore(0x20, right)
            }
            _hash := keccak256(0x0, 0x40)
        }
    }

    function getRoot(bytes32[] memory data) internal pure returns (bytes32) {
        require(data.length > 1, "won't generate root for single leaf");
        while (data.length > 1) {
            data = hashLevel(data);
        }
        return data[0];
    }

    function getProof(bytes32[] memory data, uint256 node) internal pure returns (bytes32[] memory) {
        require(data.length > 1, "won't generate proof for single leaf");
        // The size of the proof is equal to the ceiling of log2(numLeaves)
        bytes32[] memory result = new bytes32[](log2ceilBitMagic(data.length));
        uint256 pos = 0;

        // Two overflow risks: node, pos
        // node: max array size is 2**256-1. Largest index in the array will be 1 less than that. Also,
        // for dynamic arrays, size is limited to 2**64-1
        // pos: pos is bounded by log2(data.length), which should be less than type(uint256).max
        while (data.length > 1) {
            unchecked {
                if (node & 0x1 == 1) {
                    result[pos] = data[node - 1];
                } else if (node + 1 == data.length) {
                    result[pos] = bytes32(0);
                } else {
                    result[pos] = data[node + 1];
                }
                ++pos;
                node /= 2;
            }
            data = hashLevel(data);
        }
        return result;
    }

    ///@dev function is private to prevent unsafe data from being passed
    function hashLevel(bytes32[] memory data) internal pure returns (bytes32[] memory) {
        bytes32[] memory result;

        // Function is private, and all internal callers check that data.length >=2
        // Underflow is not possible as lowest possible value for data/result index is 1
        // overflow should be safe as length is / 2 always
        unchecked {
            uint256 length = data.length;
            if (length & 0x1 == 1) {
                result = new bytes32[](length / 2 + 1);
                result[result.length - 1] = hashLeafPairs(data[length - 1], bytes32(0));
            } else {
                result = new bytes32[](length / 2);
            }
            // pos is upper bounded by data.length / 2, so safe even if array is at max size
            uint256 pos = 0;
            for (uint256 i = 0; i < length - 1; i += 2) {
                result[pos] = hashLeafPairs(data[i], data[i + 1]);
                ++pos;
            }
        }
        return result;
    }

    /**
     *
     * MATH "LIBRARY" *
     *
     */

    /// @dev  Note that x is assumed > 0
    function log2ceil(uint256 x) internal pure returns (uint256) {
        uint256 ceil = 0;
        uint256 pOf2;
        // If x is a power of 2, then this function will return a ceiling
        // that is 1 greater than the actual ceiling. So we need to check if
        // x is a power of 2, and subtract one from ceil if so
        assembly ("memory-safe") {
            // we check by seeing if x == (~x + 1) & x. This applies a mask
            // to find the lowest set bit of x and then checks it for equality
            // with x. If they are equal, then x is a power of 2

            /* Example
                x has single bit set
                x := 0000_1000
                (~x + 1) = (1111_0111) + 1 = 1111_1000
                (1111_1000 & 0000_1000) = 0000_1000 == x

                x has multiple bits set
                x := 1001_0010
                (~x + 1) = (0110_1101 + 1) = 0110_1110
                (0110_1110 & x) = 0000_0010 != x
            */

            // we do some assembly magic to treat the bool as an integer later on
            pOf2 := eq(and(add(not(x), 1), x), x)
        }

        // if x == type(uint256).max, than ceil is capped at 256
        // if x == 0, then pO2 == 0, so ceil won't underflow
        unchecked {
            while (x > 0) {
                x >>= 1;
                ceil++;
            }
            ceil -= pOf2; // see above
        }
        return ceil;
    }

    /// Original bitmagic adapted from https://github.com/paulrberg/prb-math/blob/main/contracts/PRBMath.sol
    /// @dev Note that x assumed > 1
    function log2ceilBitMagic(uint256 x) internal pure returns (uint256) {
        if (x <= 1) {
            return 0;
        }
        uint256 msb = 0;
        uint256 _x = x;
        if (x >= 2 ** 128) {
            x >>= 128;
            msb += 128;
        }
        if (x >= 2 ** 64) {
            x >>= 64;
            msb += 64;
        }
        if (x >= 2 ** 32) {
            x >>= 32;
            msb += 32;
        }
        if (x >= 2 ** 16) {
            x >>= 16;
            msb += 16;
        }
        if (x >= 2 ** 8) {
            x >>= 8;
            msb += 8;
        }
        if (x >= 2 ** 4) {
            x >>= 4;
            msb += 4;
        }
        if (x >= 2 ** 2) {
            x >>= 2;
            msb += 2;
        }
        if (x >= 2 ** 1) {
            msb += 1;
        }

        uint256 lsb = (~_x + 1) & _x;
        if ((lsb == _x) && (msb > 0)) {
            return msb;
        } else {
            return msb + 1;
        }
    }
}
