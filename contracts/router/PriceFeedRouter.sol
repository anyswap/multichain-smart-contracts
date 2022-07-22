// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.10;

import "../access/MPCManageable.sol";

contract PriceFeedRouter is MPCManageable {
    // decimal of price
    uint256 public _decimal;
    // manager for price update
    mapping(address => bool) public _managers;
    // currency info
    mapping(uint256 => CurrencyInfo) private _currencyInfos;
    // currency threshold
    mapping(uint256 => Threshold) private _currencyThresholds;
    // default threshold
    Threshold public _defaultThreshold;
    // pause all token
    bool public _pauseAll;
    // pause one token
    mapping(uint256 => bool) public _pauseOne;

    event PriceUpdate(uint256 indexed chainID, uint256 price);
    event InitCurrencyInfo(
        uint256 indexed chainID,
        uint256 price,
        uint256 decimal
    );
    struct Threshold {
        uint48 low;
        uint80 mid;
        uint128 high;
    }
    struct CurrencyInfo {
        uint80 price;
        uint48 decimal;
        uint128 lastUpdateTime;
    }

    modifier onlyManagers() {
        require(_managers[msg.sender], "onlyManagers");
        _;
    }

    modifier notPuase(uint256 chainID) {
        require(!_pauseAll && !_pauseOne[chainID], "isPuase");
        _;
    }

    constructor(
        address mpc_,
        uint256 decimal_,
        address[] memory managers_,
        uint256[3] memory defaultThreshold_
    ) MPCManageable(mpc_) {
        require(
            defaultThreshold_[2] >= defaultThreshold_[1] &&
                defaultThreshold_[1] >= defaultThreshold_[0]
        );
        _decimal = decimal_;
        for (uint256 i = 0; i < managers_.length; i++) {
            _managers[managers_[i]] = true;
        }
        _defaultThreshold.low = uint48(defaultThreshold_[0]);
        _defaultThreshold.mid = uint80(defaultThreshold_[1]);
        _defaultThreshold.high = uint128(defaultThreshold_[2]);
    }

    function getCurrencyInfo(uint256 chainID)
        public
        view
        notPuase(chainID)
        returns (
            uint256 price,
            uint256 decimal,
            uint256 lastUpdateTime
        )
    {
        return (
            _currencyInfos[chainID].price,
            _currencyInfos[chainID].decimal,
            _currencyInfos[chainID].lastUpdateTime
        );
    }

    function getDecimal(uint256 chainID)
        public
        view
        notPuase(chainID)
        returns (uint256 decimal)
    {
        return _currencyInfos[chainID].decimal;
    }

    function getPrice(uint256 chainID)
        public
        view
        notPuase(chainID)
        returns (uint256 price)
    {
        return _currencyInfos[chainID].price;
    }

    function getSwapThreshold(uint256 chainID)
        public
        view
        notPuase(chainID)
        returns (
            uint256 low,
            uint256 mid,
            uint256 high
        )
    {
        if (_currencyThresholds[chainID].high != 0) {
            return (
                _currencyThresholds[chainID].low,
                _currencyThresholds[chainID].mid,
                _currencyThresholds[chainID].high
            );
        }
        return (
            _defaultThreshold.low,
            _defaultThreshold.mid,
            _defaultThreshold.high
        );
    }

    function setSwapThreshold(uint256 chainID, uint256[3] calldata threshold)
        external
        onlyManagers
    {
        require(threshold[2] >= threshold[1] && threshold[1] >= threshold[0]);
        _currencyThresholds[chainID].low = uint48(threshold[0]);
        _currencyThresholds[chainID].mid = uint80(threshold[1]);
        _currencyThresholds[chainID].high = uint128(threshold[2]);
    }

    function initCurrencyInfo(
        uint256 chainID,
        uint256 price,
        uint256 decimal
    ) external onlyManagers {
        _currencyInfos[chainID].price = uint80(price);
        _currencyInfos[chainID].decimal = uint48(decimal);
        _currencyInfos[chainID].lastUpdateTime = uint128(block.timestamp);
        emit InitCurrencyInfo(chainID, price, decimal);
    }

    function setPricesBatch(
        uint256[] calldata chainIDs,
        uint256[] calldata prices
    ) external onlyManagers {
        for (uint256 i = 0; i < chainIDs.length; i++) {
            setPrice(chainIDs[i], prices[i]);
        }
    }

    function setPrice(uint256 chainID, uint256 price) public onlyManagers {
        _currencyInfos[chainID].price = uint80(price);
        emit PriceUpdate(chainID, price);
    }

    function pauseAll(bool flag) external onlyMPC {
        require(_pauseAll != flag, "Not do anythings");
        _pauseAll = flag;
    }

    function pauseOne(uint256 chainID, bool flag) external onlyMPC {
        require(_pauseOne[chainID] != flag, "Not do anythings");
        _pauseOne[chainID] = flag;
    }

    function setManagersBatch(
        address[] calldata managers,
        bool[] calldata flags
    ) external onlyMPC {
        for (uint256 i = 0; i < managers.length; i++) {
            setManager(managers[i], flags[i]);
        }
    }

    function setManager(address manager, bool flag) public onlyMPC {
        require(_managers[manager] != flag, "Not do anythings");
        _managers[manager] = flag;
    }
}
