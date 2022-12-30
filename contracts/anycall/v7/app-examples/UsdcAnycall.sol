// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAppWithoutFallback.sol";
import "../interfaces/AnycallFlags.sol";
import "./AppBase.sol";

interface CircleBridge {
    function depositForBurnWithCaller(
        uint256 _amount,
        uint32 _destinationDomain,
        bytes32 _mintRecipient,
        address _burnToken,
        bytes32 _destinationCaller
    ) external returns (uint64 _nonce);
}

interface USDCMessageTransmitter {
    function receiveMessage(bytes memory _message, bytes calldata _attestation)
        external
        returns (uint64 _nonce);
}

contract UsdcAnycall is IAppWithoutFallback, AppBase {
    using SafeERC20 for IERC20;

    address usdcBridge;
    address usdcMessageTransmitter;
    address usdcToken;

    mapping(string => bool) public completedCallin; // key is swapid

    event LogCallin(
        address sender,
        address receiver,
        uint256 amount,
        uint256 fromChainId,
        string swapid
    );

    event LogCallout(
        address sender,
        uint256 amount,
        address receiver,
        uint256 toChainId
    );

    constructor(
        address _admin,
        address _callProxy,
        address _usdcBridge,
        address _usdcMessageTransmitter,
        address _usdcToken
    ) AppBase(_admin, _callProxy) {
        usdcBridge = _usdcBridge;
        usdcMessageTransmitter = _usdcMessageTransmitter;
        usdcToken = _usdcToken;
    }

    function toBytes32(address addr) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(addr)));
    }

    function callout(
        uint256 _amount,
        uint32 _destinationDomain,
        address _mintRecipient,
        address _burnToken,
        uint256 _toChainId,
        bool _payFeeOnSrc
    ) external payable {
        address _clientPeer = _getAndCheckPeer(_toChainId);

        uint256 oldCoinBalance;
        if (msg.value > 0) {
            oldCoinBalance = address(this).balance - msg.value;
        }
        // transfer usdc from msg.sender to this contract
        IERC20(usdcToken).safeTransferFrom(msg.sender, address(this), _amount);

        // approve usdc to usdcBridge
        IERC20(usdcToken).safeIncreaseAllowance(usdcBridge, _amount);

        // call depositForBurnWithCaller
        CircleBridge(usdcBridge).depositForBurnWithCaller(
            _amount,
            _destinationDomain,
            toBytes32(_mintRecipient),
            _burnToken,
            toBytes32(_clientPeer)
        );

        // encode the function inputs
        bytes memory _calldata = abi.encode(_amount, _mintRecipient);
        bytes memory _extdata = "usdc";
        if (_payFeeOnSrc) {
            IAnycallProxy(callProxy).anyCall{value: msg.value}(
                _clientPeer,
                _calldata,
                _toChainId,
                AnycallFlags.FLAG_NONE,
                _extdata
            );
        } else {
            IAnycallProxy(callProxy).anyCall(
                _clientPeer,
                _calldata,
                _toChainId,
                AnycallFlags.FLAG_PAY_FEE_ON_DEST,
                _extdata
            );
        }

        if (msg.value > 0) {
            uint256 newCoinBalance = address(this).balance;
            if (newCoinBalance > oldCoinBalance) {
                // return remaining fees
                (bool success, ) = msg.sender.call{
                    value: newCoinBalance - oldCoinBalance
                }("");
                require(success);
            }
        }

        emit LogCallout(msg.sender, _amount, _mintRecipient, _toChainId);
    }

    /// @notice Call by AnycallProxy's executor
    /// to execute a cross chain interaction on the destination chain
    function anyExecute(bytes calldata data)
        external
        override
        onlyExecutor
        returns (bool success, bytes memory result)
    {
        (address _sender, uint256 _fromChainId, ) = _getAndCheckContext();

        (
            bytes memory _calldata,
            string memory _swapid,
            bytes memory _message,
            bytes memory _attestation
        ) = abi.decode(data, (bytes, string, bytes, bytes));

        (uint256 _amount, address _mintRecipient) = abi.decode(
            _calldata,
            (uint256, address)
        );

        require(!completedCallin[_swapid], "completed");
        completedCallin[_swapid] = true;

        // use the message transmitter by circle to claim usdc
        USDCMessageTransmitter(usdcMessageTransmitter).receiveMessage(
            _message,
            _attestation
        );

        emit LogCallin(_sender, _mintRecipient, _amount, _fromChainId, _swapid);
        return (true, "");
    }
}
