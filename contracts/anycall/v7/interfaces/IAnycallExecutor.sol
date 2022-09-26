// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

/// IAnycallExecutor interface of the anycall executor
interface IAnycallExecutor {
    function context()
        external
        view
        returns (
            address from,
            uint256 fromChainID,
            uint256 nonce
        );

    function execute(
        address _to,
        bytes calldata _data,
        address _from,
        uint256 _fromChainID,
        uint256 _nonce,
        bytes calldata _extdata
    ) external returns (bool success, bytes memory result);
}
