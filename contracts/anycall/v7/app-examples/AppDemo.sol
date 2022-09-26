// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../interfaces/IApp.sol";
import "./AppBase.sol";

contract AppDemo is IApp, AppBase {
    event LogCallin(
        string message,
        address sender,
        address receiver,
        uint256 fromChainId
    );
    event LogCallout(
        string message,
        address sender,
        address receiver,
        uint256 toChainId
    );
    event LogCalloutFail(
        string message,
        address sender,
        address receiver,
        uint256 toChainId
    );

    constructor(address _admin, address _callProxy)
        AppBase(_admin, _callProxy)
    {}

    /**
        @dev Call by the user to submit a request for a cross chain interaction
        @param flags The bitwised flags
            FLAG_PAY_FEE_ON_DEST = 2 (pay fee on the destination chain, otherwise pay fee on source chain)
            FLAG_ALLOW_FALLBACK = 4 (allow fallback if cross chain interaction failed)
    */
    function callout(
        string calldata message,
        address receiver,
        uint256 toChainId,
        uint256 flags
    ) external payable {
        address clientPeer = _getAndCheckPeer(toChainId);

        uint256 oldCoinBalance;
        if (msg.value > 0) {
            oldCoinBalance = address(this).balance - msg.value;
        }

        bytes memory data = abi.encode(
            message,
            msg.sender,
            receiver,
            toChainId
        );
        IAnycallProxy(callProxy).anyCall{value: msg.value}(
            clientPeer,
            data,
            toChainId,
            flags,
            ""
        );

        if (msg.value > 0) {
            uint256 newCoinBalance = address(this).balance;
            if (newCoinBalance > oldCoinBalance) {
                // return remaining fees
                (bool success, ) = msg.sender.call{
                    value: newCoinBalance - oldCoinBalance
                }("");
                require(success);
            }
        }

        emit LogCallout(message, msg.sender, receiver, toChainId);
    }

    /// @notice Call by `AnycallProxy` to execute a cross chain interaction on the destination chain
    function anyExecute(bytes calldata data)
        external
        override
        onlyExecutor
        returns (bool success, bytes memory result)
    {
        (, uint256 fromChainId, ) = _getAndCheckContext();

        (string memory message, address sender, address receiver, ) = abi
            .decode(data, (string, address, address, uint256));

        // Testing: add a condition of execute failure situation here to test fallbak function
        require(bytes(message).length < 10, "App: message too long");

        emit LogCallin(message, sender, receiver, fromChainId);
        return (true, "");
    }

    /// @notice call back by `AnycallProxy` if the cross chain interaction fails on the destination chain
    function anyFallback(bytes calldata data)
        external
        override
        onlyExecutor
        returns (bool success, bytes memory result)
    {
        _getAndCheckContext();

        (
            string memory message,
            address sender,
            address receiver,
            uint256 toChainId
        ) = abi.decode(data, (string, address, address, uint256));

        emit LogCalloutFail(message, sender, receiver, toChainId);
        return (true, "");
    }
}
