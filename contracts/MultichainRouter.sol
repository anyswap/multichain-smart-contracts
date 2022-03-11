// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";


interface IRouter {
    function mint(address to, uint256 amount) external returns (bool);
    function burn(address from, uint256 amount) external returns (bool);
}

interface IUnderlying {
    function underlying() external view returns (address);
    function deposit(uint amount, address to) external returns (uint);
    function withdraw(uint amount, address to) external returns (uint);
}

interface IAnyswapERC20Auth {
    function changeVault(address newVault) external returns (bool);
    function setVault(address vault) external;
    function applyVault() external;
    function setMinter(address minter) external;
    function applyMinter() external;
    function revokeMinter(address minter) external;
}

interface IwNATIVE {
    function deposit() external payable;
    function withdraw(uint256) external;
    function transfer(address to, uint256 value) external returns (bool);
}

interface ITradeProxy {
    function trade(bytes calldata data) external returns (bool sucess, bytes memory result);
}

interface IFeeCalc {
    function calcFee(address token, address sender, uint256 amount) external returns (uint256 fee);
}

abstract contract MPCManageable {
    using Address for address;

    address public mpc;
    address public pendingMPC;

    uint256 public constant delay = 2 days;
    uint256 public delayMPC;

    modifier onlyMPC() {
        require(msg.sender == mpc, "MPC: only mpc");
        _;
    }

    event LogChangeMPC(address indexed oldMPC, address indexed newMPC, uint256 effectiveTime);
    event LogApplyMPC(address indexed oldMPC, address indexed newMPC, uint256 applyTime);

    constructor(address _mpc) {
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

    function applyMPC() external {
        require(
            msg.sender == pendingMPC ||
            (msg.sender == mpc && address(pendingMPC).isContract()),
            "MPC: only pending mpc"
        );
        require(delayMPC > 0 && block.timestamp >= delayMPC, "MPC: time before delayMPC");
        emit LogApplyMPC(mpc, pendingMPC, block.timestamp);
        mpc = pendingMPC;
        pendingMPC = address(0);
        delayMPC = 0;
    }
}

contract MultichainRouter is MPCManageable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    address public tradeProxy;
    address public feeCalc;
    address public immutable wNATIVE;

    event LogAnySwapIn(bytes32 indexed txhash, address indexed token, address indexed to, uint256 amount, uint256 fromChainID, uint256 toChainID);
    event LogAnySwapOut(address indexed token, address indexed from, address indexed to, uint256 amount, uint256 fromChainID, uint256 toChainID);
    event LogAnySwapOut(address indexed token, address indexed from, string to, uint256 amount, uint256 fromChainID, uint256 toChainID);

    event LogAnySwapInAndExec(bytes32 indexed txhash, address indexed token, address indexed to, uint256 amount, uint256 fromChainID, uint256 toChainID, bool success, bytes result);
    event LogAnySwapOutAndCall(address indexed token, address indexed from, address indexed to, uint256 amount, uint256 fromChainID, uint256 toChainID, bytes data);
    event LogAnySwapOutAndCall(address indexed token, address indexed from, string to, uint256 amount, uint256 fromChainID, uint256 toChainID, bytes data);

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, 'MultichainRouter: expired');
        _;
    }

    constructor(address _tradeProxy, address _feeCalc, address _wNATIVE, address _mpc) MPCManageable(_mpc) {
        tradeProxy = _tradeProxy;
        feeCalc = _feeCalc;
        wNATIVE = _wNATIVE;
    }

    function setTradeProxy(address _tradeProxy) external onlyMPC {
        tradeProxy = _tradeProxy;
    }

    function setFeeCalc(address _feeCalc) external onlyMPC {
        feeCalc = _feeCalc;
    }

    function changeVault(address token, address newVault) public onlyMPC returns (bool) {
        return IAnyswapERC20Auth(token).changeVault(newVault);
    }

    function setVault(address token, address vault) external onlyMPC {
        return IAnyswapERC20Auth(token).setVault(vault);
    }

    function applyVault(address token) external onlyMPC {
        return IAnyswapERC20Auth(token).applyVault();
    }

    function setMinter(address token, address minter) external onlyMPC {
        return IAnyswapERC20Auth(token).setMinter(minter);
    }

    function applyMinter(address token) external onlyMPC {
        return IAnyswapERC20Auth(token).applyMinter();
    }

    function revokeMinter(address token, address minter) external onlyMPC {
        return IAnyswapERC20Auth(token).revokeMinter(minter);
    }

    function _calcRecvAmount(address token, address sender, uint256 amount) internal returns (uint256) {
        uint256 fee = IFeeCalc(feeCalc).calcFee(token, sender, amount);
        require(amount >= fee, "MultichainRouter: not enough token fee");
        return amount - fee;
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(address token, address to, uint256 amount, uint256 toChainID) external {
        assert(IRouter(token).burn(msg.sender, amount));
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(address token, string memory to, uint256 amount, uint256 toChainID) external {
        assert(IRouter(token).burn(msg.sender, amount));
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` and call trade proxy with `data`
    function anySwapOutAndCall(address token, string memory to, uint256 amount, uint256 toChainID, bytes calldata data) external {
        assert(IRouter(token).burn(msg.sender, amount));
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOutAndCall(token, msg.sender, to, receiveAmount, block.chainid, toChainID, data);
    }

    function _anySwapOutUnderlying(address token, uint256 amount) internal {
        address _underlying = IUnderlying(token).underlying();
        require(_underlying != address(0), "zero underlying");
        IERC20(_underlying).safeTransferFrom(msg.sender, token, amount);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying`
    function anySwapOutUnderlying(address token, address to, uint256 amount, uint256 toChainID) external {
        _anySwapOutUnderlying(token, amount);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying`
    function anySwapOutUnderlying(address token, string memory to, uint256 amount, uint256 toChainID) external {
        _anySwapOutUnderlying(token, amount);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying` and call trade proxy with `data`
    function anySwapOutUnderlyingAndCall(address token, string memory to, uint256 amount, uint256 toChainID, bytes calldata data) external {
        _anySwapOutUnderlying(token, amount);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, amount);
        emit LogAnySwapOutAndCall(token, msg.sender, to, receiveAmount, block.chainid, toChainID, data);
    }

    function _anySwapOutNative(address token) internal {
        require(wNATIVE != address(0), "zero wNATIVE");
        require(IUnderlying(token).underlying() == wNATIVE, "MultichainRouter: underlying is not wNATIVE");
        IwNATIVE(wNATIVE).deposit{value: msg.value}();
        assert(IwNATIVE(wNATIVE).transfer(token, msg.value));
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(address token, address to, uint256 toChainID) external payable {
        _anySwapOutNative(token);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, msg.value);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(address token, string memory to, uint256 toChainID) external payable {
        _anySwapOutNative(token);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, msg.value);
        emit LogAnySwapOut(token, msg.sender, to, receiveAmount, block.chainid, toChainID);
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to` and call trade proxy with `data`
    function anySwapOutNativeAndCall(address token, string memory to, uint256 toChainID, bytes calldata data) external payable {
        _anySwapOutNative(token);
        uint256 receiveAmount = _calcRecvAmount(token, msg.sender, msg.value);
        emit LogAnySwapOutAndCall(token, msg.sender, to, receiveAmount, block.chainid, toChainID, data);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapIn(bytes32 txs, address token, address to, uint256 amount, uint256 fromChainID) external nonReentrant onlyMPC {
        assert(IRouter(token).mint(msg.sender, amount));
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlying(bytes32 txs, address token, address to, uint256 amount, uint256 fromChainID) external nonReentrant onlyMPC {
        require(IUnderlying(token).underlying() != address(0), "zero underlying");
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, to);
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `Native`
    function anySwapInNative(bytes32 txs, address token, address to, uint256 amount, uint256 fromChainID) external nonReentrant onlyMPC {
        require(wNATIVE != address(0), "zero wNATIVE");
        require(IUnderlying(token).underlying() == wNATIVE, "MultichainRouter: underlying is not wNATIVE");
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, address(this));
        IwNATIVE(wNATIVE).withdraw(amount);
        Address.sendValue(payable(to), amount);
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying` or `Native` if possible
    function anySwapInAuto(bytes32 txs, address token, address to, uint256 amount, uint256 fromChainID) external nonReentrant onlyMPC {
        address _underlying = IUnderlying(token).underlying();
        if (_underlying != address(0) && IERC20(_underlying).balanceOf(token) >= amount) {
            assert(IRouter(token).mint(address(this), amount));
            if (_underlying == wNATIVE) {
                IUnderlying(token).withdraw(amount, address(this));
                IwNATIVE(wNATIVE).withdraw(amount);
                Address.sendValue(payable(to), amount);
            } else {
                IUnderlying(token).withdraw(amount, to);
            }
        } else {
            assert(IRouter(token).mint(msg.sender, amount));
        }
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapInAndExec(bytes32 txs, address token, address to, uint256 amount, uint256 fromChainID, bytes calldata data) external nonReentrant onlyMPC {
        require(msg.sender != tradeProxy, "forbid call swapin from tradeProxy");
        assert(IRouter(token).mint(msg.sender, amount));
        (bool sucess, bytes memory result) = ITradeProxy(tradeProxy).trade(data);
        emit LogAnySwapInAndExec(txs, token, to, amount, fromChainID, block.chainid, sucess, result);
    }

    // Deposit `msg.value` `Native` to `token` address and mint `msg.value` `token` to `to`
    function depositNative(address token, address to) external payable returns (uint256) {
        require(wNATIVE != address(0), "zero wNATIVE");
        require(IUnderlying(token).underlying() == wNATIVE, "MultichainRouter: underlying is not wNATIVE");
        IwNATIVE(wNATIVE).deposit{value: msg.value}();
        assert(IwNATIVE(wNATIVE).transfer(token, msg.value));
        assert(IRouter(token).mint(to, msg.value));
        return msg.value;
    }

    // Withdraw `amount` `Native` from `token` address to `to`
    function withdrawNative(address token, uint256 amount, address to) external nonReentrant returns (uint256) {
        require(wNATIVE != address(0), "zero wNATIVE");
        require(IUnderlying(token).underlying() == wNATIVE, "MultichainRouter: underlying is not wNATIVE");
        IUnderlying(token).withdraw(amount, address(this));
        IwNATIVE(wNATIVE).withdraw(amount);
        Address.sendValue(payable(to), amount);
        return amount;
    }
}
