// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../access/MPCManageable.sol";

// a basic control for a mpc and multiple admins
abstract contract MPCAdminsControl is MPCManageable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private admins;

    constructor(address _admin, address _mpc) MPCManageable(_mpc) {
        admins.add(_mpc);
        admins.add(_admin);
    }

    modifier onlyAdmin() {
        require(_isAdmin(msg.sender), "MPCAdminsControl: only admin");
        _;
    }

    function isAdmin(address _caller) external view returns (bool) {
        return _isAdmin(_caller);
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
        _addAdmin(_admin);
    }

    function removeAdmin(address _admin) external onlyMPC {
        _removeAdmin(_admin);
    }

    function _isAdmin(address _caller) internal view returns (bool) {
        return admins.contains(_caller);
    }

    function _addAdmin(address _admin) internal {
        admins.add(_admin);
    }

    function _removeAdmin(address _admin) internal {
        admins.remove(_admin);
    }
}
