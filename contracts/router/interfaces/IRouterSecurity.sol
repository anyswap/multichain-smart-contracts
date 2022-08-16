// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "./SwapInfo.sol";

interface IRouterSecurity {
    function registerSwapin(string calldata swapID, SwapInfo calldata swapInfo)
        external;

    function registerSwapout(
        address token,
        address from,
        string calldata to,
        uint256 amount,
        uint256 toChainID,
        string calldata anycallProxy,
        bytes calldata data
    ) external returns (bytes32 swapoutID);

    function isSwapCompleted(
        string calldata swapID,
        bytes32 swapoutID,
        uint256 fromChainID
    ) external view returns (bool);
}
