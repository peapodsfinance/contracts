// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.28;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Context.sol";
import "./interfaces/IIndexManager.sol";
import "./interfaces/IWeightedIndexFactory.sol";

contract IndexManager is IIndexManager, Context, Ownable {
    IWeightedIndexFactory public podFactory;
    IIndexAndStatus[] public indexes;
    // index/pod => idx in indexes array
    mapping(address => uint256) _indexIdx;
    mapping(address => bool) public authorized;

    constructor(IWeightedIndexFactory _podFactory) Ownable(_msgSender()) {
        podFactory = _podFactory;
    }

    modifier onlyAuthorized() {
        require(_authorizedOrOwner(_msgSender()), "UA1");
        _;
    }

    modifier onlyAuthorizedOrCreator(address _index) {
        require(_authorizedOwnerOrCreator(_msgSender(), _index), "UA2");
        _;
    }

    function deployNewIndex(
        string memory indexName,
        string memory indexSymbol,
        bytes memory baseConfig,
        bytes memory immutables
    ) external override returns (address _index) {
        (_index,,) = podFactory.deployPodAndLinkDependencies(indexName, indexSymbol, baseConfig, immutables);
        _addIndex(_index, _msgSender(), false, false, false);
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

    function addIndex(address _index, address _creator, bool _verified, bool _selfLending, bool _makePublic)
        external
        override
        onlyAuthorized
    {
        _addIndex(_index, _creator, _verified, _selfLending, _makePublic);
    }

    function _addIndex(address _index, address _user, bool _verified, bool _selfLending, bool _makePublic) internal {
        _indexIdx[_index] = indexes.length;
        indexes.push(
            IIndexAndStatus({
                index: _index,
                creator: _user,
                verified: _verified,
                selfLending: _selfLending,
                makePublic: _makePublic
            })
        );
        emit AddIndex(_index, _verified);
    }

    function removeIndex(uint256 _idxInAry) external override onlyAuthorized {
        IIndexAndStatus memory _idx = indexes[_idxInAry];
        delete _indexIdx[_idx.index];
        indexes[_idxInAry] = indexes[indexes.length - 1];
        _indexIdx[indexes[_idxInAry].index] = _idxInAry;
        indexes.pop();
        emit RemoveIndex(_idx.index);
    }

    function verifyIndex(uint256 _idx, bool _verified) external override onlyAuthorized {
        require(indexes[_idx].verified != _verified, "CHANGE");
        indexes[_idx].verified = _verified;
        emit SetVerified(indexes[_idx].index, _verified);
    }

    function updateMakePublic(address _index, bool _shouldMakePublic) external onlyAuthorizedOrCreator(_index) {
        uint256 _idx = _indexIdx[_index];
        IIndexAndStatus storage _indexObj = indexes[_idx];
        require(_indexObj.makePublic != _shouldMakePublic, "T");
        _indexObj.makePublic = _shouldMakePublic;
    }

    function updateSelfLending(address _index, bool _isSelfLending) external onlyAuthorizedOrCreator(_index) {
        uint256 _idx = _indexIdx[_index];
        IIndexAndStatus storage _indexObj = indexes[_idx];
        require(_indexObj.selfLending != _isSelfLending, "T");
        _indexObj.selfLending = _isSelfLending;
    }

    function _authorizedOrOwner(address _sender) internal view returns (bool) {
        return _sender == owner() || authorized[_sender];
    }

    function _authorizedOwnerOrCreator(address _sender, address _index) internal view returns (bool) {
        uint256 _idx = _indexIdx[_index];
        return _authorizedOrOwner(_sender) || indexes[_idx].creator == _sender;
    }
}
