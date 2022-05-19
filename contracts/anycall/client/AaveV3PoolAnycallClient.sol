// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../access/MPCManageable.sol";
import "../../access/PausableControlWithAdmin.sol";

interface IAaveV3Pool {
    function mintUnbacked(
        address asset,
        uint256 amount,
        address onBehalfOf,
        uint16 referralCode
    ) external;

    function backUnbacked(
        address asset,
        uint256 amount,
        uint256 fee
    ) external;
}

interface IAnycallProxy {
    function context() external returns (address, uint256);

    function anyCall(
        address _to,
        bytes calldata _data,
        address _fallback,
        uint256 _toChainId
    ) external;
}

abstract contract AnycallClientBase is PausableControlWithAdmin {
    address public callProxy;
    mapping(uint256 => address) public clientPeers; // key is chainId

    modifier onlyCallProxy() {
        require(msg.sender == callProxy, "AnycallClient: not authorized");
        _;
    }

    constructor(address _admin, address _callProxy) PausableControlWithAdmin(_admin) {
        require(_callProxy != address(0));
        callProxy = _callProxy;
    }

    function setCallProxy(address _callProxy) external onlyAdmin {
        require(_callProxy != address(0));
        callProxy = _callProxy;
    }

    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peers
    ) external onlyAdmin {
        require(_chainIds.length == _peers.length);
        for (uint256 i = 0; i < _chainIds.length; i++) {
            clientPeers[_chainIds[i]] = _peers[i];
        }
    }

    function anyFallback(address to, bytes calldata data) external onlyCallProxy {
        (address from,) = IAnycallProxy(callProxy).context();
        require(from == address(this), "AnycallClient: wrong context");

        _anyFallback(to, data);
    }

    function _anyFallback(address to, bytes calldata data) internal virtual;
}

