// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
import "../access/MPCManageable.sol";

/// IAnycallProxy interface of the anycall proxy
interface IAnycallProxy {
    function exec(
        address _token,
        address _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);
}

/// IAnycallExecutor interface of the anycall executor
interface IAnycallExecutor {
    function execute(
        address _anycallProxy,
        address _token,
        address _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);
}

/// anycall executor is the delegator to execute contract calling (like a sandbox)
contract AnycallExecutor is IAnycallExecutor, MPCManageable {
    using EnumerableSet for EnumerableSet.AddressSet;
    EnumerableSet.AddressSet private authCallers;

    modifier onlyAuthCaller() {
        require(authCallers.contains(msg.sender), "only auth");
        _;
    }

    constructor(address _mpc) MPCManageable(_mpc) {}

    function isAuthCaller(address _caller) external view returns (bool) {
        return authCallers.contains(_caller);
    }

    function getAuthCallersCount() external view returns (uint256) {
        return authCallers.length();
    }

    function getAuthCallerAtIndex(uint256 index) external view returns (address) {
        return authCallers.at(index);
    }

    function getAllAuthCallers() external view returns (address[] memory) {
        return authCallers.values();
    }

    function addSupportedCaller(address[] calldata _callers) external onlyMPC {
        for(uint256 i = 0; i < _callers.length; i++) {
            authCallers.add(_callers[i]);
        }
    }

    function removeSupportedCaller(address[] calldata _callers) external onlyMPC {
        for(uint256 i = 0; i < _callers.length; i++) {
            authCallers.remove(_callers[i]);
        }
    }

    function execute(
        address _anycallProxy,
        address _token,
        address _receiver,
        uint256 _amount,
        bytes calldata _data
    ) external onlyAuthCaller returns (bool success, bytes memory result) {
        return IAnycallProxy(_anycallProxy).exec(_token, _receiver, _amount, _data);
    }
}
