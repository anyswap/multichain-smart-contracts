// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "../access/MPCManageable.sol";

contract GasConvertRouter is MPCManageable {
    uint256 public convertThreshold;
    mapping(bytes32 => bool) public txHashList;

    event LogGasConvertOut(
        address indexed from,
        string indexed to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID
    );
    event LogGasConvertIn(
        bytes32 txHash,
        address indexed to,
        uint256 amount,
        uint256 fromChainID,
        uint256 toChainID
    );
    event ChangeConvertThreshold(uint256 oldThreshold, uint256 newThreshold);
    event Withdraw(address to, uint256 amount);

    constructor(address _mpc, uint256 _convertThreshold) MPCManageable(_mpc) {
        convertThreshold = _convertThreshold;
    }

    receive() external payable {}

    modifier thresholdCheck(uint256 value) {
        require(
            value <= convertThreshold,
            "AnyswapV1GasRouter: threshold exceeded"
        );
        _;
    }

    modifier balanceCheck(uint256 amount) {
        require(
            address(this).balance >= amount,
            "AnyswapV1GasRouter: balance exceeded"
        );
        _;
    }

    function setConvertThreshold(uint256 newThreshold) external onlyMPC {
        emit ChangeConvertThreshold(convertThreshold, newThreshold);
        convertThreshold = newThreshold;
    }

    function gasConvertOut(string calldata to, uint256 toChainID)
        external
        payable
        thresholdCheck(msg.value)
    {
        emit LogGasConvertOut(
            msg.sender,
            to,
            msg.value,
            block.chainid,
            toChainID
        );
    }

    function gasConvertIn(
        bytes32 txHash,
        address to,
        uint256 amount,
        uint256 fromChainID
    ) external onlyMPC balanceCheck(amount) {
        require(!txHashList[txHash], "AnyswapV1GasRouter: txHash exists");

        txHashList[txHash] = true;
        payable(to).transfer(amount);
        emit LogGasConvertIn(txHash, to, amount, fromChainID, block.chainid);
    }

    function withdraw(address to, uint256 amount)
        external
        onlyMPC
        balanceCheck(amount)
    {
        payable(to).transfer(amount);
        emit Withdraw(to, amount);
    }
}
