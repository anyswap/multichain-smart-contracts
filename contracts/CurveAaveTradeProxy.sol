// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MPCManageable.sol";

interface ITradeProxy {
    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        );
}

interface ICurveAave {
    function coins(uint256 index) external view returns (address);
    function underlying_coins(uint256 index) external view returns (address);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

contract TradeProxy_CurveAave is MPCManageable, ITradeProxy {
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedTradeProxyManager;
    mapping(address => bool) public supportedPool;

    struct TradeInfo {
        address pool;
        address receiver;
        bool is_exchange_underlying;
        uint256 deadline;
        int128 i;
        int128 j;
        uint256 min_dy;
    }

    constructor(
        address _mpc,
        address _tradeProxyManager,
        address[] memory pools
    ) MPCManageable(_mpc) {
        supportedTradeProxyManager[_tradeProxyManager] = true;
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPool[pools[i]] = true;
        }
    }

    function encode_trade_info(TradeInfo calldata info)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(info);
    }

    function decode_trade_info(bytes memory data)
        public
        pure
        returns (TradeInfo memory)
    {
        return abi.decode(data, (TradeInfo));
    }

    function addSupportedTradeProxyManager(address tradeProxyManager) external onlyMPC {
        supportedTradeProxyManager[tradeProxyManager] = true;
    }

    function removeSupportedTradeProxyManager(address tradeProxyManager) external onlyMPC {
        supportedTradeProxyManager[tradeProxyManager] = false;
    }

    function addSupportedPools(address[] calldata pools) external onlyMPC {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPool[pools[i]] = true;
        }
    }

    function removeSupportedPools(address[] calldata pools) external onlyMPC {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPool[pools[i]] = false;
        }
    }

    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        require(supportedTradeProxyManager[msg.sender], "TradeProxy: Forbidden");

        TradeInfo memory t = decode_trade_info(data);
        require(t.deadline >= block.timestamp, "TradeProxy: expired");
        require(supportedPool[t.pool], "TradeProxy: unsupported pool");

        ICurveAave pool = ICurveAave(t.pool);

        receiver = t.receiver;

        uint256 i = uint256(uint128(t.i));
        uint256 j = uint256(uint128(t.j));

        address srcToken;
        if (t.is_exchange_underlying) {
            srcToken = pool.underlying_coins(i);
            recvToken = pool.underlying_coins(j);
        } else {
            srcToken = pool.coins(i);
            recvToken = pool.coins(j);
        }
        require(token == srcToken, "TradeProxy: source token mismatch");
        require(recvToken != address(0), "TradeProxy: zero receive token");

        if (t.is_exchange_underlying) {
            recvAmount = pool.exchange_underlying(t.i, t.j, amount, t.min_dy);
        } else {
            recvAmount = pool.exchange(t.i, t.j, amount, t.min_dy);
        }

        IERC20(recvToken).safeTransfer(receiver, recvAmount);
    }
}
