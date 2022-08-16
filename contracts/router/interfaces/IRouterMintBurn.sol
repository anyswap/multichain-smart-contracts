// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

interface IRouterMintBurn {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);
}
