// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AnycallProxyBase.sol";

interface ICurveAave {
    function coins(uint256 index) external view returns (address);
    function underlying_coins(uint256 index) external view returns (address);

    function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
    function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external returns (uint256);
}

contract AnycallProxy_CurveAave is AnycallProxyBase {
    using SafeERC20 for IERC20;

    mapping(address => bool) public supportedPool;

    struct AnycallInfo {
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
        address _caller,
        address[] memory pools
    ) AnycallProxyBase(_mpc, _caller) {
        for (uint256 i = 0; i < pools.length; i++) {
            supportedPool[pools[i]] = true;
        }
    }

    function encode_anycall_info(AnycallInfo calldata info)
        public
        pure
        returns (bytes memory)
    {
        return abi.encode(info);
    }

    function decode_anycall_info(bytes memory data)
        public
        pure
        returns (AnycallInfo memory)
    {
        return abi.decode(data, (AnycallInfo));
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
    ) external onlyAuth returns (bool success, bytes memory result) {
        AnycallInfo memory t = decode_anycall_info(data);
        require(t.deadline >= block.timestamp, "AnycallProxy: expired");
        require(supportedPool[t.pool], "AnycallProxy: unsupported pool");
        require(t.receiver != address(0), "AnycallProxy: zero receiver");

        ICurveAave pool = ICurveAave(t.pool);

        uint256 i = uint256(uint128(t.i));
        uint256 j = uint256(uint128(t.j));

        address srcToken;
        address recvToken;
        if (t.is_exchange_underlying) {
            srcToken = pool.underlying_coins(i);
            recvToken = pool.underlying_coins(j);
        } else {
            srcToken = pool.coins(i);
            recvToken = pool.coins(j);
        }
        require(token == srcToken, "AnycallProxy: source token mismatch");
        require(recvToken != address(0), "AnycallProxy: zero receive token");

        uint256 recvAmount;
        if (t.is_exchange_underlying) {
            recvAmount = pool.exchange_underlying(t.i, t.j, amount, t.min_dy);
        } else {
            recvAmount = pool.exchange(t.i, t.j, amount, t.min_dy);
        }

        IERC20(recvToken).safeTransfer(t.receiver, recvAmount);

        return (true, abi.encode(recvToken, recvAmount));
    }
}
