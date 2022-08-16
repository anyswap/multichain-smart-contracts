// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../access/MPCManageable.sol";
import "../access/PausableControlWithAdmin.sol";
import "./interfaces/IAnycallExecutor.sol";
import "./interfaces/IRouterSecurity.sol";
import "./interfaces/IRetrySwapinAndExec.sol";
import "./interfaces/IUnderlying.sol";
import "./interfaces/IwNATIVE.sol";
import "./interfaces/IAnyswapERC20Auth.sol";
import "./interfaces/IRouterMintBurn.sol";

contract MultichainV7Router is
    MPCManageable,
    PausableControlWithAdmin,
    ReentrancyGuard,
    IRetrySwapinAndExec
{
    using Address for address;
    using SafeERC20 for IERC20;

    bytes32 public constant Swapin_Paused_ROLE =
        keccak256("Swapin_Paused_ROLE");
    bytes32 public constant Swapout_Paused_ROLE =
        keccak256("Swapout_Paused_ROLE");
    bytes32 public constant Call_Paused_ROLE = keccak256("Call_Paused_ROLE");
    bytes32 public constant Exec_Paused_ROLE = keccak256("Exec_Paused_ROLE");

    address public immutable wNATIVE;
    address public immutable anycallExecutor;

    address public routerSecurity;

    struct ProxyInfo {
        bool supported;
        bool acceptAnyToken;
    }

    mapping(address => ProxyInfo) public anycallProxyInfo;
    mapping(bytes32 => bool) public retryRecords;

    event LogAnySwapIn(
        string swapID,
        bytes32 indexed swapoutID,
        address indexed token,
        address indexed receiver,
        uint256 amount,
        uint256 fromChainID
    );
    event LogAnySwapOut(
        bytes32 indexed swapoutID,
        address indexed token,
        address indexed from,
        string receiver,
        uint256 amount,
        uint256 toChainID
    );

    event LogAnySwapInAndExec(
        string swapID,
        bytes32 indexed swapoutID,
        address indexed token,
        address indexed receiver,
        uint256 amount,
        uint256 fromChainID,
        bool success,
        bytes result
    );
    event LogAnySwapOutAndCall(
        bytes32 indexed swapoutID,
        address indexed token,
        address indexed from,
        string receiver,
        uint256 amount,
        uint256 toChainID,
        string anycallProxy,
        bytes data
    );

    event LogRetryExecRecord(
        string swapID,
        bytes32 swapoutID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        address anycallProxy,
        bytes data
    );
    event LogRetrySwapInAndExec(
        string swapID,
        bytes32 swapoutID,
        address token,
        address receiver,
        uint256 amount,
        uint256 fromChainID,
        bool dontExec,
        bool success,
        bytes result
    );

    constructor(
        address _admin,
        address _mpc,
        address _wNATIVE,
        address _anycallExecutor,
        address _routerSecurity
    ) MPCManageable(_mpc) PausableControlWithAdmin(_admin) {
        require(_anycallExecutor != address(0), "zero anycall executor");
        anycallExecutor = _anycallExecutor;
        wNATIVE = _wNATIVE;
        routerSecurity = _routerSecurity;
    }

    receive() external payable {
        assert(msg.sender == wNATIVE); // only accept Native via fallback from the wNative contract
    }

    function setRouterSecurity(address _routerSecurity)
        external
        nonReentrant
        onlyMPC
    {
        routerSecurity = _routerSecurity;
    }

    function changeVault(address token, address newVault)
        external
        nonReentrant
        onlyMPC
        returns (bool)
    {
        return IAnyswapERC20Auth(token).changeVault(newVault);
    }

    function addAnycallProxies(
        address[] calldata proxies,
        bool[] calldata acceptAnyTokenFlags
    ) external nonReentrant onlyMPC {
        uint256 length = proxies.length;
        require(length == acceptAnyTokenFlags.length, "length mismatch");
        for (uint256 i = 0; i < length; i++) {
            anycallProxyInfo[proxies[i]] = ProxyInfo(
                true,
                acceptAnyTokenFlags[i]
            );
        }
    }

    function removeAnycallProxies(address[] calldata proxies)
        external
        nonReentrant
        onlyMPC
    {
        for (uint256 i = 0; i < proxies.length; i++) {
            delete anycallProxyInfo[proxies[i]];
        }
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to`
    function anySwapOut(
        address token,
        string calldata to,
        uint256 amount,
        uint256 toChainID
    ) external whenNotPaused(Swapout_Paused_ROLE) nonReentrant {
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            amount,
            toChainID,
            "",
            ""
        );
        assert(IRouterMintBurn(token).burn(msg.sender, amount));
        emit LogAnySwapOut(swapoutID, token, msg.sender, to, amount, toChainID);
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` and call anycall proxy with `data`
    function anySwapOutAndCall(
        address token,
        string calldata to,
        uint256 amount,
        uint256 toChainID,
        string calldata anycallProxy,
        bytes calldata data
    )
        external
        whenNotPaused(Swapout_Paused_ROLE)
        whenNotPaused(Call_Paused_ROLE)
        nonReentrant
    {
        require(data.length > 0, "empty call data");
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            amount,
            toChainID,
            anycallProxy,
            data
        );
        assert(IRouterMintBurn(token).burn(msg.sender, amount));
        emit LogAnySwapOutAndCall(
            swapoutID,
            token,
            msg.sender,
            to,
            amount,
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
        require(
            new_balance >= old_balance && new_balance <= old_balance + amount
        );
        return new_balance - old_balance;
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying`
    function anySwapOutUnderlying(
        address token,
        string calldata to,
        uint256 amount,
        uint256 toChainID
    ) external nonReentrant {
        uint256 recvAmount = _anySwapOutUnderlying(token, amount);
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID,
            "",
            ""
        );
        emit LogAnySwapOut(
            swapoutID,
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID
        );
    }

    // Swaps `amount` `token` from this chain to `toChainID` chain with recipient `to` by minting with `underlying` and call anycall proxy with `data`
    function anySwapOutUnderlyingAndCall(
        address token,
        string calldata to,
        uint256 amount,
        uint256 toChainID,
        string calldata anycallProxy,
        bytes calldata data
    ) external whenNotPaused(Call_Paused_ROLE) nonReentrant {
        require(data.length > 0, "empty call data");
        uint256 recvAmount = _anySwapOutUnderlying(token, amount);
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID,
            anycallProxy,
            data
        );
        emit LogAnySwapOutAndCall(
            swapoutID,
            token,
            msg.sender,
            to,
            recvAmount,
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
        require(
            new_balance >= old_balance && new_balance <= old_balance + msg.value
        );
        return new_balance - old_balance;
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to`
    function anySwapOutNative(
        address token,
        string calldata to,
        uint256 toChainID
    ) external payable nonReentrant {
        uint256 recvAmount = _anySwapOutNative(token);
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID,
            "",
            ""
        );
        emit LogAnySwapOut(
            swapoutID,
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID
        );
    }

    // Swaps `msg.value` `Native` from this chain to `toChainID` chain with recipient `to` and call anycall proxy with `data`
    function anySwapOutNativeAndCall(
        address token,
        string calldata to,
        uint256 toChainID,
        string calldata anycallProxy,
        bytes calldata data
    ) external payable whenNotPaused(Call_Paused_ROLE) nonReentrant {
        require(data.length > 0, "empty call data");
        uint256 recvAmount = _anySwapOutNative(token);
        bytes32 swapoutID = IRouterSecurity(routerSecurity).registerSwapout(
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID,
            anycallProxy,
            data
        );
        emit LogAnySwapOutAndCall(
            swapoutID,
            token,
            msg.sender,
            to,
            recvAmount,
            toChainID,
            anycallProxy,
            data
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapIn(string calldata swapID, SwapInfo calldata swapInfo)
        external
        whenNotPaused(Swapin_Paused_ROLE)
        nonReentrant
        onlyMPC
    {
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);
        assert(
            IRouterMintBurn(swapInfo.token).mint(
                swapInfo.receiver,
                swapInfo.amount
            )
        );
        emit LogAnySwapIn(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlying(
        string calldata swapID,
        SwapInfo calldata swapInfo
    ) external whenNotPaused(Swapin_Paused_ROLE) nonReentrant onlyMPC {
        require(
            IUnderlying(swapInfo.token).underlying() != address(0),
            "MultichainRouter: zero underlying"
        );
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);
        assert(
            IRouterMintBurn(swapInfo.token).mint(address(this), swapInfo.amount)
        );
        IUnderlying(swapInfo.token).withdraw(
            swapInfo.amount,
            swapInfo.receiver
        );
        emit LogAnySwapIn(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `Native`
    function anySwapInNative(string calldata swapID, SwapInfo calldata swapInfo)
        external
        whenNotPaused(Swapin_Paused_ROLE)
        nonReentrant
        onlyMPC
    {
        require(wNATIVE != address(0), "MultichainRouter: zero wNATIVE");
        require(
            IUnderlying(swapInfo.token).underlying() == wNATIVE,
            "MultichainRouter: underlying is not wNATIVE"
        );
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);
        assert(
            IRouterMintBurn(swapInfo.token).mint(address(this), swapInfo.amount)
        );
        IUnderlying(swapInfo.token).withdraw(swapInfo.amount, address(this));
        IwNATIVE(wNATIVE).withdraw(swapInfo.amount);
        Address.sendValue(payable(swapInfo.receiver), swapInfo.amount);
        emit LogAnySwapIn(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying` or `Native` if possible
    function anySwapInAuto(string calldata swapID, SwapInfo calldata swapInfo)
        external
        whenNotPaused(Swapin_Paused_ROLE)
        nonReentrant
        onlyMPC
    {
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);
        address _underlying = IUnderlying(swapInfo.token).underlying();
        if (
            _underlying != address(0) &&
            IERC20(_underlying).balanceOf(swapInfo.token) >= swapInfo.amount
        ) {
            assert(
                IRouterMintBurn(swapInfo.token).mint(
                    address(this),
                    swapInfo.amount
                )
            );
            if (_underlying == wNATIVE) {
                IUnderlying(swapInfo.token).withdraw(
                    swapInfo.amount,
                    address(this)
                );
                IwNATIVE(wNATIVE).withdraw(swapInfo.amount);
                Address.sendValue(payable(swapInfo.receiver), swapInfo.amount);
            } else {
                IUnderlying(swapInfo.token).withdraw(
                    swapInfo.amount,
                    swapInfo.receiver
                );
            }
        } else {
            assert(
                IRouterMintBurn(swapInfo.token).mint(
                    swapInfo.receiver,
                    swapInfo.amount
                )
            );
        }
        emit LogAnySwapIn(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID
    function anySwapInAndExec(
        string calldata swapID,
        SwapInfo calldata swapInfo,
        address anycallProxy,
        bytes calldata data
    )
        external
        whenNotPaused(Swapin_Paused_ROLE)
        whenNotPaused(Exec_Paused_ROLE)
        nonReentrant
        onlyMPC
    {
        require(
            anycallProxyInfo[anycallProxy].supported,
            "unsupported ancall proxy"
        );
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);

        assert(
            IRouterMintBurn(swapInfo.token).mint(
                swapInfo.receiver,
                swapInfo.amount
            )
        );

        bool success;
        bytes memory result;
        try
            IAnycallExecutor(anycallExecutor).execute(
                anycallProxy,
                swapInfo.token,
                swapInfo.amount,
                data
            )
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {}

        emit LogAnySwapInAndExec(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID,
            success,
            result
        );
    }

    // Swaps `amount` `token` in `fromChainID` to `to` on this chainID with `to` receiving `underlying`
    function anySwapInUnderlyingAndExec(
        string calldata swapID,
        SwapInfo calldata swapInfo,
        address anycallProxy,
        bytes calldata data
    )
        external
        whenNotPaused(Swapin_Paused_ROLE)
        whenNotPaused(Exec_Paused_ROLE)
        nonReentrant
        onlyMPC
    {
        require(
            anycallProxyInfo[anycallProxy].supported,
            "unsupported ancall proxy"
        );
        IRouterSecurity(routerSecurity).registerSwapin(swapID, swapInfo);

        address receiveToken;
        // transfer token to the receiver before execution
        {
            address _underlying = IUnderlying(swapInfo.token).underlying();
            require(
                _underlying != address(0),
                "MultichainRouter: zero underlying"
            );

            if (
                IERC20(_underlying).balanceOf(swapInfo.token) >= swapInfo.amount
            ) {
                receiveToken = _underlying;
                assert(
                    IRouterMintBurn(swapInfo.token).mint(
                        address(this),
                        swapInfo.amount
                    )
                );
                IUnderlying(swapInfo.token).withdraw(
                    swapInfo.amount,
                    swapInfo.receiver
                );
            } else if (anycallProxyInfo[anycallProxy].acceptAnyToken) {
                receiveToken = swapInfo.token;
                assert(
                    IRouterMintBurn(swapInfo.token).mint(
                        swapInfo.receiver,
                        swapInfo.amount
                    )
                );
            } else {
                bytes32 retryHash = keccak256(
                    abi.encode(
                        swapID,
                        swapInfo.swapoutID,
                        swapInfo.token,
                        swapInfo.receiver,
                        swapInfo.amount,
                        swapInfo.fromChainID,
                        anycallProxy,
                        data
                    )
                );
                retryRecords[retryHash] = true;
                emit LogRetryExecRecord(
                    swapID,
                    swapInfo.swapoutID,
                    swapInfo.token,
                    swapInfo.receiver,
                    swapInfo.amount,
                    swapInfo.fromChainID,
                    anycallProxy,
                    data
                );
                return;
            }
        }

        bool success;
        bytes memory result;
        try
            IAnycallExecutor(anycallExecutor).execute(
                anycallProxy,
                receiveToken,
                swapInfo.amount,
                data
            )
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch {}

        emit LogAnySwapInAndExec(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID,
            success,
            result
        );
    }

    // should be called only by the `receiver`
    // @param dontExec
    // if `true` transfer the underlying token to the `receiver`,
    //      and the `receiver` should complete the left job.
    // if `false` retry swapin and execute in normal way.
    function retrySwapinAndExec(
        string calldata swapID,
        SwapInfo calldata swapInfo,
        address anycallProxy,
        bytes calldata data,
        bool dontExec
    ) external nonReentrant {
        require(msg.sender == swapInfo.receiver, "forbid retry swap");
        require(
            IRouterSecurity(routerSecurity).isSwapCompleted(
                swapID,
                swapInfo.swapoutID,
                swapInfo.fromChainID
            ),
            "swap not completed"
        );
        bytes32 retryHash = keccak256(
            abi.encode(
                swapID,
                swapInfo.swapoutID,
                swapInfo.token,
                swapInfo.receiver,
                swapInfo.amount,
                swapInfo.fromChainID,
                anycallProxy,
                data
            )
        );
        require(retryRecords[retryHash], "retry record not exist");
        retryRecords[retryHash] = false;

        address _underlying = IUnderlying(swapInfo.token).underlying();
        require(_underlying != address(0), "MultichainRouter: zero underlying");
        require(
            IERC20(_underlying).balanceOf(swapInfo.token) >= swapInfo.amount,
            "MultichainRouter: retry failed"
        );
        assert(
            IRouterMintBurn(swapInfo.token).mint(address(this), swapInfo.amount)
        );
        IUnderlying(swapInfo.token).withdraw(
            swapInfo.amount,
            swapInfo.receiver
        );

        bool success;
        bytes memory result;

        if (!dontExec) {
            try
                IAnycallExecutor(anycallExecutor).execute(
                    anycallProxy,
                    _underlying,
                    swapInfo.amount,
                    data
                )
            returns (bool succ, bytes memory res) {
                (success, result) = (succ, res);
            } catch {}
        }

        emit LogRetrySwapInAndExec(
            swapID,
            swapInfo.swapoutID,
            swapInfo.token,
            swapInfo.receiver,
            swapInfo.amount,
            swapInfo.fromChainID,
            dontExec,
            success,
            result
        );
    }

    // extracts mpc fee from bridge fees
    function anySwapFeeTo(address token, uint256 amount)
        external
        nonReentrant
        onlyMPC
    {
        IRouterMintBurn(token).mint(address(this), amount);
        IUnderlying(token).withdraw(amount, msg.sender);
    }
}
