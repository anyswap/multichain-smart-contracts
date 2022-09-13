// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../common/TransparentUpgradeableProxy.sol";

contract MultichainV7RouterSecurityProxy is TransparentUpgradeableProxy {
    constructor(
        address _roterSecurity,
        address admin_,
        bytes memory _data
    ) payable TransparentUpgradeableProxy(_roterSecurity, admin_, _data) {}
}
