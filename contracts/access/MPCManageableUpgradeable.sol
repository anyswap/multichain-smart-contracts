// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

abstract contract MPCManageableUpgradeable {
    address public mpc;
    address public pendingMPC;

    uint256 public constant delay = 2 days;
    uint256 public delayMPC;

    modifier onlyMPC() {
        require(msg.sender == mpc, "MPC: only mpc");
        _;
    }

    event LogChangeMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 effectiveTime
    );
    event LogApplyMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 applyTime
    );

    function _initializeMPC(address _mpc) internal {
        require(_mpc != address(0), "MPC: mpc is the zero address");
        mpc = _mpc;
        emit LogChangeMPC(address(0), mpc, block.timestamp);
    }

    function changeMPC(address _mpc) external onlyMPC {
        require(_mpc != address(0), "MPC: mpc is the zero address");
        pendingMPC = _mpc;
        delayMPC = block.timestamp + delay;
        emit LogChangeMPC(mpc, pendingMPC, delayMPC);
    }

    // only the `pendingMPC` can `apply`
    // except when `pendingMPC` is a contract, then `mpc` can also `apply`
    // in case `pendingMPC` has no `apply` wrapper method and cannot `apply`
    function applyMPC() external {
        require(
            msg.sender == pendingMPC ||
                (msg.sender == mpc && address(pendingMPC).code.length > 0),
            "MPC: only pending mpc"
        );
        require(
            delayMPC > 0 && block.timestamp >= delayMPC,
            "MPC: time before delayMPC"
        );
        emit LogApplyMPC(mpc, pendingMPC, block.timestamp);
        mpc = pendingMPC;
        pendingMPC = address(0);
        delayMPC = 0;
    }
}
