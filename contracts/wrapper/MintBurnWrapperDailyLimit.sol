// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../access/AdminPausableControl.sol";

// TokenType token type enumerations (*required* by the multichain front-end)
// When in `need approve` situations, the user should approve to this wrapper contract,
// not to the Router contract, and not to the target token to be wrapped.
// If not, this wrapper will fail its function.
enum TokenType {
    MintBurnAny, // mint and burn(address from, uint256 amount), don't need approve
    MintBurnFrom, // mint and burnFrom(address from, uint256 amount), need approve
    MintBurnSelf, // mint and burn(uint256 amount), call transferFrom first, need approve
    Transfer, // transfer and transferFrom, need approve
    TransferDeposit, // transfer and transferFrom, deposit and withdraw, need approve, block when lack of liquidity
    TransferDeposit2 // transfer and transferFrom, deposit and withdraw, need approve, don't block when lack of liquidity
}

// IRouterMintBurn interface required for Multichain Router Dapp
// `mint` and `burn` is required by the router contract
// `token` and `tokenType` is required by the front-end
interface IRouterMintBurn {
    function mint(address to, uint256 amount) external returns (bool);

    function burn(address from, uint256 amount) external returns (bool);

    function token() external view returns (address);

    function tokenType() external view returns (TokenType);
}

// ITokenMintBurn is the interface the target token to be wrapped actually supports.
// We should adjust these functions according to the token itself,
// and wrapper them to support `IRouterMintBurn`
interface ITokenMintBurn {
    function mint(address _to, uint256 _value) external returns (bool);

    function burn(address _who, uint256 _value) external;
}

/*
 * There are three roles.
 * 1. operator: minter, burner
 * 3. contract admin: add/remove operator, callToken, setting limit
 */
