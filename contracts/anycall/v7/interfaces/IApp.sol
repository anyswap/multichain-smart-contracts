// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

/// IApp interface of the application
interface IApp {
    /// (required) call on the destination chain to exec the interaction
    function anyExecute(bytes calldata _data)
        external
        returns (bool success, bytes memory result);

    /// (optional,advised) call back on the originating chain if the cross chain interaction fails
    /// `_to` and `_data` are the orignal interaction arguments call on the destination chain
    function anyFallback(address _to, bytes calldata _data)
        external
        returns (bool success, bytes memory result);
}
