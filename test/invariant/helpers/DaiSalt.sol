// SPDX-License-Identifier
pragma solidity ^0.8.19;

import {Test, console2} from "forge-std/Test.sol";
import {FuzzBase} from "fuzzlib/FuzzBase.sol";

import {MockERC20} from "../mocks/MockERC20.sol";

contract SaltGenerator is Test, FuzzBase {

    function test_salt() public {
        bytes memory constructorArgs = abi.encodePacked(
            type(MockERC20).creationCode,
            ""
        );

        string[] memory uniswapV2Inputs = new string[](5);
        uniswapV2Inputs[0] = "./test/invariant/helpers/salt_hash.sh";
        uniswapV2Inputs[1] = "--bytecodeHash";
        uniswapV2Inputs[2] = toHexString(keccak256(constructorArgs));
        uniswapV2Inputs[3] = "--deployer";
        uniswapV2Inputs[4] = toString(0x00a329c0648769A73afAc7F9381E08FB43dBEA72);
        // 0x4e59b44847b379578588920ca78fbf26c0b4956c

        bytes memory uniswapV2Res = vm.ffi(uniswapV2Inputs);
        bytes32 uniswapV2Salt = abi.decode(uniswapV2Res, (bytes32));

        fl.log(
            "Dai Salt:",
            uniswapV2Salt
        );
        fl.t(false, "DONE");
    }

    function toString(address _addr) internal pure returns (string memory) {
        bytes32 value = bytes32(uint256(uint160(_addr)));
        bytes memory alphabet = "0123456789abcdef";

        bytes memory str = new bytes(42);
        str[0] = "0";
        str[1] = "x";

        for (uint256 i = 0; i < 20; i++) {
            str[2 + i * 2] = alphabet[uint8(value[i + 12] >> 4)];
            str[3 + i * 2] = alphabet[uint8(value[i + 12] & 0x0f)];
        }

        return string(str);
    }

    function toHexString(bytes32 input) internal pure returns (string memory) {
        bytes16 symbols = "0123456789abcdef";
        bytes memory hex_buffer = new bytes(64 + 2);
        hex_buffer[0] = "0";
        hex_buffer[1] = "x";

        uint256 pos = 2;
        for (uint256 i = 0; i < 32; ++i) {
            uint256 _byte = uint8(input[i]);
            hex_buffer[pos++] = symbols[_byte >> 4];
            hex_buffer[pos++] = symbols[_byte & 0xf];
        }
        return string(hex_buffer);
    }
}