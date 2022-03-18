// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./MPCManageable.sol";

interface ISushiswapV2Pair {
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function swap(uint256 amount0Out, uint256 amount1Out, address to, bytes calldata data) external;
}

interface IwNATIVE {
    function deposit() external payable;
    function transfer(address to, uint256 value) external returns (bool);
    function withdraw(uint256) external;
}

// a library for performing overflow-safe math, courtesy of DappHub (https://github.com/dapphub/ds-math)

library SafeMathSushiswap {
    function add(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x + y) >= x, 'ds-math-add-overflow');
        }
    }

    function sub(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require((z = x - y) <= x, 'ds-math-sub-underflow');
        }
    }

    function mul(uint256 x, uint256 y) internal pure returns (uint256 z) {
        unchecked {
            require(y == 0 || (z = x * y) / y == x, 'ds-math-mul-overflow');
        }
    }
}

library SushiswapV2Library {
    using SafeMathSushiswap for uint256;

    // returns sorted token addresses, used to handle return values from pairs sorted in this order
    function sortTokens(address tokenA, address tokenB) internal pure returns (address token0, address token1) {
        require(tokenA != tokenB, 'SushiswapV2Library: IDENTICAL_ADDRESSES');
        (token0, token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);
        require(token0 != address(0), 'SushiswapV2Library: ZERO_ADDRESS');
    }

    // calculates the CREATE2 address for a pair without making any external calls
    // take care the `init code hash` must be right.
    // the other way is by external call `factory.getPair` (does this way cost more gas?)
    function pairFor(address factory, address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = sortTokens(tokenA, tokenB);
        pair = address(uint160(uint256(keccak256(abi.encodePacked(
                hex'ff',
                factory,
                keccak256(abi.encodePacked(token0, token1)),
                hex'e18a34eb0e04b04f7a0ac29a6e80748dca96319b42c54d679cb821dca90c6303' // init code hash
            )))));
    }

    // fetches and sorts the reserves for a pair
    function getReserves(address factory, address tokenA, address tokenB) internal view returns (uint256 reserveA, uint256 reserveB) {
        (address token0,) = sortTokens(tokenA, tokenB);
        (uint256 reserve0, uint256 reserve1,) = ISushiswapV2Pair(pairFor(factory, tokenA, tokenB)).getReserves();
        (reserveA, reserveB) = tokenA == token0 ? (reserve0, reserve1) : (reserve1, reserve0);
    }

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) internal pure returns (uint256 amountB) {
        require(amountA > 0, 'SushiswapV2Library: INSUFFICIENT_AMOUNT');
        require(reserveA > 0 && reserveB > 0, 'SushiswapV2Library: INSUFFICIENT_LIQUIDITY');
        amountB = amountA.mul(reserveB) / reserveA;
    }

    // given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountOut) {
        require(amountIn > 0, 'SushiswapV2Library: INSUFFICIENT_INPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SushiswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut) internal pure returns (uint256 amountIn) {
        require(amountOut > 0, 'SushiswapV2Library: INSUFFICIENT_OUTPUT_AMOUNT');
        require(reserveIn > 0 && reserveOut > 0, 'SushiswapV2Library: INSUFFICIENT_LIQUIDITY');
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // performs chained getAmountOut calculations on any number of pairs
    function getAmountsOut(address factory, uint256 amountIn, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 length = path.length;
        require(length >= 2, 'SushiswapV2Library: INVALID_PATH');
        amounts = new uint256[](length);
        amounts[0] = amountIn;
        for (uint256 i; i < length - 1; i++) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i], path[i + 1]);
            amounts[i + 1] = getAmountOut(amounts[i], reserveIn, reserveOut);
        }
    }

    // performs chained getAmountIn calculations on any number of pairs
    function getAmountsIn(address factory, uint256 amountOut, address[] memory path) internal view returns (uint256[] memory amounts) {
        uint256 length = path.length;
        require(length >= 2, 'SushiswapV2Library: INVALID_PATH');
        amounts = new uint256[](length);
        amounts[length - 1] = amountOut;
        for (uint256 i = length - 1; i > 0; i--) {
            (uint256 reserveIn, uint256 reserveOut) = getReserves(factory, path[i - 1], path[i]);
            amounts[i - 1] = getAmountIn(amounts[i], reserveIn, reserveOut);
        }
    }
}

