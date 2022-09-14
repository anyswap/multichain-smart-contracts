// SPDX-License-Identifier: GPL-3.0-or-later

import "./MPCAdminControl.sol";
import "./PausableControl.sol";

pragma solidity ^0.8.10;

abstract contract MPCAdminPausableControl is MPCAdminControl, PausableControl {
    constructor(address _admin, address _mpc) MPCAdminControl(_admin, _mpc) {}

    function pause(bytes32 role) external onlyAdmin {
        _pause(role);
    }

    function unpause(bytes32 role) external onlyAdmin {
        _unpause(role);
    }
}
