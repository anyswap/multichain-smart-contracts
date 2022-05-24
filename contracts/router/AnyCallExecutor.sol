// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

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
    mapping(address => bool) public isAuthCaller;

    modifier onlyAuthCaller() {
        require(isAuthCaller[msg.sender], "only auth");
        _;
    }

    constructor(address _mpc) MPCManageable(_mpc) {}

    function addSupportedCaller(address[] calldata _callers) external onlyMPC {
        address caller;
        for(uint256 i = 0; i < _callers.length; i++) {
            caller = _callers[i];
            require(!isAuthCaller[caller]);
            isAuthCaller[caller] = true;
        }
    }

    function removeSupportedCaller(address[] calldata _callers) external onlyMPC {
        address caller;
        for(uint256 i = 0; i < _callers.length; i++) {
            caller = _callers[i];
            require(!isAuthCaller[caller]);
            isAuthCaller[caller] = false;
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
