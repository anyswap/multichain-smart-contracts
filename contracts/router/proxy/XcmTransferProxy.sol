// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./AnycallProxyBase.sol";
import "../interfaces/ILocalAsset.sol";
import "../interfaces/Xtokens.sol";
import "../interfaces/Xtokens.sol";
import "../interfaces/Xtokens.sol";

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
        address xTokens_ // 0x0000000000000000000000000000000000000804
    ) AnycallProxyBase(mpc_, caller_) {
        xTokens = Xtokens(xTokens_);
    }

    struct AnycallInfo {
        uint256 amount;
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
        address _receiver,
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
            emit ExecFailed();
        }
    }

    function execXcmTransfer(
        address token,
        uint256 amount,
        bytes calldata data
    ) external returns (bool success, bytes memory result) {
        require(msg.sender == address(this));

        AnycallInfo memory anycallInfo = decode_anycall_info(data);
        Xtokens.Multilocation memory destination = anycallInfo.destination;
        uint64 weight = anycallInfo.weight;

        ILocalAsset localAsset = ILocalAsset(token);
        localAsset.mint(address(this), amount);

        xTokens.transfer(
            token,
            amount,
            destination,
            weight
        );
        emit XcmTransfer(token, amount);
        return (true, abi.encode(token, amount));
    }
}
