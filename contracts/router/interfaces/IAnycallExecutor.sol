// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

/// IAnycallExecutor interface of the anycall executor
interface IAnycallExecutor {
    function execute(
        address _anycallProxy,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);
}
