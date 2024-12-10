// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IIndexManager.sol";
import "./interfaces/IWeightedIndexFactory.sol";

contract IndexManager is IIndexManager, Context, Ownable {
    IWeightedIndexFactory public podFactory;
    IIndexAndStatus[] public indexes;
    mapping(address => bool) public authorized;

    constructor(IWeightedIndexFactory _podFactory) Ownable(_msgSender()) {
        podFactory = _podFactory;
    }

    modifier onlyAuthorized() {
        bool _authd = _msgSender() == owner() || authorized[_msgSender()];
        require(_authd, "UNAUTHORIZED");
        _;
    }

    function deployNewIndex(
        string memory indexName,
        string memory indexSymbol,
        IDecentralizedIndex.Config memory config,
        IDecentralizedIndex.Fees memory fees,
        address[] memory tokens,
        uint256[] memory weights,
        address stakeUserRestriction,
        bool leaveRewardsAsPairedLp,
        bytes memory immutables
    ) external {
        (address _index,,) = podFactory.deployPodAndLinkDependencies(
            indexName,
            indexSymbol,
            config,
            fees,
            tokens,
            weights,
            stakeUserRestriction,
            leaveRewardsAsPairedLp,
            immutables
        );
        _addIndex(_index, false);
    }

    function indexLength() external view returns (uint256) {
        return indexes.length;
    }

    function allIndexes() external view override returns (IIndexAndStatus[] memory) {
        return indexes;
    }

    function setFactory(IWeightedIndexFactory _newFactory) external onlyOwner {
        podFactory = _newFactory;
    }

    function setAuthorized(address _auth, bool _isAuthed) external onlyOwner {
        require(authorized[_auth] != _isAuthed, "CHANGE");
        authorized[_auth] = _isAuthed;
    }

    function addIndex(address _index, bool _verified) external override onlyAuthorized {
        _addIndex(_index, _verified);
    }

    function _addIndex(address _index, bool _verified) internal {
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
