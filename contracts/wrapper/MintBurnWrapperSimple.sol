// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../access/AdminControl.sol";

// TokenType token type enumerations (*required* by the multichain front-end)
// When in `need approve` situations, the user should approve to this wrapper contract,
// not to the Router contract, and not to the target token to be wrapped.
// If not, this wrapper will fail its function.
enum TokenType {
    MintBurnAny, // mint and burn(address from, uint256 amount), don't need approve
    MintBurnFrom, // mint and burnFrom(address from, uint256 amount), need approve
    MintBurnSelf, // mint and burn(uint256 amount), call transferFrom first, need approve
    Transfer, // transfer and transferFrom, need approve
    TransferDeposit, // transfer and transferFrom, deposit and withdraw, need approve, block when lack of liquidity
    TransferDeposit2 // transfer and transferFrom, deposit and withdraw, need approve, don't block when lack of liquidity
}

// IRouterMintBurn interface required for Multichain Router Dapp
// `mint` and `burn` is required by the router contract
// `token` and `tokenType` is required by the front-end
// Notice: the parameters and return type should be same
interface IRouterMintBurn {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function token() external view returns (address);

    function tokenType() external view returns (TokenType);
}

// ITokenMintBurn is the interface the target token to be wrapped actually supports.
// We should adjust these functions according to the token itself,
// and wrapper them to support `IRouterMintBurn`
// Notice: the parameters and return type should be same
interface ITokenMintBurn {
    function mint(address to, uint256 amount) external returns (bool);

    function burnFrom(address from, uint256 amount) external returns (bool);
}

// RoleControl has a `admin` (the primary controller)
// and a set of `minters` (can be this bridge or other bridges)
abstract contract RoleControl is AdminControl {
    mapping(address => bool) public isMinter;

    modifier onlyAuth() {
        require(isMinter[msg.sender], "onlyAuth");
        _;
    }

    event AddMinter(address _minter);
    event RevokeMinter(address _minter);

    constructor(address _admin) AdminControl(_admin) {}

    function addMinter(address _minter) external onlyAdmin {
        require(_minter != address(0), "zero minter address");
        require(!isMinter[_minter], "minter exists");
        isMinter[_minter] = true;
        emit AddMinter(_minter);
    }

    function revokeMinter(address _minter) external onlyAdmin {
        require(isMinter[_minter], "minter not exists");
        isMinter[_minter] = false;
        emit RevokeMinter(_minter);
    }
}

// MintBurnWrapperSimple is a wrapper for token that supports `ITokenMintBurn` to support `IRouterMintBurn`
// This is a simple wrapper without any security enhancement controls (eg. mint cap, pausable, etc.)
contract MintBurnWrapperSimple is IRouterMintBurn, RoleControl {
    // the target token to be wrapped, must support `ITokenMintBurn`
    address public immutable override token;
    // token type should be consistent with the `TokenType` context
    TokenType public constant override tokenType = TokenType.MintBurnFrom;

    constructor(address _token, address _admin) RoleControl(_admin) {
        require(
            _token != address(0) && _token != address(this),
            "zero token address"
        );
        token = _token;
    }

    function mint(address to, uint256 amount)
        external
        override
        onlyAuth
        returns (bool)
    {
        assert(ITokenMintBurn(token).mint(to, amount));
        return true;
    }

    function burn(address from, uint256 amount)
        external
        override
        onlyAuth
        returns (bool)
    {
        assert(ITokenMintBurn(token).burnFrom(from, amount));
        return true;
    }
}
