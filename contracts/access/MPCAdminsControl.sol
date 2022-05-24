// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../access/MPCManageable.sol";

// a basic control for a mpc and multiple admins
abstract contract MPCAdminsControl is MPCManageable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private admins;

    constructor(address _mpc) MPCManageable(_mpc) {
        admins.add(_mpc);
    }

    modifier onlyAdmin() {
        require(admins.contains(msg.sender), "MPCAdminsControl: only admin");
        _;
    }

    function isAdmin(address _caller) external view returns (bool) {
        return admins.contains(_caller);
    }

    function getAdminsCount() external view returns (uint256) {
        return admins.length();
    }

    function getAdminAtIndex(uint256 index) external view returns (address) {
        return admins.at(index);
    }

    function getAllAdmins() external view returns (address[] memory) {
        return admins.values();
    }

    function addAdmin(address _admin) external onlyMPC {
        admins.add(_admin);
    }

    function removeAdmin(address _admin) external onlyMPC {
        admins.remove(_admin);
    }
}

