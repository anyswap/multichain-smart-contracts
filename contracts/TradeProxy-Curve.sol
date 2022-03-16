// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MPCManageable.sol";

interface ITradeProxy {
    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (address recvToken, address receiver, uint256 recvAmount);
}

interface ICurve {
    function coins(int128 index) external returns (address);
    function underlying_coins(int128 index) external returns (address);
}

contract TradeProxy_Curve is MPCManageable, ITradeProxy {
    using Address for address;
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedPools;

    bytes4 constant Exchange_Selector = bytes4(
        keccak256(
            "exchange(int128,int128,uint256,uint256)"
        )
    );
    bytes4 constant Exchange_Underlying_Selector = bytes4(
        keccak256(
            "exchange_underlying(int128,int128,uint256,uint256)"
        )
    );

    struct TradeInfo {
        address pool;
        address receiver;
        bool is_exchange_underlying;
        uint256 deadline;
        int128 i;
        int128 j;
        uint256 min_dy;
    }

    constructor(address _mpc, address[] memory pools) MPCManageable(_mpc) {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPools[pools[i]] = true;
        }
    }

    function encode_trade_info(TradeInfo calldata info) public pure returns (bytes memory) {
        return abi.encode(info);
    }

    function decode_trade_info(bytes memory data) public pure returns (TradeInfo memory) {
        return abi.decode((data), (TradeInfo));
    }

    function addSupportedPools(address[] calldata pools) external onlyMPC {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPools[pools[i]] = true;
        }
    }

    function removeSupportedPools(address[] calldata pools) external onlyMPC {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPools[pools[i]] = false;
        }
    }

    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (address recvToken, address receiver, uint256 recvAmount) {
        TradeInfo memory t = decode_trade_info(data);
        require(t.deadline >= block.timestamp, "TradeProxy: expired");

        address pool = t.pool;
        require(supportedPools[pool], "TradeProxy: unsupported pool");

        int128 i = t.i;
        int128 j = t.j;

        address srcToken;
        if (t.is_exchange_underlying) {
            srcToken = ICurve(pool).coins(i);
            recvToken = ICurve(pool).coins(j);
        } else {
            srcToken = ICurve(pool).underlying_coins(i);
            recvToken = ICurve(pool).underlying_coins(j);
        }

        require(token == srcToken, "TradeProxy: source token mismatch");

        uint256 old_balance = IERC20(recvToken).balanceOf(address(this));

        if (t.is_exchange_underlying) {
            call_exchange_underlying(pool, i, j, amount, t.min_dy);
        } else {
            call_exchange(pool, i, j, amount, t.min_dy);
        }

        uint256 new_balance = IERC20(recvToken).balanceOf(address(this));

        receiver = t.receiver;
        recvAmount = new_balance - old_balance;
        IERC20(recvToken).safeTransfer(receiver, recvAmount);
    }

    function call_exchange(address pool, int128 i, int128 j, uint256 dx, uint256 min_dy) internal {
        pool.functionCall(abi.encodeWithSelector(Exchange_Selector, i, j, dx, min_dy));
    }

    function call_exchange_underlying(address pool, int128 i, int128 j, uint256 dx, uint256 min_dy) internal {
        pool.functionCall(abi.encodeWithSelector(Exchange_Underlying_Selector, i, j, dx, min_dy));
    }
}
