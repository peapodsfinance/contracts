// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IIndexManager.sol";

contract IndexManager is IIndexManager, Context, Ownable {
    IIndexAndStatus[] public indexes;
    mapping(address => bool) public authorized;

    modifier onlyAuthorized() {
        bool _authd = _msgSender() == owner() || authorized[_msgSender()];
        require(_authd, "UNAUTHORIZED");
        _;
    }

    function indexLength() external view returns (uint256) {
        return indexes.length;
    }

    function allIndexes() external view override returns (IIndexAndStatus[] memory) {
        return indexes;
    }

    function setAuthorized(address _auth, bool _isAuthed) external onlyOwner {
        require(authorized[_auth] != _isAuthed, "CHANGE");
        authorized[_auth] = _isAuthed;
    }

    function addIndex(address _index, bool _verified) external override onlyAuthorized {
        indexes.push(IIndexAndStatus({index: _index, verified: _verified}));
        emit AddIndex(_index, _verified);
    }

    function removeIndex(uint256 _indexIdx) external override onlyAuthorized {
        IIndexAndStatus memory _idx = indexes[_indexIdx];
        indexes[_indexIdx] = indexes[indexes.length - 1];
        indexes.pop();
        emit RemoveIndex(_idx.index);
    }

    function verifyIndex(uint256 _indexIdx, bool _verified) external override onlyAuthorized {
        require(indexes[_indexIdx].verified != _verified, "CHANGE");
        indexes[_indexIdx].verified = _verified;
        emit SetVerified(indexes[_indexIdx].index, _verified);
    }
}
