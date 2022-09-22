// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../common/TransparentUpgradeableProxy.sol";

contract AnycallV7Proxy is TransparentUpgradeableProxy {
    constructor(
        address _anycall,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_anycall, admin_, _data) {}
}
