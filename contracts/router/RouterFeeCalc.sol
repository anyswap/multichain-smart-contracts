// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

abstract contract Ownable {
    address[2] private _owners;

    modifier onlyOwner() {
        require(msg.sender == _owners[0] || msg.sender == _owners[1], "only owner");
        _;
    }

    constructor (address[2] memory newOwners) {
        require(newOwners[0] != address(0)
            && newOwners[1] != address(0)
            && newOwners[0] != newOwners[1],
            "CTOR: owners are same or contain zero address");
        _owners = newOwners;
    }

    function owners() external view returns (address[2] memory) {
        return _owners;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "the new owner is the zero address");
        require(newOwner != _owners[0] && newOwner != _owners[1], "the new owner is existed");
        if (msg.sender == _owners[0]) {
            _owners[0] = newOwner;
        } else {
            _owners[1] = newOwner;
        }
    }
}

struct SwapConfig {
    uint256 MaximumSwap;
    uint256 MinimumSwap;
    uint256 BigValueThreshold;
    uint256 SwapFeeRatePerMillion;
    uint256 MaximumSwapFee;
    uint256 MinimumSwapFee;
}

interface IRouterSwapConfig {
    function getSwapConfig(address token) external view returns (SwapConfig memory);
    function isInBigValueWhitelist(address token, address sender) external view returns (bool);
}

contract RouterSwapConfig is IRouterSwapConfig, Ownable {
    modifier checkSwapConfig(SwapConfig memory config) {
        require(config.MaximumSwap > 0, "zero MaximumSwap");
        require(config.MinimumSwap > 0, "zero MinimumSwap");
        require(config.BigValueThreshold > 0, "zero BigValueThreshold");
        require(config.MaximumSwap >= config.MinimumSwap, "MaximumSwap < MinimumSwap");
        require(config.MaximumSwapFee >= config.MinimumSwapFee, "MaximumSwapFee < MinimumSwapFee");
        require(config.MinimumSwap >= config.MinimumSwapFee, "MinimumSwap < MinimumSwapFee");
        require(config.SwapFeeRatePerMillion < 1000000, "SwapFeeRatePerMillion >= 1000000");
        require(config.SwapFeeRatePerMillion > 0 || config.MaximumSwapFee == 0, "wrong MaximumSwapFee");
        _;
    }

    mapping(address => SwapConfig) _swapConfig;
    mapping(address => mapping(address => bool)) _isInBigValueWhitelist;

    constructor(address[2] memory _owners) Ownable(_owners) {
    }


    function getSwapConfig(address token) external view returns (SwapConfig memory) {
        return _swapConfig[token];
    }

    function isInBigValueWhitelist(address token, address sender) external view returns (bool) {
        return _isInBigValueWhitelist[token][sender];
    }

    function setSwapCofig(address token, SwapConfig memory config) external onlyOwner checkSwapConfig(config) {
        _swapConfig[token] = config;
    }

    function setBigValueWhitelist(address token, address sender, bool flag) external onlyOwner {
        _isInBigValueWhitelist[token][sender] = flag;
    }
}

// separate `RouterSwapConfig` (storage) and `RouterFeeCalc` (algorithm)
contract RouterFeeCalc is Ownable {
    address public routerSwapConfig;

    constructor(address _routerSwapConfig, address[2] memory _owners) Ownable(_owners) {
        routerSwapConfig = _routerSwapConfig;
    }

    function setRouterSwapConfig(address _routerSwapConfig) external onlyOwner {
        routerSwapConfig = _routerSwapConfig;
    }

    function getSwapConfig(address token) public view returns (SwapConfig memory) {
        return IRouterSwapConfig(routerSwapConfig).getSwapConfig(token);

    }

    function isInBigValueWhitelist(address token, address sender) public view returns (bool) {
        return IRouterSwapConfig(routerSwapConfig).isInBigValueWhitelist(token, sender);
    }

    function calcFee(address token, address sender, uint256 amount) external view returns (uint256 fee) {
        SwapConfig memory config = getSwapConfig(token);
        require(config.MaximumSwap > 0, "no swap config");
        bool isBigValWhitelist = isInBigValueWhitelist(token, sender);
        require(
            (amount >= config.MinimumSwap && amount <= config.MaximumSwap) || isBigValWhitelist,
            "wrong swap value"
        );
        if (isBigValWhitelist) {
            fee = config.MinimumSwapFee;
        } else if (config.SwapFeeRatePerMillion > 0) {
            fee = amount * config.SwapFeeRatePerMillion / 1000000;
            if (fee < config.MinimumSwapFee) {
                fee = config.MinimumSwapFee;
            } else if (fee > config.MaximumSwapFee) {
                fee = config.MaximumSwapFee;
            }
        }
        return fee;
    }
}
