// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AnycallProxyBase.sol";
import "../interfaces/Xtokens.sol";
import "../interfaces/IXC20Wrapper.sol";

contract AnycallProxy_XcmTransfer is AnycallProxyBase {
    Xtokens public xTokens;

    using SafeERC20 for IERC20;

    event XcmTransfer(
        address indexed tokenAddress,
        uint256 amount
    );

    event ExecFailed();

    constructor(
        address mpc_,
        address caller_,
        // default address is 0x0000000000000000000000000000000000000804,
        // but it may be changed for test purposes
        address xTokens_
    ) AnycallProxyBase(mpc_, caller_) {
        xTokens = Xtokens(xTokens_);
    }

    struct AnycallInfo {
        Xtokens.Multilocation destination;
        uint64 weight;
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

    // impl `IAnycallProxy` interface
    // Note: take care of the situation when do the business failed.
    function exec(
        address token,
        address receiver,
        uint256 amount,
        bytes calldata data
    ) external onlyAuth returns (bool success, bytes memory result) {
        try this.execXcmTransfer(token, amount, data) returns (
            bool succ,
            bytes memory res
        ) {
            (success, result) = (succ, res);
        } catch Error(string memory reason) {
            result = bytes(reason);
        } catch (bytes memory reason) {
            result = reason;
        }
        if (!success) {
            // process failure situation (eg. return token)
            IERC20(token).safeTransfer(receiver, amount);
            emit ExecFailed();
        }
    }

    function execXcmTransfer(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result) {
        require(msg.sender == address(this));

        address xc20Token = IXC20Wrapper(token).token();
        require(
            xc20Token != address(0),
            "XcmTransferAnycallProxy: invalid xc20 token address"
        );

        AnycallInfo memory anycallInfo = decode_anycall_info(data);
        Xtokens.Multilocation memory destination = anycallInfo.destination;
        uint64 weight = anycallInfo.weight;

        xTokens.transfer(
            xc20Token,
            amount,
            destination,
            weight
        );
        emit XcmTransfer(xc20Token, amount);
        return (true, abi.encode(xc20Token, amount));
    }

    // this contract is designed as a handler (not token pool)
    // it should have no token balance, but if it has we can withdraw them
    function skim(address token, address to) external onlyMPC {
        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));
    }
}
