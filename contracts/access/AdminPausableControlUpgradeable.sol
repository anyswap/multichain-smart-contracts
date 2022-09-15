// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "./AdminControlUpgradeable.sol";
import "./PausableControl.sol";

abstract contract AdminPausableControlUpgradeable is
    AdminControlUpgradeable,
    PausableControl
{
    function pause(bytes32 role) external onlyAdmin {
        _pause(role);
    }

    function unpause(bytes32 role) external onlyAdmin {
        _unpause(role);
    }
}
