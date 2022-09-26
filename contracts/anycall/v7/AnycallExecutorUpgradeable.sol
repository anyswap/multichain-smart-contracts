// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../access/MPCAdminPausableControlUpgradeable.sol";
import "./interfaces/IApp.sol";
import "./interfaces/IAnycallExecutor.sol";

abstract contract RoleControl is MPCAdminPausableControlUpgradeable {
    mapping(address => bool) public isSupportedCaller;
    address[] public supportedCallers;

    modifier onlyAuth() {
        require(isSupportedCaller[msg.sender], "not supported caller");
        _;
    }

    function getAllSupportedCallers() external view returns (address[] memory) {
        return supportedCallers;
    }

    function addSupportedCaller(address caller) external onlyAdmin {
        require(!isSupportedCaller[caller]);
        isSupportedCaller[caller] = true;
        supportedCallers.push(caller);
    }

    function removeSupportedCaller(address caller) external onlyAdmin {
        require(isSupportedCaller[caller]);
        isSupportedCaller[caller] = false;
        uint256 length = supportedCallers.length;
        for (uint256 i = 0; i < length; i++) {
            if (supportedCallers[i] == caller) {
                supportedCallers[i] = supportedCallers[length - 1];
                supportedCallers.pop();
                return;
            }
        }
    }
}

/// anycall executor is the delegator to execute contract calling (like a sandbox)
contract AnycallExecutorUpgradeable is IAnycallExecutor, RoleControl {
    struct Context {
        address from;
        uint256 fromChainID;
        uint256 nonce;
    }

    Context public override context;

    constructor() {
        _disableInitializers();
    }

    function initialize(address _admin, address _mpc) external initializer {
        __AdminControl_init(_admin);
        __MPCManageable_init(_mpc);
    }

    // @dev `_extdata` content is implementation based in each version
    function execute(
        address _to,
        bytes calldata _data,
        address _from,
        uint256 _fromChainID,
        uint256 _nonce,
        bytes calldata _extdata
    )
        external
        virtual
        override
        onlyAuth
        whenNotPaused(PAUSE_ALL_ROLE)
        returns (bool success, bytes memory result)
    {
        bool isFallback = _extdata.length > 0 && abi.decode(_extdata, (bool));

        context = Context({
            from: _from,
            fromChainID: _fromChainID,
            nonce: _nonce
        });

        if (!isFallback) {
            (success, result) = IApp(_to).anyExecute(_data);
        } else {
            (success, result) = IApp(_to).anyFallback(_data);
        }

        context = Context({from: address(0), fromChainID: 0, nonce: 0});
    }
}
