// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

abstract contract PausableControl {
    mapping(bytes32 => bool) private _pausedRoles;
    bool private _pausedAll;
    address public _admin;

    event Paused(bytes32 role, bool flag);
    event PausedAll(bool flag);

    constructor(address admin) {
        _admin = admin;
    }

    modifier onlyAdmin() {
        require(msg.sender == _admin, "PausableControl:not admin");
        _;
    }

    modifier whenNotPaused(bytes32 role) {
        require(!pausedAll(), "PausableControl: all paused");
        require(!paused(role), "PausableControl: paused");
        _;
    }

    modifier whenPaused(bytes32 role) {
        require(pausedAll() || paused(role), "PausableControl: paused");
        _;
    }

    function changeAdmin(address admin_) external onlyAdmin {
        require(_admin != admin_, "PausableControl:admin not change");
        _admin = admin_;
    }

    function paused(bytes32 role) public view virtual returns (bool) {
        return _pausedRoles[role];
    }

    function pausedAll() public view virtual returns (bool) {
        return _pausedAll;
    }

    function pause(bytes32 role) external onlyAdmin whenNotPaused(role) {
        _pause(role, true);
    }

    function _pause(bytes32 role, bool flag) internal {
        _pausedRoles[role] = flag;
        emit Paused(role, flag);
    }

    function _setPauseAll(bool flag) internal {
        _pausedAll = flag;
        emit PausedAll(flag);
    }

    function unPause(bytes32 role) external onlyAdmin whenPaused(role) {
        _pause(role, false);
    }

    function setPauseAll(bool flag) external onlyAdmin {
        require(pausedAll() != flag, "PausableControl: _pausedAll not change");
        _setPauseAll(flag);
    }
}

contract test is PausableControl {
    bytes32 public constant Native_Paused_ROLE =
        keccak256("Native_Paused_ROLE");
    bytes32 public constant Underlying_Paused_ROLE =
        keccak256("Underlying_Paused_ROLE");
    bytes32 public constant Token_Paused_ROLE = keccak256("Token_Paused_ROLE");

    event Test(bytes32 role, uint256 number);

    constructor(address admin) PausableControl(admin) {
        _pause(Native_Paused_ROLE, true);
        // _setPauseAll(true);
    }

    function test_Native_Paused_ROLE(uint256 number)
        public
        whenNotPaused(Native_Paused_ROLE)
    {
        emit Test(Native_Paused_ROLE, number);
    }

    function test_Underlying_Paused_ROLE(uint256 number)
        public
        whenNotPaused(Underlying_Paused_ROLE)
    {
        emit Test(Underlying_Paused_ROLE, number);
    }

    function test_Token_Paused_ROLE(uint256 number)
        public
        whenNotPaused(Token_Paused_ROLE)
    {
        emit Test(Token_Paused_ROLE, number);
    }
}
