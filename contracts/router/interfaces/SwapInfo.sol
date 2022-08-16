// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

struct SwapInfo {
    bytes32 swapoutID;
    address token;
    address receiver;
    uint256 amount;
    uint256 fromChainID;
}
