// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./SwapInfo.sol";

interface IRetrySwapinAndExec {
    function retrySwapinAndExec(
        string calldata swapID,
        SwapInfo calldata swapInfo,
        address anycallProxy,
        bytes calldata data,
        bool dontExec
    ) external;
}
