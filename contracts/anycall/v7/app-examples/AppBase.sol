// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../../access/AdminControl.sol";
import "../interfaces/IAnycallProxy.sol";
import "../interfaces/IAnycallExecutor.sol";

abstract contract AppBase is AdminControl {
    address public callProxy;
    address public executor;

    // associated client app on each chain
    mapping(uint256 => address) public clientPeers; // key is chainId

    modifier onlyExecutor() {
        require(msg.sender == executor, "AppBase: onlyExecutor");
        _;
    }

    constructor(address _admin, address _callProxy) AdminControl(_admin) {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallProxy(callProxy).executor();
    }

    receive() external payable {
        require(
            msg.sender == callProxy,
            "AppBase: receive from forbidden sender"
        );
    }

    function setCallProxy(address _callProxy) external onlyAdmin {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallProxy(callProxy).executor();
    }

    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peers
    ) external onlyAdmin {
        require(_chainIds.length == _peers.length);
        for (uint256 i = 0; i < _chainIds.length; i++) {
            clientPeers[_chainIds[i]] = _peers[i];
        }
    }

    function _getAndCheckPeer(uint256 chainId) internal view returns (address) {
        address clientPeer = clientPeers[chainId];
        require(clientPeer != address(0), "AppBase: peer not exist");
        return clientPeer;
    }

    function _getAndCheckContext()
        internal
        view
        returns (
            address from,
            uint256 fromChainId,
            uint256 nonce
        )
    {
        (from, fromChainId, nonce) = IAnycallExecutor(executor).context();
        require(clientPeers[fromChainId] == from, "AppBase: wrong context");
    }
}
