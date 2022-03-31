// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../access/MPCManageable.sol";

interface IRouter {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function withdrawVault(address from, uint amount, address to) external returns (uint);

}

interface IUnderlying {
    function underlying() external view returns (address);

    function deposit(uint256 amount, address to) external returns (uint256);

    function withdraw(uint256 amount, address to) external returns (uint256);
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

interface IAnycallProxy {
    function exec(
        address token,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result);
}

contract MultichainRouter is MPCManageable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    address public immutable wNATIVE;

    mapping(address => bool) public supportedAnycallProxy;
    mapping(bytes32 => bool) public swapinExisted;

    event LogAnySwapIn(
        bytes32 indexed txhash,
        address indexed token,
        address indexed to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID
    );
    event LogAnySwapOut(
        address indexed token,
        address indexed from,
        address indexed to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID
    );
    event LogAnySwapOut(
        address indexed token,
        address indexed from,
        string to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID
    );

    event LogAnySwapInAndExec(
        bytes32 indexed txhash,
        address indexed token,
        address indexed receiver,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID,
        bool success,
        bytes result
    );
    event LogAnySwapOutAndCall(
        address indexed token,
        address indexed from,
        string to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID,
        string anycallProxy,
        bytes data
    );

    constructor(
        address _mpc,
        address _wNATIVE,
        address[] memory _anycallProxies
    ) MPCManageable(_mpc) {
        wNATIVE = _wNATIVE;
        for(uint256 i = 0; i < _anycallProxies.length; i++) {
            supportedAnycallProxy[_anycallProxies[i]] = true;
        }
    }

    receive() external payable {
        assert(msg.sender == wNATIVE); // only accept Native via fallback from the wNative contract
    }

    function addAnycallProxies(address[] memory proxies) external onlyMPC {
        for(uint256 i = 0; i < proxies.length; i++) {
            supportedAnycallProxy[proxies[i]] = true;
        }
    }

    function removeAnycallProxies(address[] memory proxies) external onlyMPC {
        for(uint256 i = 0; i < proxies.length; i++) {
            supportedAnycallProxy[proxies[i]] = false;
        }
    }

