// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/proxy/beacon/UpgradeableBeacon.sol";

/**
 * @title LockableUpgradeableBeacon
 * @dev Extension of OpenZeppelin's UpgradeableBeacon that adds the ability to permanently lock the implementation
 */
contract LockableUpgradeableBeacon is UpgradeableBeacon {
    bool private _upgradesLocked;

    event UpgradesLocked();

    constructor(address implementation_, address initialOwner_) UpgradeableBeacon(implementation_, initialOwner_) {}

    /**
     * @dev Override of the upgradeTo function that checks if upgrades are locked
     * @param _newImplementation) Address of the new implementation
     */
    function upgradeTo(address _newImplementation) public override onlyOwner {
        require(!_upgradesLocked, "LockableUpgradeableBeacon: upgrades are locked");
        super.upgradeTo(_newImplementation);
    }

    /**
     * @dev Permanently locks the ability to upgrade the implementation
     * @notice This action cannot be undone
     */
    function lockUpgrades() external onlyOwner {
        require(!_upgradesLocked, "LockableUpgradeableBeacon: already locked");
        _upgradesLocked = true;
        emit UpgradesLocked();
    }

    function upgradesLocked() external view returns (bool) {
        return _upgradesLocked;
    }
}
