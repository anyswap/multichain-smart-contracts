// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../access/MPCManageable.sol";
import "../access/PausableControlWithAdmin.sol";

interface IRouter {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);
}

interface IUnderlying {
    function underlying() external view returns (address);

    function deposit(uint256 amount, address to) external returns (uint256);

    function withdraw(uint256 amount, address to) external returns (uint256);
}

interface IAnyswapERC20Auth {
    function changeVault(address newVault) external returns (bool);
}

interface IwNATIVE {
    function deposit() external payable;

    function withdraw(uint256) external;
}

interface IAnycallExecutor {
    function execute(
        address _anycallProxy,
        address _token,
        uint256 _amount,
        bytes calldata _data
    ) external returns (bool success, bytes memory result);
}

contract MultichainV7Router is MPCManageable, PausableControlWithAdmin, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;

    bytes32 public constant Swapin_Paused_ROLE =
        keccak256("Swapin_Paused_ROLE");
    bytes32 public constant Swapout_Paused_ROLE =
        keccak256("Swapout_Paused_ROLE");
    bytes32 public constant Call_Paused_ROLE =
        keccak256("Call_Paused_ROLE");
    bytes32 public constant Exec_Paused_ROLE =
        keccak256("Exec_Paused_ROLE");
    bytes32 public constant Check_Completion_Paused_ROLE =
        keccak256("Check_Completion_Paused_ROLE");

    address public immutable wNATIVE;
    address public immutable anycallExecutor;

    struct ProxyInfo {
        bool supported;
        bool acceptAnyToken;
    }

    mapping(address => ProxyInfo) public anycallProxyInfo;
    mapping(bytes32 => bool) public retryRecords;
    mapping(string => bool) public completedSwapin;

    modifier checkCompletion(string memory swapID) {
        require(!completedSwapin[swapID] || paused(Check_Completion_Paused_ROLE), "swap is completed");
        _;
    }

    event LogAnySwapIn(
        string swapID,
        address indexed token,
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
        string swapID,
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

    event LogRetryExecRecord(
        string swapID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes data
    );


    constructor(
        address _admin,
        address _mpc,
        address _wNATIVE,
        address _anycallExecutor
    ) MPCManageable(_mpc) PausableControlWithAdmin(_admin) {
        require(_anycallExecutor != address(0), "zero anycall executor");
        anycallExecutor = _anycallExecutor;
        wNATIVE = _wNATIVE;
    }

    receive() external payable {
        assert(msg.sender == wNATIVE); // only accept Native via fallback from the wNative contract
    }

    function changeVault(address token, address newVault) external onlyMPC returns (bool) {
        return IAnyswapERC20Auth(token).changeVault(newVault);
    }

    function addAnycallProxies(address[] memory proxies, bool[] memory acceptAnyTokenFlags) external onlyMPC {
        uint256 length = proxies.length;
        require(length == acceptAnyTokenFlags.length, "length mismatch");
        for(uint256 i = 0; i < length; i++) {
            anycallProxyInfo[proxies[i]] = ProxyInfo(true, acceptAnyTokenFlags[i]);
        }
    }

    function removeAnycallProxies(address[] memory proxies) external onlyMPC {
        for(uint256 i = 0; i < proxies.length; i++) {
            delete anycallProxyInfo[proxies[i]];
        }
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(
        address token,
        string memory to,
        uint256 amount,
        uint256 toChainID
    ) external whenNotPaused(Swapout_Paused_ROLE) {
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
    ) external whenNotPaused(Swapout_Paused_ROLE) whenNotPaused(Call_Paused_ROLE) {
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

    function _anySwapOutUnderlying(address token, uint256 amount)
        internal
        whenNotPaused(Swapout_Paused_ROLE)
        returns (uint256)
    {
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
    ) external whenNotPaused(Call_Paused_ROLE) {
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

    function _anySwapOutNative(address token)
        internal
        whenNotPaused(Swapout_Paused_ROLE)
        returns (uint256)
    {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        uint256 old_balance = IERC20(wNATIVE).balanceOf(token);
        IwNATIVE(wNATIVE).deposit{value: msg.value}();
        IERC20(wNATIVE).safeTransfer(token, msg.value);
        uint256 new_balance = IERC20(wNATIVE).balanceOf(token);
        return new_balance > old_balance ? new_balance - old_balance : 0;
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(
        address token,
        string memory to,
        uint256 toChainID
    ) external payable {
        uint256 recvAmount = _anySwapOutNative(token);
        emit LogAnySwapOut(
            token,
            msg.sender,
            to,
            recvAmount,
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
    ) external whenNotPaused(Call_Paused_ROLE) payable {
        uint256 recvAmount = _anySwapOutNative(token);
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

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapIn(
        string memory swapID,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external whenNotPaused(Swapin_Paused_ROLE) checkCompletion(swapID) nonReentrant onlyMPC {
        completedSwapin[swapID] = true;
        assert(IRouter(token).mint(to, amount));
        emit LogAnySwapIn(swapID, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlying(
        string memory swapID,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external whenNotPaused(Swapin_Paused_ROLE) checkCompletion(swapID) nonReentrant onlyMPC {
        require(
            IUnderlying(token).underlying() != address(0),
            "MultichainRouter: zero underlying"
        );
        completedSwapin[swapID] = true;
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, to);
        emit LogAnySwapIn(swapID, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `Native`
    function anySwapInNative(
        string memory swapID,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external whenNotPaused(Swapin_Paused_ROLE) checkCompletion(swapID) nonReentrant onlyMPC {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        completedSwapin[swapID] = true;
        assert(IRouter(token).mint(address(this), amount));
        IUnderlying(token).withdraw(amount, address(this));
        IwNATIVE(wNATIVE).withdraw(amount);
        Address.sendValue(payable(to), amount);
        emit LogAnySwapIn(swapID, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying` or `Native` if possible
    function anySwapInAuto(
        string memory swapID,
        address token,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external whenNotPaused(Swapin_Paused_ROLE) checkCompletion(swapID) nonReentrant onlyMPC {
        completedSwapin[swapID] = true;
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
        emit LogAnySwapIn(swapID, token, to, amount, fromChainID, block.chainid);
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapInAndExec(
        string memory swapID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data
    ) external whenNotPaused(Swapin_Paused_ROLE) whenNotPaused(Exec_Paused_ROLE) checkCompletion(swapID) nonReentrant onlyMPC {
        require(anycallProxyInfo[anycallProxy].supported, "unsupported ancall proxy");
        completedSwapin[swapID] = true;

        assert(IRouter(token).mint(receiver, amount));

        bool success;
        bytes memory result;
        try IAnycallExecutor(anycallExecutor).execute(anycallProxy, token, amount, data)
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {
        }

        emit LogAnySwapInAndExec(
            swapID,
            token,
            receiver,
            amount,
            fromChainID,
            block.chainid,
            success,
            result
        );
    }

    function _anySwapInUnderlyingAndExec(
        string memory swapID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data,
        bool isRetry
    ) internal whenNotPaused(Swapin_Paused_ROLE) whenNotPaused(Exec_Paused_ROLE) nonReentrant {
        require(anycallProxyInfo[anycallProxy].supported, "unsupported ancall proxy");
        completedSwapin[swapID] = true;

        address receiveToken;

        { // fix Stack too deep
            address _underlying = IUnderlying(token).underlying();
            require(_underlying != address(0), "MultichainRouter: zero underlying");

            if (IERC20(_underlying).balanceOf(token) >= amount) {
                receiveToken = _underlying;
                assert(IRouter(token).mint(address(this), amount));
                IUnderlying(token).withdraw(amount, receiver);
            } else if (anycallProxyInfo[anycallProxy].acceptAnyToken) {
                receiveToken = token;
                assert(IRouter(token).mint(receiver, amount));
            } else {
                require(!isRetry, "MultichainRouter: retry failed");
                bytes32 retryHash = keccak256(abi.encode(swapID, token, receiver, amount, fromChainID, anycallProxy, data));
                retryRecords[retryHash] = true;
                emit LogRetryExecRecord(swapID, token, receiver, amount, fromChainID, anycallProxy, data);
                return;
            }
        }

        bool success;
        bytes memory result;
        try IAnycallExecutor(anycallExecutor).execute(anycallProxy, receiveToken, amount, data)
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {
        }

        { // fix Stack too deep
            string memory _swapID = swapID;
            emit LogAnySwapInAndExec(
                _swapID,
                token,
                receiver,
                amount,
                fromChainID,
                block.chainid,
                success,
                result
            );
        }
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlyingAndExec(
        string memory swapID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data
    ) external checkCompletion(swapID) onlyMPC {
        _anySwapInUnderlyingAndExec(swapID, token, receiver, amount, fromChainID, anycallProxy, data, false);
    }

    function retrySwapinAndExec(
        string memory swapID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes calldata data
    ) external {
        bytes32 retryHash = keccak256(abi.encode(swapID, token, receiver, amount, fromChainID, anycallProxy, data));
        require(retryRecords[retryHash], "retry record not exist");
        retryRecords[retryHash] = false;

        _anySwapInUnderlyingAndExec(swapID, token, receiver, amount, fromChainID, anycallProxy, data, true);
    }

    // extracts mpc fee from bridge fees
    function anySwapFeeTo(address token, uint256 amount) external onlyMPC {
        IRouter(token).mint(address(this), amount);
        IUnderlying(token).withdraw(amount, msg.sender);
    }
}
