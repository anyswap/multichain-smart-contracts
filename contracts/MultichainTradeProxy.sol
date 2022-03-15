// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/utils/Address.sol";

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
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

contract MultichainTradeProxy is MPCManageable {
    address public _sushiSwap;
    address public _curve;

    event EventLog(address to, bytes data);

    constructor(
        address mpc_,
        address sushiSwap_,
        address curve_
    ) MPCManageable(mpc_) {
        _sushiSwap = sushiSwap_;
        _curve = curve_;
    }

    function setSushiSwap(address sushiSwap_) external onlyMPC {
        _sushiSwap = sushiSwap_;
    }

    function setCurve(address curve_) external onlyMPC {
        _curve = curve_;
    }

    function trade(address to, bytes calldata data)
        external
    // returns (bool success, bytes memory result)
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
            (
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap).swapExactTokensForTokens(
                amountIn,
                amountOutMin,
                path,
                to_,
                deadline
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapTokensForExactTokens(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountOut,
                uint256 amountInMax,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap).swapTokensForExactTokens(
                amountOut,
                amountInMax,
                path,
                to_,
                deadline
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactETHForTokens(uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(data[4:], (uint256, address[], address, uint256));
            IUniswapV2Router02(_sushiSwap).swapExactETHForTokens(
                amountOutMin,
                path,
                to_,
                deadline
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapTokensForExactETH(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountOut,
                uint256 amountInMax,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap).swapTokensForExactETH(
                amountOut,
                amountInMax,
                path,
                to_,
                deadline
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactTokensForETH(uint256,uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap).swapExactTokensForETH(
                amountIn,
                amountOutMin,
                path,
                to_,
                deadline
            );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapETHForExactTokens(uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountOut,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(data[4:], (uint256, address[], address, uint256));
            IUniswapV2Router02(_sushiSwap).swapETHForExactTokens(
                amountOut,
                path,
                to_,
                deadline
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
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap)
                .swapExactTokensForTokensSupportingFeeOnTransferTokens(
                    amountIn,
                    amountOutMin,
                    path,
                    to_,
                    deadline
                );
        } else if (
            sig ==
            bytes4(
                keccak256(
                    "swapExactETHForTokensSupportingFeeOnTransferTokens(uint256,address[],address,uint256)"
                )
            )
        ) {
            (
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(data[4:], (uint256, address[], address, uint256));
            IUniswapV2Router02(_sushiSwap)
                .swapExactETHForTokensSupportingFeeOnTransferTokens(
                    amountOutMin,
                    path,
                    to_,
                    deadline
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
                uint256 amountIn,
                uint256 amountOutMin,
                address[] memory path,
                address to_,
                uint256 deadline
            ) = abi.decode(
                    data[4:],
                    (uint256, uint256, address[], address, uint256)
                );
            IUniswapV2Router02(_sushiSwap)
                .swapExactTokensForETHSupportingFeeOnTransferTokens(
                    amountIn,
                    amountOutMin,
                    path,
                    to_,
                    deadline
                );
        } else {
            emit EventLog(to, data);
        }
    }
}
