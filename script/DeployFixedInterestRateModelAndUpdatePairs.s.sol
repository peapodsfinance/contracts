// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "forge-std/Script.sol";
import "forge-std/console.sol";
import {FixedInterestRateModel} from "../contracts/liquidator/FixedInterestRateModel.sol";
import {IFraxlendPair} from "../contracts/interfaces/IFraxlendPair.sol";
import {VaultAccount} from "../contracts/libraries/VaultAccount.sol";

interface IOwnable {
    function owner() external view returns (address);
}

contract DeployFixedInterestRateModelAndUpdatePairs is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Parse FraxlendPair addresses from environment variable
        // Expected format: FRAXLEND_PAIRS="0xAddress1,0xAddress2,0xAddress3"
        // If not provided, script will fail with a clear error message
        address[] memory fraxlendPairs = parseFraxlendPairs();

        require(
            fraxlendPairs.length > 0, "No FraxlendPair addresses provided. Set FRAXLEND_PAIRS environment variable."
        );
        console.log("Processing %d FraxlendPair(s)", fraxlendPairs.length);

        vm.startBroadcast(deployerPrivateKey);

        // 1. Deploy a new FixedInterestRateModel contract with constructor input as 0
        console.log("Deploying FixedInterestRateModel with rate 0...");
        FixedInterestRateModel fixedRateModel = new FixedInterestRateModel(uint64(0));
        console.log("FixedInterestRateModel deployed to: %s", address(fixedRateModel));

        // Process each FraxlendPair
        for (uint256 i = 0; i < fraxlendPairs.length; i++) {
            address pairAddress = fraxlendPairs[i];
            console.log("--- Processing FraxlendPair %d at address: %s ---", i + 1, pairAddress);
            console.log("Current owner: %s", IOwnable(pairAddress).owner());

            IFraxlendPair pair = IFraxlendPair(pairAddress);

            // 3. Log the current rateContract
            address currentRateContract = pair.rateContract();
            console.log("Current rateContract: %s", currentRateContract);

            // 4. Execute setRateContract with the new FixedInterestRateModel we just created
            console.log("Setting new rate contract to: %s", address(fixedRateModel));
            pair.setRateContract(address(fixedRateModel));
            console.log("Rate contract updated successfully");

            // 5. Execute addInterest on the IFraxlendPair
            console.log("Calling addInterest...");
            (
                uint256 interestEarned,
                uint256 feesAmount,
                uint256 feesShare,
                IFraxlendPair.CurrentRateInfo memory newCurrentRateInfo,
                VaultAccount memory totalAsset,
                VaultAccount memory totalBorrow
            ) = pair.addInterest(true);

            // 6. Verify through the returned data in addInterest that the new rate is indeed 0
            console.log("Interest earned: %d", interestEarned);
            console.log("Fees amount: %d", feesAmount);
            console.log("Fees share: %d", feesShare);
            console.log("New rate per second: %d", newCurrentRateInfo.ratePerSec);
            console.log("Full utilization rate: %d", newCurrentRateInfo.fullUtilizationRate);

            // Verification
            if (newCurrentRateInfo.ratePerSec == 0) {
                console.log("VERIFICATION PASSED: Rate per second is 0 as expected");
            } else {
                console.log(
                    "VERIFICATION FAILED: Rate per second is not 0, actual value: %d", newCurrentRateInfo.ratePerSec
                );
            }

            if (newCurrentRateInfo.fullUtilizationRate == 0) {
                console.log("VERIFICATION PASSED: Full utilization rate is 0 as expected");
            } else {
                console.log(
                    "VERIFICATION FAILED: Full utilization rate is not 0, actual value: %d",
                    newCurrentRateInfo.fullUtilizationRate
                );
            }

            console.log("Total asset amount: %d", totalAsset.amount);
            console.log("Total asset shares: %d", totalAsset.shares);
            console.log("Total borrow amount: %d", totalBorrow.amount);
            console.log("Total borrow shares: %d", totalBorrow.shares);
        }

        console.log("=== Script execution completed ===");
        console.log("FixedInterestRateModel address: %s", address(fixedRateModel));
        console.log("Processed %d FraxlendPairs", fraxlendPairs.length);

        vm.stopBroadcast();
    }

    /// @notice Parses FraxlendPair addresses from the FRAXLEND_PAIRS environment variable
    /// @dev Expected format: "0xAddress1,0xAddress2,0xAddress3" (comma-separated, no spaces)
    /// @return Array of parsed addresses
    function parseFraxlendPairs() internal view returns (address[] memory) {
        // Try to read the environment variable
        try vm.envString("FRAXLEND_PAIRS") returns (string memory pairsStr) {
            return parseAddressArray(pairsStr);
        } catch {
            // If environment variable is not set, return empty array
            // The script will fail with a clear error message
            return new address[](0);
        }
    }

    /// @notice Parses a comma-separated string of addresses into an array
    /// @param addressesStr Comma-separated string of addresses (e.g., "0xAddr1,0xAddr2")
    /// @return Array of parsed addresses
    function parseAddressArray(string memory addressesStr) internal pure returns (address[] memory) {
        bytes memory strBytes = bytes(addressesStr);

        // Handle empty string
        if (strBytes.length == 0) {
            return new address[](0);
        }

        // Count commas to determine array size
        uint256 commaCount = 0;
        for (uint256 i = 0; i < strBytes.length; i++) {
            if (strBytes[i] == ",") {
                commaCount++;
            }
        }
        uint256 addressCount = commaCount + 1;

        // Create array and parse addresses
        address[] memory addresses = new address[](addressCount);
        uint256 addressIndex = 0;
        uint256 startIndex = 0;

        for (uint256 i = 0; i <= strBytes.length; i++) {
            // Process when we hit a comma or reach the end
            if (i == strBytes.length || strBytes[i] == ",") {
                // Extract substring for this address
                bytes memory addressBytes = new bytes(i - startIndex);
                for (uint256 j = 0; j < addressBytes.length; j++) {
                    addressBytes[j] = strBytes[startIndex + j];
                }

                // Convert bytes to string and parse address
                string memory addressStr = string(addressBytes);
                addresses[addressIndex] = parseAddress(addressStr);
                addressIndex++;
                startIndex = i + 1; // Skip the comma
            }
        }

        return addresses;
    }

    /// @notice Parses a string representation of an address to an address type
    /// @param str String representation of an address (with or without 0x prefix)
    /// @return Parsed address
    function parseAddress(string memory str) internal pure returns (address) {
        bytes memory strBytes = bytes(str);
        require(strBytes.length > 0, "Empty address string");

        // Remove 0x prefix if present
        uint256 offset = 0;
        if (strBytes.length >= 2 && strBytes[0] == "0" && (strBytes[1] == "x" || strBytes[1] == "X")) {
            offset = 2;
        }

        require(strBytes.length - offset == 40, "Invalid address length");

        // Parse hex string to address
        uint160 result = 0;
        for (uint256 i = offset; i < strBytes.length; i++) {
            uint160 digit = uint160(uint8(strBytes[i]));

            // Convert character to hex value
            if (digit >= 48 && digit <= 57) {
                // 0-9
                digit -= 48;
            } else if (digit >= 65 && digit <= 70) {
                // A-F
                digit -= 55;
            } else if (digit >= 97 && digit <= 102) {
                // a-f
                digit -= 87;
            } else {
                revert("Invalid character in address");
            }

            result = result * 16 + digit;
        }

        return address(result);
    }
}