    function changeVault(address token, address newVault)
        external
        onlyMPC
        returns (bool)
    {
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

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external {
        assert(IRouter(token).burn(msg.sender, amount));
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            amount,
            block.chainid,
            toChainID
        );
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(
        address token,
        string memory to,
        uint256 amount,
        uint256 toChainID
    ) external {
        assert(IRouter(token).burn(msg.sender, amount));
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            amount,
            block.chainid,
            toChainID
        );
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` and call anycall proxy with `data`
    function anySwapOutAndCall(
        address token,
        string memory to,
        uint256 amount,
        uint256 toChainID,
        string memory anycallProxy,
        bytes calldata data
    ) external {
        assert(IRouter(token).burn(msg.sender, amount));
        emit LogAnySwapOutAndCall(
            token,
            msg.sender,
            to,
            amount,
            block.chainid,
            toChainID,
            anycallProxy,
            data
        );
    }

    function _anySwapOutUnderlying(address token, uint256 amount) internal returns (uint256) {
        address _underlying = IUnderlying(token).underlying();
        require(_underlying != address(0), "MultichainRouter: zero underlying");
        uint256 old_balance = IERC20(_underlying).balanceOf(token);
        IERC20(_underlying).safeTransferFrom(msg.sender, token, amount);
        uint256 new_balance = IERC20(_underlying).balanceOf(token);
        return new_balance > old_balance ? new_balance - old_balance : 0;
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying`
    function anySwapOutUnderlying(
        address token,
        address to,
        uint256 amount,
        uint256 toChainID
    ) external {
        uint256 recvAmount = _anySwapOutUnderlying(token, amount);
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            recvAmount,
            block.chainid,
            toChainID
        );
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying`
    function anySwapOutUnderlying(
        address token,
        string memory to,
        uint256 amount,
        uint256 toChainID
    ) external {
        uint256 recvAmount = _anySwapOutUnderlying(token, amount);
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            recvAmount,
            block.chainid,
            toChainID
        );
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying` and call anycall proxy with `data`
    function anySwapOutUnderlyingAndCall(
        address token,
        string memory to,
        uint256 amount,
        uint256 toChainID,
        string memory anycallProxy,
        bytes calldata data
    ) external {
        uint256 recvAmount = _anySwapOutUnderlying(token, amount);
        emit LogAnySwapOutAndCall(
            token,
            msg.sender,
            to,
            recvAmount,
            block.chainid,
            toChainID,
            anycallProxy,
            data
        );
    }

    function _anySwapOutNative(address token) internal {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        IwNATIVE(wNATIVE).deposit{value: msg.value}();
        assert(IwNATIVE(wNATIVE).transfer(token, msg.value));
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(
        address token,
        address to,
        uint256 toChainID
    ) external payable {
        _anySwapOutNative(token);
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            msg.value,
            block.chainid,
            toChainID
        );
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(
        address token,
        string memory to,
        uint256 toChainID
    ) external payable {
        _anySwapOutNative(token);
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            msg.value,
            block.chainid,
            toChainID
        );
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to` and call anycall proxy with `data`
    function anySwapOutNativeAndCall(
        address token,
        string memory to,
        uint256 toChainID,
        string memory anycallProxy,
        bytes calldata data
    ) external payable {
        _anySwapOutNative(token);
        emit LogAnySwapOutAndCall(
            token,
            msg.sender,
            to,
            msg.value,
            block.chainid,
            toChainID,
            anycallProxy,
            data
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapIn(
        bytes32 txs,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        swapinExisted[txs] = true;
        assert(IRouter(token).mint(to, amount));
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlying(
        bytes32 txs,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        swapinExisted[txs] = true;
        require(
            IUnderlying(token).underlying() != address(0),
            "MultichainRouter: zero underlying"
        );
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, to);
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `Native`
    function anySwapInNative(
        bytes32 txs,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        swapinExisted[txs] = true;
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, address(this));
        IwNATIVE(wNATIVE).withdraw(amount);
        Address.sendValue(payable(to), amount);
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying` or `Native` if possible
    function anySwapInAuto(
        bytes32 txs,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        swapinExisted[txs] = true;
        address _underlying = IUnderlying(token).underlying();
        if (
            _underlying != address(0) &&
            IERC20(_underlying).balanceOf(token) >= amount
        ) {
            assert(IRouter(token).mint(address(this), amount));
            if (_underlying == wNATIVE) {
                IUnderlying(token).withdraw(amount, address(this));
                IwNATIVE(wNATIVE).withdraw(amount);
                Address.sendValue(payable(to), amount);
            } else {
                IUnderlying(token).withdraw(amount, to);
            }
        } else {
            assert(IRouter(token).mint(to, amount));
        }
        emit LogAnySwapIn(txs, token, to, amount, fromChainID, block.chainid);
    }

    function atomicSwapInAndExec(
        address token,
        address receiver,
        uint256 amount,
        address anycallProxy,
        bytes calldata data,
        bool useUnderlying
    ) external returns (bool success, bytes memory result) {
        require(msg.sender == address(this), "forbid atomic call");
        if (useUnderlying) {
            assert(IRouter(token).mint(address(this), amount));
            IUnderlying(token).withdraw(amount, anycallProxy);
            return IAnycallProxy(anycallProxy).exec(IUnderlying(token).underlying(), receiver, amount, data);
        }
        assert(IRouter(token).mint(anycallProxy, amount));
        return IAnycallProxy(anycallProxy).exec(token, receiver, amount, data);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapInAndExec(
        bytes32 txs,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        require(supportedAnycallProxy[anycallProxy], "unsupported ancall proxy");
        swapinExisted[txs] = true;

        bool success;
        bytes memory result;
        try this.atomicSwapInAndExec(token, receiver, amount, anycallProxy, data, false)
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {
            assert(IRouter(token).mint(receiver, amount));
            success = true;
        }

        emit LogAnySwapInAndExec(
            txs,
            token,
            receiver,
            amount,
            fromChainID,
            block.chainid,
            success,
            result
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlyingAndExec(
        bytes32 txs,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data
    ) external nonReentrant onlyMPC {
        require(!swapinExisted[txs], "swapin existed");
        require(supportedAnycallProxy[anycallProxy], "unsupported ancall proxy");
        swapinExisted[txs] = true;

        address _underlying = IUnderlying(token).underlying();
        require(_underlying != address(0), "MultichainRouter: zero underlying");

        bool success;
        bytes memory result;
        try this.atomicSwapInAndExec(token, receiver, amount, anycallProxy, data, true)
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {
            if (IERC20(_underlying).balanceOf(token) >= amount) {
                assert(IRouter(token).mint(address(this), amount));
                IUnderlying(token).withdraw(amount, receiver);
            } else {
                assert(IRouter(token).mint(receiver, amount));
            }
            success = true;
        }

        emit LogAnySwapInAndExec(
            txs,
            token,
            receiver,
            amount,
            fromChainID,
            block.chainid,
            success,
            result
        );
    }

    // Deposit `msg.value` `Native` to `token` address and mint `msg.value` `token` to `to`
    function depositNative(address token, address to)
        external
        payable
        returns (uint256)
    {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        IwNATIVE(wNATIVE).deposit{value: msg.value}();
        assert(IwNATIVE(wNATIVE).transfer(token, msg.value));
        assert(IRouter(token).mint(to, msg.value));
        return msg.value;
    }

    // Withdraw `amount` `Native` from `token` address to `to` (need approve)
    function withdrawNative(
        address token,
        uint256 amount,
        address to
    ) external nonReentrant returns (uint256) {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );

        uint256 old_balance = IERC20(wNATIVE).balanceOf(address(this));
        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);
        IUnderlying(token).withdraw(amount, address(this));
        uint256 new_balance = IERC20(wNATIVE).balanceOf(address(this));
        assert(new_balance == old_balance + amount);

        IwNATIVE(wNATIVE).withdraw(amount);
        Address.sendValue(payable(to), amount);
        return amount;
    }

    // extracts mpc fee from bridge fees
    function anySwapFeeTo(address token, uint amount) external onlyMPC {
        IRouter(token).mint(msg.sender, amount);
        IRouter(token).withdrawVault(msg.sender, amount, msg.sender);
    }
}
