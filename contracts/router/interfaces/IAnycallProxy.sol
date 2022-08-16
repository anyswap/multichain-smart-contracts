// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

interface IAnycallProxy {
    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result);
}
