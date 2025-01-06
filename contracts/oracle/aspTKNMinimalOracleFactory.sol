// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "./aspTKNMinimalOracle.sol";

contract aspTKNMinimalOracleFactory is Ownable {
    event Create(address newOracle);

    constructor() Ownable(_msgSender()) {}

    function create(address _aspTKN, bytes memory _requiredImmutables, bytes memory _optionalImmutables, uint96 _salt)
        external
        returns (address _oracleAddress)
    {
        _oracleAddress = _deploy(getBytecode(_aspTKN, _requiredImmutables, _optionalImmutables), _getFullSalt(_salt));
        aspTKNMinimalOracle(_oracleAddress).transferOwnership(owner());
        emit Create(_oracleAddress);
    }

    function getNewCaFromParams(
        address _aspTKN,
        bytes memory _requiredImmutables,
        bytes memory _optionalImmutables,
        uint96 _salt
    ) external view returns (address) {
        bytes memory _bytecode = getBytecode(_aspTKN, _requiredImmutables, _optionalImmutables);
        return getNewCaAddress(_bytecode, _salt);
    }

    function getBytecode(address _aspTKN, bytes memory _requiredImmutables, bytes memory _optionalImmutables)
        public
        pure
        returns (bytes memory)
    {
        bytes memory _bytecode = type(aspTKNMinimalOracle).creationCode;
        return abi.encodePacked(_bytecode, abi.encode(_aspTKN, _requiredImmutables, _optionalImmutables));
    }

    function getNewCaAddress(bytes memory _bytecode, uint96 _salt) public view returns (address) {
        bytes32 _hash =
            keccak256(abi.encodePacked(bytes1(0xff), address(this), _getFullSalt(_salt), keccak256(_bytecode)));
        return address(uint160(uint256(_hash)));
    }

    function _getFullSalt(uint96 _salt) internal view returns (uint256) {
        return uint256(uint160(address(this))) + _salt;
    }

    function _deploy(bytes memory _bytecode, uint256 _finalSalt) internal returns (address _addr) {
        assembly {
            _addr := create2(callvalue(), add(_bytecode, 0x20), mload(_bytecode), _finalSalt)
            if iszero(_addr) { revert(0, 0) }
        }
    }
}
