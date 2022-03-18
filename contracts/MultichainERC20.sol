// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Capped.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/draft-ERC20Permit.sol";
import "@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract MultichainERC20 is ERC20Capped, ERC20Burnable, ERC20Permit, AccessControlEnumerable {
    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    struct Supply {
        uint256 max; // single limit of each mint
        uint256 cap; // total limit of all mint
        uint256 total; // total minted minus burned
    }

    mapping(address => Supply) public minterSupply;

    // switches to control minters' mint and burn action
    bool public allMintPaused; // pause all minters' mint calling
    bool public allBurnPaused; // pause all minters' burn calling (normal user is not paused)
    mapping(address => bool) public mintPaused; // pause specify minters' mint calling
    mapping(address => bool) public burnPaused; // pause specify minters' burn calling

    uint8 immutable _tokenDecimals;

    event LogSwapin(bytes32 indexed txhash, address indexed account, uint256 amount);
    event LogSwapout(address indexed account, address indexed bindaddr, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _cap,
        address _admin
    )
    ERC20(_name, _symbol)
    ERC20Capped(_cap)
    ERC20Permit(_name)
    {
        _tokenDecimals = _decimals;
        _grantRole(DEFAULT_ADMIN_ROLE, _admin);
    }

    function getOwner() external view returns (address) {
        return getRoleMember(DEFAULT_ADMIN_ROLE, 0);
    }

    function decimals() public view virtual override returns (uint8) {
        return _tokenDecimals;
    }

    function underlying() external view virtual returns (address) {
        return address(0);
    }

    function _mint(address to, uint256 amount) internal virtual override(ERC20, ERC20Capped) {
        require(to != address(this), "forbid mint to address(this)");
        require(!allMintPaused && !mintPaused[msg.sender], "mint paused");
        Supply storage s = minterSupply[msg.sender];
        require(amount <= s.max, "minter max exceeded");
        s.total += amount;
        require(s.total <= s.cap, "minter cap exceeded");

        super._mint(to, amount);
    }

    function _burn(address from, uint256 amount) internal virtual override {
        if (hasRole(MINTER_ROLE, msg.sender)) {
            require(from != address(this), "forbid burn from address(this)");
            require(!allBurnPaused && !burnPaused[msg.sender], "burn paused");
            Supply storage s = minterSupply[msg.sender];
            require(s.total >= amount, "minter burn amount exceeded");
            s.total -= amount;
        }

        super._burn(from, amount);
    }

    function mint(address to, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _mint(to, amount);
        return true;
    }

    function burn(address from, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _burn(from, amount);
        return true;
    }

    function Swapin(bytes32 txhash, address account, uint256 amount) external onlyRole(MINTER_ROLE) returns (bool) {
        _mint(account, amount);
        emit LogSwapin(txhash, account, amount);
        return true;
    }

    function Swapout(uint256 amount, address bindaddr) external returns (bool) {
        require(bindaddr != address(0), "zero bind address");
        super._burn(msg.sender, amount);
        emit LogSwapout(msg.sender, bindaddr, amount);
        return true;
    }

    function addMinter(address minter, uint256 cap, uint256 max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _grantRole(MINTER_ROLE, minter);
        minterSupply[minter].cap = cap;
        minterSupply[minter].max = max;
        mintPaused[minter] = false;
        burnPaused[minter] = false;
    }

    function removeMinter(address minter) external onlyRole(DEFAULT_ADMIN_ROLE) {
        _revokeRole(MINTER_ROLE, minter);
        minterSupply[minter].cap = 0;
        minterSupply[minter].max = 0;
    }

    function setMinterCap(address minter, uint256 cap) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(MINTER_ROLE, minter), "not minter");
        minterSupply[minter].cap = cap;
    }

    function setMinterMax(address minter, uint256 max) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(MINTER_ROLE, minter), "not minter");
        minterSupply[minter].max = max;
    }

    function setMinterTotal(address minter, uint256 total, bool force) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(force || hasRole(MINTER_ROLE, minter), "not minter");
        minterSupply[minter].total = total;
    }

    function setAllMintPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allMintPaused = paused;
    }

    function setAllBurnPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allBurnPaused = paused;
    }

    function setAllMintAndBurnPaused(bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        allMintPaused = paused;
        allBurnPaused = paused;
    }

    function setMintPaused(address minter, bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(MINTER_ROLE, minter), "not minter");
        mintPaused[minter] = paused;
    }

    function setBurnPaused(address minter, bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(MINTER_ROLE, minter), "not minter");
        burnPaused[minter] = paused;
    }

    function setMintAndBurnPaused(address minter, bool paused) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(hasRole(MINTER_ROLE, minter), "not minter");
        mintPaused[minter] = paused;
        burnPaused[minter] = paused;
    }
}

contract MultichainERC20WithUnderlying is MultichainERC20 {
    using SafeERC20 for IERC20;

    address public immutable override underlying;

    event Deposit(address indexed from, address indexed to, uint256 amount);
    event Withdraw(address indexed from, address indexed to, uint256 amount);

    constructor(
        string memory _name,
        string memory _symbol,
        uint8 _decimals,
        uint256 _cap,
        address _admin,
        address _underlying
    ) MultichainERC20(_name, _symbol, _decimals, _cap, _admin) {
        require(_underlying != address(0), "underlying is the zero address");
        require(_underlying != address(this), "underlying is same to address(this)");
        require(_decimals == IERC20Metadata(_underlying).decimals(), "decimals mismatch");

        underlying = _underlying;
    }

    function deposit(uint256 amount) public returns (uint256) {
        return deposit(amount, msg.sender);
    }

    function deposit(uint256 amount, address to) public returns (uint256) {
        IERC20(underlying).safeTransferFrom(msg.sender, address(this), amount);
        _mint(to, amount);
        emit Deposit(msg.sender, to, amount);
        return amount;
    }

    function withdraw(uint256 amount) public returns (uint256) {
        return withdraw(amount, msg.sender);
    }

    function withdraw(uint256 amount, address to) public returns (uint256) {
        _burn(msg.sender, amount);
        IERC20(underlying).safeTransfer(to, amount);
        emit Withdraw(msg.sender, to, amount);
        return amount;
    }
}