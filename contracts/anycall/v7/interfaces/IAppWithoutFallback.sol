// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

/// IAppWithoutFallback interface of the application (without fallback support)
interface IAppWithoutFallback {
    /// (required) call on the destination chain to exec the interaction
    function anyExecute(bytes calldata _data)
        external
        returns (bool success, bytes memory result);
}