contract AaveV3PoolAnycallClient is AnycallClientBase, MPCManageable {
    using SafeERC20 for IERC20;

    // pausable control roles
    bytes32 public constant PAUSE_CALLOUT_ROLE = keccak256("PAUSE_CALLOUT_ROLE");
    bytes32 public constant PAUSE_CALLIN_ROLE = keccak256("PAUSE_CALLIN_ROLE");
    bytes32 public constant PAUSE_FALLBACK_ROLE = keccak256("PAUSE_FALLBACK_ROLE");
    bytes32 public constant PAUSE_BACK_ROLE = keccak256("PAUSE_BACK_ROLE");

    address public aaveV3Pool;
    uint16 public referralCode;

    mapping(address => mapping(uint256 => address)) public tokenPeers;

    event LogCallout(
        address indexed token, address indexed sender, address indexed receiver,
        uint256 amount, uint256 toChainId
    );
    event LogCallin(
        address indexed token, address indexed sender, address indexed receiver,
        uint256 amount, uint256 fromChainId
    );
    event LogCalloutFail(
        address indexed token, address indexed sender, address indexed receiver,
        uint256 amount, uint256 toChainId
    );

    constructor(
        address _admin,
        address _mpc,
        address _callProxy,
        address _aaveV3Pool
    ) AnycallClientBase(_admin, _callProxy) MPCManageable(_mpc) {
        require(_aaveV3Pool != address(0));
        aaveV3Pool = _aaveV3Pool;
    }

    function setAavePool(address _aaveV3Pool) external onlyAdmin {
        require(_aaveV3Pool != address(0));
        aaveV3Pool = _aaveV3Pool;
    }

    function setReferralCode(uint16 _referralCode) external onlyAdmin {
        referralCode = _referralCode;
    }

    function setMultiTokens(
        address srcToken,
        uint256[] calldata chainIds,
        address[] calldata dstTokens
    ) external onlyAdmin {
        require(chainIds.length == dstTokens.length);
        for (uint256 i = 0; i < chainIds.length; i++) {
            tokenPeers[srcToken][chainIds[i]] = dstTokens[i];
        }
    }

    function backUnbacked(
        address asset,
        uint256 amount,
        uint256 fee
    ) external onlyMPC whenNotPaused(PAUSE_BACK_ROLE) {
        IAaveV3Pool(aaveV3Pool).backUnbacked(asset, amount, fee);
    }

    function callout(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId
    ) external whenNotPaused(PAUSE_CALLOUT_ROLE) {
        address clientPeer = clientPeers[toChainId];
        require(clientPeer != address(0), "AnycallClient: no dest client");

        address dstToken = tokenPeers[token][toChainId];
        require(dstToken != address(0), "AnycallClient: no dest token");

        IERC20(token).safeTransferFrom(msg.sender, address(this), amount);

        bytes memory data = abi.encodeWithSelector(
            AaveV3PoolAnycallClient.callin.selector,
            token,
            dstToken,
            amount,
            msg.sender,
            receiver,
            toChainId
        );
        IAnycallProxy(callProxy).anyCall(
            clientPeer,
            data,
            address(this),
            toChainId
        );

        emit LogCallout(token, msg.sender, receiver, amount, toChainId);
    }

    function callin(
        address srcToken,
        address dstToken,
        uint256 amount,
        address sender,
        address receiver,
        uint256 toChainId
    ) external onlyCallProxy whenNotPaused(PAUSE_CALLIN_ROLE) {
        _callin(srcToken, dstToken, amount, sender, receiver, toChainId);
    }

    function _callin(
        address srcToken,
        address dstToken,
        uint256 amount,
        address sender,
        address receiver,
        uint256 /*toChainId*/ // used in anyFallback
    ) internal {
        (address from, uint256 fromChainId) = IAnycallProxy(callProxy).context();
        require(clientPeers[fromChainId] == from, "AnycallClient: wrong context");
        require(tokenPeers[dstToken][fromChainId] == srcToken, "AnycallClient: mismatch source token");

        if (IERC20(dstToken).balanceOf(address(this)) >= amount) {
            IERC20(dstToken).safeTransferFrom(address(this), receiver, amount);
        } else {
            IAaveV3Pool(aaveV3Pool).mintUnbacked(dstToken, amount, receiver, referralCode);
        }

        emit LogCallin(dstToken, sender, receiver, amount, fromChainId);
    }

    function _anyFallback(
        address to,
        bytes calldata data
    ) internal override whenNotPaused(PAUSE_FALLBACK_ROLE) {
        (
            address srcToken,
            address dstToken,
            uint256 amount,
            address from,
            address receiver,
            uint256 toChainId
        ) = abi.decode(
            data[4:],
            (address, address, uint256, address, address, uint256)
        );

        require(clientPeers[toChainId] == to, "AnycallClient: mismatch dest client");
        require(tokenPeers[srcToken][toChainId] == dstToken, "AnycallClient: mismatch dest token");

        if (IERC20(srcToken).balanceOf(address(this)) >= amount) {
            IERC20(srcToken).safeTransferFrom(address(this), from, amount);
        } else {
            IAaveV3Pool(aaveV3Pool).mintUnbacked(srcToken, amount, from, referralCode);
        }

        emit LogCalloutFail(srcToken, from, receiver, amount, toChainId);
    }

    // impl AnyswapV6CallProxy IApp interface
    function anyExecute(bytes calldata data)
        external
        onlyCallProxy
        whenNotPaused(PAUSE_CALLIN_ROLE)
        returns (bool success, bytes memory result)
    {
        (
            bytes4 selector,
            address srcToken,
            address dstToken,
            uint256 amount,
            address sender,
            address receiver,
            uint256 toChainId
        ) = abi.decode(
            data,
            (bytes4, address, address, uint256, address, address, uint256)
        );

        require(selector == AaveV3PoolAnycallClient.callin.selector, "wrong selector");

        _callin(srcToken, dstToken, amount, sender, receiver, toChainId);

        return (true, "");
    }
}
