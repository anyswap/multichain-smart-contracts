// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";


library TokenOperation {
    using Address for address;

    function safeMint(
        address token,
        address to,
        uint256 value
    ) internal {
        // mint(address,uint256)
        _callOptionalReturn(token, abi.encodeWithSelector(0x40c10f19, to, value));
    }

    function safeBurnAny(
        address token,
        address from,
        uint256 value
    ) internal {
        // burn(address,uint256)
        _callOptionalReturn(token, abi.encodeWithSelector(0x9dc29fac, from, value));
    }

    function safeBurnSelf(
        address token,
        uint256 value
    ) internal {
        // burn(uint256)
        _callOptionalReturn(token, abi.encodeWithSelector(0x42966c68, msg.sender, value));
    }

    function safeBurnFrom(
        address token,
        address from,
        uint256 value
    ) internal {
        // burnFrom(address,uint256)
        _callOptionalReturn(token, abi.encodeWithSelector(0x79cc6790, from, value));
    }

    function _callOptionalReturn(address token, bytes memory data) private {
        bytes memory returndata = token.functionCall(data, "TokenOperation: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "TokenOperation: did not succeed");
        }
    }
}

interface IBridge {
    function Swapin(bytes32 txhash, address account, uint256 amount) external returns (bool);
    function Swapout(uint256 amount, address bindaddr) external returns (bool);

    event LogSwapin(bytes32 indexed txhash, address indexed account, uint256 amount);
    event LogSwapout(address indexed account, address indexed bindaddr, uint256 amount);
}

interface IRouter {
    function mint(address to, uint256 amount) external returns (bool);
    function burn(address from, uint256 amount) external returns (bool);
}

contract MintBurnWrapper is AccessControlEnumerable, IBridge, IRouter {
    using SafeERC20 for IERC20;

    struct Supply {
        uint256 max; // single limit of each mint
        uint256 cap; // total limit of all mint
        uint256 total; // total minted minus burned
    }

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    mapping(address => Supply) public minterSupply;

    bool public mintPaused; // pause all mint calling
    bool public burnPaused; // pause all burn calling

    enum TokenType {
        MintBurnAny,  // mint and burn(address from, uint256 amount), don't need approve
        MintBurnFrom, // mint and burnFrom(address from, uint256 amount), need approve
        MintBurnSelf, // mint and burn(uint256 amount), call transferFrom first, need approve
        Transfer      // transfer and transferFrom, need approve
    }

    address public immutable token; // the target token this contract is wrapping
    TokenType public immutable tokenType;

    constructor(address _token, TokenType _tokenType, address _admin) {
        require(_token != address(0), "zero token address");
        require(_admin != address(0), "zero admin address");
        token = _token;
        tokenType = _tokenType;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function owner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    function _mint(address to, uint256 amount) internal {
        require(to != address(this), "forbid mint to address(this)");
        require(!mintPaused, "mint paused");
        Supply storage s = minterSupply[msg.sender];
        require(amount <= s.max, "minter upper bound exceeded");
        s.total += amount;
        require(s.total <= s.cap, "minter cap exceeded");

        if (tokenType == TokenType.Transfer) {
            IERC20(token).safeTransfer(to, amount);
        } else {
            TokenOperation.safeMint(token, to, amount);
        }
    }

    function _burn(address from, uint256 amount) internal {
        require(from != address(this), "forbid burn from address(this)");
        require(!burnPaused, "burn paused");
        Supply storage s = minterSupply[msg.sender];
        s.total -= amount;

        if (tokenType == TokenType.Transfer) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
        } else if (tokenType == TokenType.MintBurnAny) {
            TokenOperation.safeBurnAny(token, from, amount);
        } else if (tokenType == TokenType.MintBurnFrom) {
            TokenOperation.safeBurnFrom(token, from, amount);
        } else if (tokenType == TokenType.MintBurnSelf) {
            IERC20(token).safeTransferFrom(from, address(this), amount);
            TokenOperation.safeBurnSelf(token, amount);
        }
    }

    // impl IRouter `mint`
    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _mint(to, amount);
        return true;
    }

    // impl IRouter `burn`
    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _burn(from, amount);
        return true;
    }

    // impl IBridge `Swapin`
    function Swapin(bytes32 txhash, address account, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    // impl IBridge `Swapout`
    function Swapout(uint256 amount, address bindaddr) public returns (bool) {
        require(bindaddr != address(0), "zero bind address");
        _burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    function setMinterCap(address minter, uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minterSupply[minter].cap = cap;
    }

    function setMinterMax(address minter, uint256 max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        minterSupply[minter].max = max;
    }

    function setMintPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPaused = paused;
    }

    function setBurnPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        burnPaused = paused;
    }

    function setMintAndBurnPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        mintPaused = paused;
        burnPaused = paused;
    }
}

