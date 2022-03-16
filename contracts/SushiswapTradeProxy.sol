// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";
import "./MPCManageable.sol";

library SafeMathUniswap {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x + y) >= x, "ds-math-add-overflow");
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require((z = x - y) <= x, "ds-math-sub-underflow");
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        require(y == 0 || (z = x * y) / y == x, "ds-math-mul-overflow");
    }
}

interface IERC20Uniswap {
    function balanceOf(address owner) external view returns (uint256);
}

interface IWETH {
    function withdraw(uint256) external;
}

interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);
}

interface IUniswapV2Pair {
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

library UniswapV2Library {
    using SafeMathUniswap for uint256;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB)
        internal
        pure
        returns (address token0, address token1)
    {
        require(tokenA != tokenB, "UniswapV2Library: IDENTICAL_ADDRESSES");
        (token0, token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        require(token0 != address(0), "UniswapV2Library: ZERO_ADDRESS");
    }

    // calculates the CREATE2 address for a pair without making any external calls
    function pairFor(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (address pair) {
        return IUniswapV2Factory(factory).getPair(tokenA, tokenB);
    }

    // fetches and sorts the reserves for a pair
    function getReserves(
        address factory,
        address tokenA,
        address tokenB
    ) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0, ) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1, ) = IUniswapV2Pair(
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
        require(amountIn > 0, "UniswapV2Library: INSUFFICIENT_INPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
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
        require(amountOut > 0, "UniswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT");
        require(
            reserveIn > 0 && reserveOut > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
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
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
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
        require(path.length >= 2, "UniswapV2Library: INVALID_PATH");
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

library TransferHelper {
    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0xa9059cbb, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FAILED"
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, "TransferHelper: ETH_TRANSFER_FAILED");
    }
}

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

contract SushiswapTradeProxy is ITradeProxy, MPCManageable {
    using SafeMathUniswap for uint256;

    address public immutable SushiV2Factory; // 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac
    address public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "UniswapV2Router: EXPIRED");
        _;
    }

