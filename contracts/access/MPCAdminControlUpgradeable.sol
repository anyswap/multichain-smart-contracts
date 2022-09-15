// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../access/MPCManageableUpgradeable.sol";

abstract contract MPCAdminControlUpgradeable is MPCManageableUpgradeable {
    address public admin;

    event ChangeAdmin(address indexed _old, address indexed _new);

    function _initializeAdmin(address _admin) internal {
        admin = _admin;
        emit ChangeAdmin(address(0), _admin);
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, "MPCAdminControl: not admin");
        _;
    }

    function changeAdmin(address _admin) external onlyMPC {
        emit ChangeAdmin(admin, _admin);
        admin = _admin;
    }
}