interface IAnycallProxy {
    function exec(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result);
}

contract AnycallProxy_Sushiswap is MPCManageable, IAnycallProxy {
    using SafeERC20 for IERC20;

    address public immutable factory;
    address public immutable wNATIVE;

    mapping(address => bool) public supportedCaller;

    struct AnycallInfo {
        uint256 amountOutMin;
        address[] path;
        address receiver;
        uint256 deadline;
        bool forNative;
    }

    constructor(
        address _mpc,
        address _factory,
        address _wNATIVE,
        address _caller
    ) MPCManageable(_mpc) {
        factory = _factory;
        wNATIVE = _wNATIVE;
        supportedCaller[_caller] = true;
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
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result) {
        require(supportedCaller[msg.sender], "AnycallProxy: Forbidden");

        AnycallInfo memory t = decode_anycall_info(data);
        require(t.deadline >= block.timestamp, "AnycallProxy: expired");

        address[] memory path = t.path;
        uint256 length = path.length;
        require(length >= 2, "AnycallProxy: invalid path length");
        require(token == path[0], "AnycallProxy: source token mismatch");

        uint256[] memory amounts = SushiswapV2Library.getAmountsOut(factory, amount, path);
        require(amounts.length == length, "path and amounts length mismatch");
        require(amount == amounts[0], "AnycallProxy: source amount mismatch");
        require(amounts[length - 1] >= t.amountOutMin, "AnycallProxy: insufficient output amount");

        // send the initial amount to the first pair
        IERC20(token).safeTransfer(SushiswapV2Library.pairFor(factory, token, path[1]), amount);

        address receiver = t.receiver;
        address recvToken = path[length - 1];
        uint256 recvAmount = amounts[length - 1];

        if (t.forNative) {
            require(recvToken == wNATIVE, "AnycallProxy: path is not end of wNATIVE");
            _swap(amounts, path, address(this));
            IwNATIVE(wNATIVE).withdraw(recvAmount);
            Address.sendValue(payable(receiver), recvAmount);
        } else {
            _swap(amounts, path, receiver);
        }

        return (true, abi.encode(recvToken, t.receiver, recvAmount));
    }

    // requires the initial amount to have already been sent to the first pair
    function _swap(uint256[] memory amounts, address[] memory path, address receiver) internal {
        uint256 length = path.length;
        for (uint256 i; i < length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0,) = SushiswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0 ? (uint256(0), amountOut) : (amountOut, uint256(0));
            address to = i < length - 2 ? SushiswapV2Library.pairFor(factory, output, path[i + 2]) : receiver;
            ISushiswapV2Pair(SushiswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out, amount1Out, to, new bytes(0)
            );
        }
    }

    // **** LIBRARY FUNCTIONS ****
    function quote(uint256 amountA, uint256 reserveA, uint256 reserveB) public pure returns (uint256 amountB) {
        return SushiswapV2Library.quote(amountA, reserveA, reserveB);
    }

    function getAmountOut(uint256 amountIn, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountOut)
    {
        return SushiswapV2Library.getAmountOut(amountIn, reserveIn, reserveOut);
    }

    function getAmountIn(uint256 amountOut, uint256 reserveIn, uint256 reserveOut)
        public
        pure
        returns (uint256 amountIn)
    {
        return SushiswapV2Library.getAmountIn(amountOut, reserveIn, reserveOut);
    }

    function getAmountsOut(uint256 amountIn, address[] memory path)
        public
        view
        returns (uint256[] memory amounts)
    {
        return SushiswapV2Library.getAmountsOut(factory, amountIn, path);
    }

    function getAmountsIn(uint256 amountOut, address[] memory path)
        public
        view
        returns (uint256[] memory amounts)
    {
        return SushiswapV2Library.getAmountsIn(factory, amountOut, path);
    }
}