contract MintBurnWrapperDailyLimit is IRouterMintBurn, AdminPausableControl {
    // pausable control roles
    bytes32 public constant PAUSE_MINT_ROLE = keccak256("PAUSE_MINT_ROLE");
    bytes32 public constant PAUSE_BURN_ROLE = keccak256("PAUSE_BURN_ROLE");
    bytes32 public constant PAUSE_CALLTOKEN_ROLE =
        keccak256("PAUSE_CALLTOKEN_ROLE");

    // the target token to be wrapped, must support `ITokenMintBurn`
    address public override token;
    // token type should be consistent with the `TokenType` context
    TokenType public constant override tokenType = TokenType.MintBurnAny;

    mapping(address => bool) public operators;

    // if supply is set to `type(uint256).max`, then disable supply checking.
    // otherwise the operator cannot burn token amount exceeds its mint amount.
    mapping(address => uint256) public operatorSupply;

    uint256 public perMintLimit;
    uint256 public dailyMintLimit;
    mapping(address => uint256) public operatorDailyMintLimit;

    mapping(uint256 => uint256) public totalDailyMinted;
    mapping(address => mapping(uint256 => uint256)) public operatorDailyMinted;

    event PerMintLimitChanged(uint256 prev, uint256 current);
    event OperatorDailyMintLimitChanged(
        uint256 prev,
        uint256 current,
        address operator
    );
    event DailyMintLimitChanged(uint256 prev, uint256 current);

    uint256 public perBurnLimit;
    uint256 public dailyBurnLimit;
    mapping(address => uint256) public operatorDailyBurnLimit;

    mapping(uint256 => uint256) public totalDailyBurned;
    mapping(address => mapping(uint256 => uint256)) public operatorDailyBurned;

    event PerBurnLimitChanged(uint256 prev, uint256 current);
    event OperatorDailyBurnLimitChanged(
        uint256 prev,
        uint256 current,
        address operator
    );
    event DailyBurnLimitChanged(uint256 prev, uint256 current);

    event OperatorAdded(address operator);
    event OperatorRemoved(address operator);

    modifier isOperator() {
        require(operators[msg.sender] == true);
        _;
    }

    constructor(address _token, address _admin) AdminPausableControl(_admin) {
        token = _token;
    }

    function minterBurner() internal view returns (ITokenMintBurn) {
        return ITokenMintBurn(token);
    }

    // Owner function

    function addOperator(address addr) external onlyAdmin {
        emit OperatorAdded(addr);
        operators[addr] = true;
    }

    function removeOperator(address addr) external onlyAdmin {
        emit OperatorRemoved(addr);
        delete operators[addr];
    }

    function callToken(bytes calldata data)
        external
        payable
        onlyAdmin
        whenNotPaused(PAUSE_CALLTOKEN_ROLE)
        returns (bool)
    {
        (bool success, ) = token.call{value: msg.value}(data);
        require(success);
        return true;
    }

    function setOperatorSupply(address addr, uint256 amount)
        external
        onlyAdmin
    {
        operatorSupply[addr] = amount;
    }

    // Limit setting functions

    function setDailyMintLimit(uint256 amount) external onlyAdmin {
        emit DailyMintLimitChanged(dailyMintLimit, amount);
        dailyMintLimit = amount;
    }

    function setPerMintLimit(uint256 amount) external onlyAdmin {
        emit PerMintLimitChanged(perMintLimit, amount);
        perMintLimit = amount;
    }

    function setOperatorDailyMintLimit(uint256 amount, address operator)
        external
        onlyAdmin
    {
        emit OperatorDailyMintLimitChanged(
            operatorDailyMintLimit[operator],
            amount,
            operator
        );
        operatorDailyMintLimit[operator] = amount;
    }

    function setDailyBurnLimit(uint256 amount) external onlyAdmin {
        emit DailyBurnLimitChanged(dailyBurnLimit, amount);
        dailyBurnLimit = amount;
    }

    function setPerBurnLimit(uint256 amount) external onlyAdmin {
        emit PerBurnLimitChanged(perBurnLimit, amount);
        perBurnLimit = amount;
    }

    function setOperatorDailyBurnLimit(uint256 amount, address operator)
        external
        onlyAdmin
    {
        emit OperatorDailyBurnLimitChanged(
            operatorDailyBurnLimit[operator],
            amount,
            operator
        );
        operatorDailyBurnLimit[operator] = amount;
    }

    // Operator functions, or co-minter functions.
    function mint(address _to, uint256 _value)
        external
        override
        isOperator
        whenNotPaused(PAUSE_MINT_ROLE)
        returns (bool)
    {
        if (perMintLimit > 0) {
            require(_value <= perMintLimit, "Exceed per mint limit");
        }
        uint256 _currentDay = getCurrentDay();
        uint256 _operatorDailyMintLimit = operatorDailyMintLimit[msg.sender];
        uint256 _operatorDailyMinted = operatorDailyMinted[msg.sender][
            _currentDay
        ];
        if (_operatorDailyMintLimit > 0) {
            require(
                _value + _operatorDailyMinted <= _operatorDailyMintLimit,
                "Exceed operator day limit"
            );
        }
        uint256 _totalDailyMinted = totalDailyMinted[_currentDay];
        if (dailyMintLimit > 0) {
            require(
                _value + _totalDailyMinted <= dailyMintLimit,
                "Exceed day limit"
            );
        }

        bool res = minterBurner().mint(_to, _value);
        if (res) {
            uint256 _operatorSupply = operatorSupply[msg.sender];
            if (_operatorSupply != type(uint256).max) {
                operatorSupply[msg.sender] = _operatorSupply + _value;
            }
            totalDailyMinted[_currentDay] = _totalDailyMinted + _value;
            operatorDailyMinted[msg.sender][_currentDay] =
                _operatorDailyMinted +
                _value;
        }

        return res;
    }

    function burn(address _who, uint256 _value)
        external
        override
        isOperator
        whenNotPaused(PAUSE_BURN_ROLE)
        returns (bool)
    {
        if (perBurnLimit > 0) {
            require(_value <= perBurnLimit, "Exceed per burn limit");
        }
        uint256 _currentDay = getCurrentDay();
        uint256 _operatorDailyBurnLimit = operatorDailyBurnLimit[msg.sender];
        uint256 _operatorDailyBurned = operatorDailyBurned[msg.sender][
            _currentDay
        ];
        if (_operatorDailyBurnLimit > 0) {
            require(
                _value + _operatorDailyBurned <= _operatorDailyBurnLimit,
                "Exceed operator day limit"
            );
        }
        uint256 _totalDailyBurned = totalDailyBurned[_currentDay];
        if (dailyBurnLimit > 0) {
            require(
                _value + _totalDailyBurned <= dailyBurnLimit,
                "Exceed day limit"
            );
        }

        minterBurner().burn(_who, _value);

        uint256 _operatorSupply = operatorSupply[msg.sender];
        if (_operatorSupply != type(uint256).max) {
            require(_value <= _operatorSupply, "Exceed operator supply");
            operatorSupply[msg.sender] = _operatorSupply - _value;
        }
        totalDailyBurned[_currentDay] = _totalDailyBurned + _value;
        operatorDailyBurned[msg.sender][_currentDay] =
            _operatorDailyBurned +
            _value;

        return true;
    }

    // Utility function
    function getCurrentDay() public view returns (uint256) {
        return block.timestamp / 1 days;
    }
}