    constructor(
        address mpc_,
        address sushiV2Factory_,
        address weth_
    ) MPCManageable(mpc_) {
        SushiV2Factory = sushiV2Factory_;
        WETH = weth_;
    }

    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        onlyMPC
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        bytes4 sig = bytes4(data[:4]);
        if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactTokensForTokens(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (recvToken, receiver, recvAmount) = swapExactTokensForTokens(
                token,
                amount,
                data
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapTokensForExactTokens(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (recvToken, receiver, recvAmount) = swapTokensForExactTokens(
                token,
                amount,
                data
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapTokensForExactETH(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (recvToken, receiver, recvAmount) = swapTokensForExactETH(
                token,
                amount,
                data
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactTokensForETH(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (recvToken, receiver, recvAmount) = swapExactTokensForETH(
                token,
                amount,
                data
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactTokensForTokensSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                recvToken,
                receiver,
                recvAmount
            ) = swapExactTokensForTokensSupportingFeeOnTransferTokens(
                token,
                amount,
                data
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactTokensForETHSupportingFeeOnTransferTokens(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                recvToken,
                receiver,
                recvAmount
            ) = swapExactTokensForETHSupportingFeeOnTransferTokens(
                token,
                amount,
                data
            );
        }
        //  else if (
        //     sig ==
        //     bytes4(
        //         keccak256(
        //             "swapExactETHForTokens(uint256,address[],address,uint256)"
        //         )
        //     )
        // ) {
        //     (recvToken, receiver, recvAmount) = swapExactETHForTokens(
        //         token,
        //         amount,
        //         data
        //     );
        // }
        //  else if (
        //     sig ==
        //     bytes4(
        //         keccak256(
        //             "swapETHForExactTokens(uint256,address[],address,uint256)"
        //         )
        //     )
        // ) {
        //     (
        //         uint256 amountOut,
        //         address[] memory path,
        //         address to_,
        //         uint256 deadline
        //     ) = abi.decode(data[4:], (uint256, address[], address, uint256));
        //     IUniswapV2Router02(_sushiSwap).swapETHForExactTokens(
        //         amountOut,
        //         path,
        //         to_,
        //         deadline
        //     );
        // }
        // else if (
        //     sig ==
        //     bytes4(
        //         keccak256(
        //             "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)"
        //         )
        //     )
        // ) {
        //     (
        //         uint256 amountOutMin,
        //         address[] memory path,
        //         address to_,
        //         uint256 deadline
        //     ) = abi.decode(data[4:], (uint256, address[], address, uint256));
        //     IUniswapV2Router02(_sushiSwap)
        //         .swapExactETHForTokensSupportingFeeOnTransferTokens(
        //             amountOutMin,
        //             path,
        //             to_,
        //             deadline
        //         );
        // }
        else {
            revert(
                "MultichainTradeProxy: This tradeProxy not support to parse param data!"
            );
        }
    }

    function swapExactTokensForTokens(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountIn <= amount,
            "MultichainTradeProxy: amountIn must less than amount"
        );
        require(
            path[0] == token,
            "MultichainTradeProxy: input token not equals path[0]"
        );
        return
            _swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function swapTokensForExactTokens(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountOut,
            uint256 amountInMax,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountInMax <= amount,
            "MultichainTradeProxy: amountInMax must less than amount"
        );
        require(
            path[0] == token,
            "MultichainTradeProxy: input token not equals path[0]"
        );
        return
            _swapTokensForExactTokens(
                amountOut,
                amountInMax,
                path,
                to,
                deadline
            );
    }

    function swapTokensForExactETH(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountOut,
            uint256 amountInMax,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountInMax <= amount,
            "MultichainTradeProxy: swap amount has error"
        );
        require(path[0] == token, "MultichainTradeProxy: swap token has error");
        return
            _swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }

    function swapExactTokensForETH(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountIn <= amount,
            "MultichainTradeProxy: swap amount has error"
        );
        require(path[0] == token, "MultichainTradeProxy: swap token has error");
        return
            _swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountIn <= amount,
            "MultichainTradeProxy: swap amount has error"
        );
        require(path[0] == token, "MultichainTradeProxy: swap token has error");
        return
            _swapExactTokensForTokensSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        address token,
        uint256 amount,
        bytes calldata data
    )
        internal
        returns (
            address,
            address,
            uint256
        )
    {
        (
            uint256 amountIn,
            uint256 amountOutMin,
            address[] memory path,
            address to,
            uint256 deadline
        ) = abi.decode(
                data[4:],
                (uint256, uint256, address[], address, uint256)
            );
        require(
            amountIn <= amount,
            "MultichainTradeProxy: swap amount has error"
        );
        require(path[0] == token, "MultichainTradeProxy: swap token has error");
        return
            _swapExactTokensForETHSupportingFeeOnTransferTokens(
                amountIn,
                amountOutMin,
                path,
                to,
                deadline
            );
    }

    function _swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(
            SushiV2Factory,
            amountIn,
            path
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "MultichainTradeProxy: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amounts[0]
        );
        (recvToken, receiver, recvAmount) = _swap(amounts, path, to);
    }

    function _swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        uint256[] memory amounts = UniswapV2Library.getAmountsIn(
            SushiV2Factory,
            amountOut,
            path
        );
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amounts[0]
        );
        (recvToken, receiver, recvAmount) = _swap(amounts, path, to);
    }

    function _swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        uint256[] memory amounts = UniswapV2Library.getAmountsIn(
            SushiV2Factory,
            amountOut,
            path
        );
        require(
            amounts[0] <= amountInMax,
            "UniswapV2Router: EXCESSIVE_INPUT_AMOUNT"
        );
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amounts[0]
        );
        (recvToken, receiver, recvAmount) = _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function _swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(
            SushiV2Factory,
            amountIn,
            path
        );
        require(
            amounts[amounts.length - 1] >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amounts[0]
        );
        (recvToken, receiver, recvAmount) = _swap(amounts, path, address(this));
        IWETH(WETH).withdraw(amounts[amounts.length - 1]);
        TransferHelper.safeTransferETH(to, amounts[amounts.length - 1]);
    }

    function _swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address,
            address,
            uint256
        )
    {
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amountIn
        );
        uint256 balanceBefore = IERC20Uniswap(path[path.length - 1]).balanceOf(
            to
        );
        _swapSupportingFeeOnTransferTokens(path, to);
        require(
            IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(
                balanceBefore
            ) >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        return (
            path[path.length - 1],
            to,
            IERC20Uniswap(path[path.length - 1]).balanceOf(to).sub(
                balanceBefore
            )
        );
    }

    function _swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to,
        uint256 deadline
    )
        internal
        virtual
        ensure(deadline)
        returns (
            address,
            address,
            uint256
        )
    {
        require(path[path.length - 1] == WETH, "UniswapV2Router: INVALID_PATH");
        TransferHelper.safeTransfer(
            path[0],
            UniswapV2Library.pairFor(SushiV2Factory, path[0], path[1]),
            amountIn
        );
        _swapSupportingFeeOnTransferTokens(path, address(this));
        uint256 amountOut = IERC20Uniswap(WETH).balanceOf(address(this));
        require(
            amountOut >= amountOutMin,
            "UniswapV2Router: INSUFFICIENT_OUTPUT_AMOUNT"
        );
        IWETH(WETH).withdraw(amountOut);
        TransferHelper.safeTransferETH(to, amountOut);
        return (path[path.length - 1], to, amountOut);
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
            address,
            uint256
        )
    {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2
                ? UniswapV2Library.pairFor(SushiV2Factory, output, path[i + 2])
                : _to;
            IUniswapV2Pair(
                UniswapV2Library.pairFor(SushiV2Factory, input, output)
            ).swap(amount0Out, amount1Out, to, new bytes(0));
        }
        return (path[path.length - 1], _to, amounts[amounts.length - 1]);
    }

    // **** SWAP (supporting fee-on-transfer tokens) ****
    // requires the initial amount to have already been sent to the first pair
    function _swapSupportingFeeOnTransferTokens(
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            IUniswapV2Pair pair = IUniswapV2Pair(
                UniswapV2Library.pairFor(SushiV2Factory, input, output)
            );
            uint256 amountInput;
            uint256 amountOutput;
            {
                // scope to avoid stack too deep errors
                (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
                (uint256 reserveInput, uint256 reserveOutput) = input == token0
                    ? (reserve0, reserve1)
                    : (reserve1, reserve0);
                amountInput = IERC20Uniswap(input).balanceOf(address(pair)).sub(
                        reserveInput
                    );
                amountOutput = UniswapV2Library.getAmountOut(
                    amountInput,
                    reserveInput,
                    reserveOutput
                );
            }
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOutput)
                : (amountOutput, uint256(0));
            address to = i < path.length - 2
                ? UniswapV2Library.pairFor(SushiV2Factory, output, path[i + 2])
                : _to;
            pair.swap(amount0Out, amount1Out, to, new bytes(0));
        }
    }
}
