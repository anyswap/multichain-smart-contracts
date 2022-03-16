// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "./MPCManageable.sol";

interface ITradeProxy {
    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        );
}

interface ITradeProxyManager {
    function trade(
        address tradeProxy,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        );

    function addTradeProxy(address tradeProxy) external;

    function removeTradeProxy(address tradeProxy) external;

    function addAuth(address auth) external;

    function removeAuth(address auth) external;
}

contract TradeProxyManager is MPCManageable, ITradeProxyManager {
    using Address for address;

    // mapping for tradeProxy to exists flag
    mapping(address => bool) public tradeProxyCheck;
    // mapping for caller to call auth
    mapping(address => bool) public authCheck;

    modifier onlyAuth() {
        require(authCheck[msg.sender], "TradeProxyManageable: caller auth fails!");
        _;
    }

    modifier tradeProxyExists(address tradeProxy) {
        require(
            tradeProxyCheck[tradeProxy],
            "TradeProxyManageable: tradeProxy nonexists!"
        );
        _;
    }

    constructor(address mpc_) MPCManageable(mpc_) {
        authCheck[mpc_] = true;
    }

    function addAuth(address auth) external onlyMPC {
        require(authCheck[auth] == false, "TradeProxyManageable: auth exists!");
        authCheck[auth] = true;
    }

    function removeAuth(address auth) external onlyMPC {
        require(
            authCheck[auth] == true,
            "TradeProxyManageable: auth nonexists!"
        );
        authCheck[auth] = false;
    }

    function addTradeProxy(address tradeProxy) external onlyMPC {
        require(
            tradeProxyCheck[tradeProxy] == false,
            "TradeProxyManageable: tradeProxy exists!"
        );
        tradeProxyCheck[tradeProxy] = true;
    }

    function removeTradeProxy(address tradeProxy) external onlyMPC {
        require(
            tradeProxyCheck[tradeProxy],
            "TradeProxyManageable: tradeProxy nonexists!"
        );
        tradeProxyCheck[tradeProxy] = false;
    }

    function trade(
        address tradeProxy,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        tradeProxyExists(tradeProxy)
        onlyAuth
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        (recvToken, receiver, recvAmount) = ITradeProxy(tradeProxy).exec(
            token,
            amount,
            data
        );
    }
}
