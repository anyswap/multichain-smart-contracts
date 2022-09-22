// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../common/TransparentUpgradeableProxy.sol";

contract AnycallExecutorProxy is TransparentUpgradeableProxy {
    constructor(
        address _executor,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_executor, admin_, _data) {}
}
