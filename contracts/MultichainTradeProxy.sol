// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";

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
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
}

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function migrator() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;

    function setMigrator(address) external;
}

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
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

    // given some amount of an asset and pair reserves, returns an equivalent amount of the other asset
    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) internal pure returns (uint256 amountB) {
        require(amountA > 0, "UniswapV2Library: INSUFFICIENT_AMOUNT");
        require(
            reserveA > 0 && reserveB > 0,
            "UniswapV2Library: INSUFFICIENT_LIQUIDITY"
        );
        amountB = amountA.mul(reserveB) / reserveA;
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
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x095ea7b3, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: APPROVE_FAILED"
        );
    }

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

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(
            abi.encodeWithSelector(0x23b872dd, from, to, value)
        );
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            "TransferHelper: TRANSFER_FROM_FAILED"
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

interface ITradeProxyManageable {
    function trade(
        address tradeProxy,
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

    function addTradeProxy(address tradeProxy) external;

    function removeTradeProxy(address tradeProxy) external;
}

abstract contract MPCManageable {
    using Address for address;

    address public mpc;
    address public pendingMPC;

    uint256 public constant delay = 2 days;
    uint256 public delayMPC;

    modifier onlyMPC() {
        require(msg.sender == mpc, "MPC: only mpc");
        _;
    }

    event LogChangeMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 effectiveTime
    );
    event LogApplyMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 applyTime
    );

    constructor(address _mpc) {
        require(_mpc != address(0), "MPC: mpc is the zero address");
        mpc = _mpc;
        emit LogChangeMPC(address(0), mpc, block.timestamp);
    }

    function changeMPC(address _mpc) external onlyMPC {
        require(_mpc != address(0), "MPC: mpc is the zero address");
        pendingMPC = _mpc;
        delayMPC = block.timestamp + delay;
        emit LogChangeMPC(mpc, pendingMPC, delayMPC);
    }

    function applyMPC() external {
        require(
            msg.sender == pendingMPC ||
                (msg.sender == mpc && address(pendingMPC).isContract()),
            "MPC: only pending mpc"
        );
        require(
            delayMPC > 0 && block.timestamp >= delayMPC,
            "MPC: time before delayMPC"
        );
        emit LogApplyMPC(mpc, pendingMPC, block.timestamp);
        mpc = pendingMPC;
        pendingMPC = address(0);
        delayMPC = 0;
    }
}

contract TradeProxyManager is MPCManageable, ITradeProxyManageable {
    using Address for address;

    mapping(address => bool) public tradeProxyMap;

    modifier tradeProxyExists(address tradeProxy) {
        require(
            tradeProxyMap[tradeProxy],
            "TradeProxyManageable: tradeProxy nonexists!"
        );
        _;
    }

    constructor(address mpc_, address[] memory tradeProxys)
        MPCManageable(mpc_)
    {
        for (uint256 index; index < tradeProxys.length; index++) {
            tradeProxyMap[tradeProxys[index]] = true;
        }
    }

    function addTradeProxy(address tradeProxy) external onlyMPC {
        require(
            tradeProxyMap[tradeProxy] == false,
            "TradeProxyManageable: tradeProxy exists!"
        );
        tradeProxyMap[tradeProxy] = true;
    }

    function removeTradeProxy(address tradeProxy) external onlyMPC {
        require(
            tradeProxyMap[tradeProxy],
            "TradeProxyManageable: tradeProxy nonexists!"
        );
        tradeProxyMap[tradeProxy] = false;
    }

    function trade(
        address tradeProxy,
        address token,
        uint256 amount,
        bytes calldata data
    )
        external
        tradeProxyExists(tradeProxy)
        onlyMPC
        returns (
            address recvToken,
            address receiver,
            uint256 recvAmount
        )
    {
        (recvToken, receiver, recvAmount) = ITradeProxy(tradeProxy).exec(
            token,
            amount,
            data
        );
    }
}

contract MultichainTradeProxy is ITradeProxy, MPCManageable {
    using SafeMathUniswap for uint256;

    address public immutable SushiV2Factory; // 0xC0AEe478e3658e2610c5F7A4A2E1777cE9e4f2Ac
    address public immutable WETH; // 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2

    event EventLog(bytes data);

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
