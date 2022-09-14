// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../access/MPCAdminPausableControlUpgradeable.sol";
import "../interfaces/IRouterSecurity.sol";

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

contract MultichainV7RouterSecurity is IRouterSecurity, RoleControl {
    bytes32 public constant Pause_Register_Swapin =
        keccak256("Pause_Register_Swapin");
    bytes32 public constant Pause_Register_Swapout =
        keccak256("Pause_Register_Swapout");
    bytes32 public constant Pause_Check_SwapID_Completion =
        keccak256("Pause_Check_SwapID_Completion");
    bytes32 public constant Pause_Check_SwapoutID_Completion =
        keccak256("Pause_Check_SwapoutID_Completion");

    bool private initialized;

    mapping(string => bool) public completedSwapin;
    mapping(bytes32 => mapping(uint256 => bool)) public completedSwapoutID;
    mapping(bytes32 => uint256) public swapoutNonce;

    uint256 public currentSwapoutNonce;
    modifier autoIncreaseSwapoutNonce() {
        currentSwapoutNonce++;
        _;
    }

    modifier checkCompletion(
        string calldata swapID,
        bytes32 swapoutID,
        uint256 fromChainID
    ) {
        require(
            !completedSwapin[swapID] || paused(Pause_Check_SwapID_Completion),
            "swapID is completed"
        );
        require(
            !completedSwapoutID[swapoutID][fromChainID] ||
                paused(Pause_Check_SwapoutID_Completion),
            "swapoutID is completed"
        );
        _;
    }

    constructor() {
        initialized = true;
    }

    function initialize(address _admin, address _mpc) external {
        require(!initialized, "initialized");
        initialized = true;

        _initializeAdmin(_admin);
        _initializeMPC(_mpc);
    }

    function isSwapoutIDExist(bytes32 swapoutID) external view returns (bool) {
        return swapoutNonce[swapoutID] != 0;
    }

    function isSwapCompleted(
        string calldata swapID,
        bytes32 swapoutID,
        uint256 fromChainID
    ) external view returns (bool) {
        return
            completedSwapin[swapID] ||
            completedSwapoutID[swapoutID][fromChainID];
    }

    function registerSwapin(string calldata swapID, SwapInfo calldata swapInfo)
        external
        onlyAuth
        whenNotPaused(Pause_Register_Swapin)
        checkCompletion(swapID, swapInfo.swapoutID, swapInfo.fromChainID)
    {
        completedSwapin[swapID] = true;
        completedSwapoutID[swapInfo.swapoutID][swapInfo.fromChainID] = true;
    }

    function registerSwapout(
        address token,
        address from,
        string calldata to,
        uint256 amount,
        uint256 toChainID,
        string calldata anycallProxy,
        bytes calldata data
    )
        external
        onlyAuth
        whenNotPaused(Pause_Register_Swapout)
        autoIncreaseSwapoutNonce
        returns (bytes32 swapoutID)
    {
        swapoutID = keccak256(
            abi.encode(
                address(this),
                msg.sender,
                token,
                from,
                to,
                amount,
                currentSwapoutNonce,
                toChainID,
                anycallProxy,
                data
            )
        );
        require(!this.isSwapoutIDExist(swapoutID), "swapoutID already exist");
        swapoutNonce[swapoutID] = currentSwapoutNonce;
        return swapoutID;
    }
}
