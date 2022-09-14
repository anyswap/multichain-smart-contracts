// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

/// IAnycallExecutor interface of the anycall executor
/// Note: `_receiver` is the `fallback receive address` when exec failed.
interface IAnycallExecutor {
    function execute(
        address _anycallProxy,
        address _token,
        address _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);
}
