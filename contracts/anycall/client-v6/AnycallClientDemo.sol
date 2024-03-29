// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.6;

import "../../access/AdminControl.sol";

interface IApp {
    function anyExecute(bytes calldata _data)
        external
        returns (bool success, bytes memory result);
}

interface IAnycallExecutor {
    function context()
        external
        returns (
            address from,
            uint256 fromChainID,
            uint256 nonce
        );
}

interface IAnycallV6Proxy {
    function executor() external view returns (address);

    function anyCall(
        address _to,
        bytes calldata _data,
        address _fallback,
        uint256 _toChainID,
        uint256 _flags
    ) external payable;
}

abstract contract AnycallClientBase is IApp, AdminControl {
    address public callProxy;
    address public executor;

    // associated client app on each chain
    mapping(uint256 => address) public clientPeers; // key is chainId

    modifier onlyExecutor() {
        require(msg.sender == executor, "AnycallClient: onlyExecutor");
        _;
    }

    constructor(address _admin, address _callProxy) AdminControl(_admin) {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallV6Proxy(callProxy).executor();
    }

    receive() external payable {
        require(
            msg.sender == callProxy,
            "AnycallClient: receive from forbidden sender"
        );
    }

    function setCallProxy(address _callProxy) external onlyAdmin {
        require(_callProxy != address(0));
        callProxy = _callProxy;
        executor = IAnycallV6Proxy(callProxy).executor();
    }

    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peers
    ) external onlyAdmin {
        require(_chainIds.length == _peers.length);
        for (uint256 i = 0; i < _chainIds.length; i++) {
            clientPeers[_chainIds[i]] = _peers[i];
        }
    }
}

contract AnycallClientDemo is AnycallClientBase {
    event LogCallin(
        string message,
        address sender,
        address receiver,
        uint256 fromChainId
    );
    event LogCallout(
        string message,
        address sender,
        address receiver,
        uint256 toChainId
    );
    event LogCalloutFail(
        string message,
        address sender,
        address receiver,
        uint256 toChainId
    );

    constructor(address _admin, address _callProxy)
        AnycallClientBase(_admin, _callProxy)
    {}

    /// @dev Call by the user to submit a request for a cross chain interaction
    /// flags is 0 means pay fee on destination chain
    /// flags is 2 means pay fee on source chain
    function callout(
        string calldata message,
        address receiver,
        uint256 toChainId,
        uint256 flags
    ) external payable {
        address clientPeer = clientPeers[toChainId];
        require(clientPeer != address(0), "AnycallClient: no dest client");

        uint256 oldCoinBalance;
        if (msg.value > 0) {
            oldCoinBalance = address(this).balance - msg.value;
        }

        // encode with `anyExecute` selector
        bytes memory data = abi.encodeWithSelector(
            this.anyExecute.selector,
            message,
            msg.sender,
            receiver,
            toChainId
        );
        IAnycallV6Proxy(callProxy).anyCall{value: msg.value}(
            clientPeer,
            data,
            address(this), // has fallback processing in this contract
            toChainId,
            flags
        );

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

        emit LogCallout(message, msg.sender, receiver, toChainId);
    }

    /// @notice Call by `AnycallProxy` to execute a cross chain interaction on the destination chain
    function anyExecute(bytes calldata data)
        external
        override
        onlyExecutor
        returns (bool success, bytes memory result)
    {
        bytes4 selector = bytes4(data[:4]);
        if (selector == this.anyExecute.selector) {
            (string memory message, address sender, address receiver, ) = abi
                .decode(data[4:], (string, address, address, uint256));

            (address from, uint256 fromChainId, ) = IAnycallExecutor(executor)
                .context();
            require(
                clientPeers[fromChainId] == from,
                "AnycallClient: wrong context"
            );

            // Testing: add a condition of execute failure situation here to test fallbak function
            require(
                bytes(message).length < 10,
                "AnycallClient: message too long"
            );

            emit LogCallin(message, sender, receiver, fromChainId);
        } else if (selector == 0xa35fe8bf) {
            // bytes4(keccak256('anyFallback(address,bytes)'))
            (address _to, bytes memory _data) = abi.decode(
                data[4:],
                (address, bytes)
            );
            anyFallback(_to, _data);
        } else {
            return (false, "unknown selector");
        }
        return (true, "");
    }

    function anyFallback(address to, bytes memory data) internal {
        (address _from, , ) = IAnycallExecutor(executor).context();
        require(_from == address(this), "AnycallClient: wrong context");

        (
            bytes4 selector,
            string memory message,
            address sender,
            address receiver,
            uint256 toChainId
        ) = abi.decode(data, (bytes4, string, address, address, uint256));

        require(
            selector == this.anyExecute.selector,
            "AnycallClient: wrong fallback data"
        );
        require(
            clientPeers[toChainId] == to,
            "AnycallClient: mismatch dest client"
        );

        emit LogCalloutFail(message, sender, receiver, toChainId);
    }
}
