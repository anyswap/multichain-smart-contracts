// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../access/MPCManageable.sol";

library SafeMathSushiswap {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x + y) >= x, "ds-math-add-overflow");
        }
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x - y) <= x, "ds-math-sub-underflow");
        }
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
        }
    }
}

interface IwNATIVE {
    function withdraw(uint256) external;
}

interface ISushiswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface ISushiswapV2Pair {
    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

library SushiswapV2Library {
    using SafeMathSushiswap for uint256;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "SushiswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "SushiswapV2Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (address pair) {
        return ISushiswapV2Factory(factory).getPair(tokenA, tokenB);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = ISushiswapV2Pair(
            pairFor(factory, tokenA, tokenB)
        ).getReserves();
        (reserveA, reserveB) = tokenA == token0
            ? (reserve0, reserve1)
            : (reserve1, reserve0);
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, "SushiswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "SushiswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, "SushiswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "SushiswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(
        address factory,
        uint256 amountIn,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "SushiswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[0] = amountIn;
        for (uint256 i; i < path.length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                path[i],
                path[i + 1]
            );
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(
        address factory,
        uint256 amountOut,
        address[] memory path
    ) internal view returns (uint256[] memory amounts) {
        require(path.length >= 2, "SushiswapV2Library: INVALID_PATH");
        amounts = new uint256[](path.length);
        amounts[amounts.length - 1] = amountOut;
        for (uint256 i = path.length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(
                factory,
                path[i - 1],
                path[i]
            );
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}

interface IAnycallProxy {
    function exec(
        address token,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result);
}

contract AnycallProxy_SushiSwap is IAnycallProxy, MPCManageable {
    using SafeMathSushiswap for uint256;
    using SafeERC20 for IERC20;

    address public immutable sushiFactory;
    address public immutable wNATIVE;
    mapping(address => bool) public supportedCaller;

    event TokenSwap(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );
    event TokenBack(
        address indexed token,
        address indexed receiver,
        uint256 amount
    );

    modifier onlyAuth() {
        require(supportedCaller[msg.sender], "SushiSwapAnycallProxy: only auth");
        _;
    }

    constructor(
        address mpc_,
        address caller_,
        address sushiV2Factory_,
        address wNATIVE_
    ) MPCManageable(mpc_) {
        supportedCaller[caller_] = true;
        sushiFactory = sushiV2Factory_;
        wNATIVE = wNATIVE_;
    }

    struct AnycallInfo {
        uint256 amountOut;
        uint256 amountOutMin;
        uint256 amountInMax;
        address[] path;
        uint256 deadline;
        bool toNative;
    }

    struct AnycallRes {
        address recvToken;
        address receiver;
        uint256 recvAmount;
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

    function addSupportedCaller(address caller) external onlyMPC {
        supportedCaller[caller] = true;
    }

    function removeSupportedCaller(address caller) external onlyMPC {
        supportedCaller[caller] = false;
    }

    function exec(
        address token,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external onlyAuth returns (bool success, bytes memory result) {
        AnycallInfo memory anycallInfo = decode_anycall_info(data);
        require(
            anycallInfo.deadline >= block.timestamp,
            "SushiSwapAnycallProxy: EXPIRED"
        );

        address[] memory path = anycallInfo.path;
        require(path.length >= 2, "SushiSwapAnycallProxy: invalid path length");
        require(
            path[0] == token,
            "SushiSwapAnycallProxy: source token mismatch"
        );

        require(
            anycallInfo.amountInMax <= amount,
            "SushiSwapAnycallProxy:EXCESSIVE_INPUT_AMOUNT"
        );

        uint256[] memory amounts;
        if (anycallInfo.amountOut == 0) {
            amounts = swapExactTokensForTokens(anycallInfo);
        } else {
            amounts = swapTokensForExactTokens(anycallInfo);
        }

        IERC20(path[0]).safeTransfer(
            SushiswapV2Library.pairFor(sushiFactory, path[0], path[1]),
            amounts[0]
        );

        address recvToken;
        uint256 recvAmount;

        if (anycallInfo.toNative) {
            require(
                path[path.length - 1] == wNATIVE,
                "SushiSwapAnycallProxy:INVALID_PATH"
            );
            (recvToken, recvAmount) = _swap(
                amounts,
                path,
                address(this)
            );
            IwNATIVE(wNATIVE).withdraw(recvAmount);
            Address.sendValue(payable(receiver), recvAmount);
            recvToken = address(0);
        } else {
            (recvToken, recvAmount) = _swap(
                amounts,
                path,
                receiver
            );
        }
        emit TokenSwap(recvToken, receiver, recvAmount);

        if (amount.sub(amounts[0]) > 0) {
            IERC20(path[0]).safeTransfer(
                receiver,
                amount.sub(amounts[0])
            );
            emit TokenBack(token, receiver, amount.sub(amounts[0]));
        }

        return (
            true,
            abi.encode(recvToken, recvAmount)
        );
    }

    function swapTokensForExactTokens(AnycallInfo memory anycallInfo)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = SushiswapV2Library.getAmountsIn(
            sushiFactory,
            anycallInfo.amountOut,
            anycallInfo.path
        );
        require(
            amounts[0] <= anycallInfo.amountInMax,
            "SushiSwapAnycallProxy: EXCESSIVE_INPUT_AMOUNT"
        );
    }

    function swapExactTokensForTokens(AnycallInfo memory anycallInfo)
        internal
        view
        returns (uint256[] memory amounts)
    {
        amounts = SushiswapV2Library.getAmountsOut(
            sushiFactory,
            anycallInfo.amountInMax,
            anycallInfo.path
        );

        require(
            amounts[amounts.length - 1] >= anycallInfo.amountOutMin,
            "SushiSwapAnycallProxy: INSUFFICIENT_OUTPUT_AMOUNT"
        );
    }

    // **** SWAP ****
    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    )
        internal
        virtual
        returns (
            address,
            uint256
        )
    {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = SushiswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? SushiswapV2Library.pairFor(sushiFactory, output, path[i + 2])
                : _to;
            ISushiswapV2Pair(
                SushiswapV2Library.pairFor(sushiFactory, input, output)
            ).swap(amount0Out, amount1Out, to, new bytes(0));
        }
        return (path[path.length - 1], amounts[amounts.length - 1]);
    }

    fallback() external payable {
        assert(msg.sender == wNATIVE); // only accept Native via fallback from the wNative contract
    }

    receive() external payable {
        assert(msg.sender == wNATIVE); // only accept Native via fallback from the wNative contract
    }
}
