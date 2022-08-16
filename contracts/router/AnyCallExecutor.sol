// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../access/MPCAdminsControl.sol";
import "./interfaces/IAnycallProxy.sol";
import "./interfaces/IAnycallExecutor.sol";

/// anycall executor is the delegator to execute contract calling (like a sandbox)
contract AnycallExecutor is IAnycallExecutor, MPCAdminsControl {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private authCallers;

    modifier onlyAuthCaller() {
        require(authCallers.contains(msg.sender), "only auth");
        _;
    }

    constructor(address _mpc) MPCAdminsControl(_mpc) {}

    function isAuthCaller(address _caller) external view returns (bool) {
        return authCallers.contains(_caller);
    }

    function getAuthCallersCount() external view returns (uint256) {
        return authCallers.length();
    }

    function getAuthCallerAtIndex(uint256 index)
        external
        view
        returns (address)
    {
        return authCallers.at(index);
    }

    function getAllAuthCallers() external view returns (address[] memory) {
        return authCallers.values();
    }

    function addAuthCallers(address[] calldata _callers) external onlyAdmin {
        for (uint256 i = 0; i < _callers.length; i++) {
            authCallers.add(_callers[i]);
        }
    }

    function removeAuthCallers(address[] calldata _callers) external onlyAdmin {
        for (uint256 i = 0; i < _callers.length; i++) {
            authCallers.remove(_callers[i]);
        }
    }

    function execute(
        address _anycallProxy,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external onlyAuthCaller returns (bool success, bytes memory result) {
        return IAnycallProxy(_anycallProxy).exec(_token, _amount, _data);
    }
}
