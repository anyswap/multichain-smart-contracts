// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../common/UpgradableProxy.sol";

contract MultichainV7RouterSecurityProxy is UpgradableProxy {
    constructor(address _roterSecurityUpgradeable)
        UpgradableProxy(_roterSecurityUpgradeable)
    {}
}
