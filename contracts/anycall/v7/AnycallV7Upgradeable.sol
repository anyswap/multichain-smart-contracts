// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "../../common/Initializable.sol";
import "./interfaces/IAnycallExecutor.sol";
import "./interfaces/IAnycallConfig.sol";
import "./interfaces/IAnycallProxy.sol";

/// anycall proxy is a universal protocal to complete cross-chain interaction.
/// 1. the client call `AnycallV7Proxy::anyCall`
///         on the originating chain
///         to submit a request for a cross chain interaction
/// 2. the mpc network verify the request and call `AnycallV7Proxy::anyExec`
///         on the destination chain
///         to execute a cross chain interaction (exec `IApp::anyExecute`)
/// 3. if step 2 failed and step 1 has set allow fallback flags,
///         then emit a `LogAnyCall` log on the destination chain
///         to cause fallback on the originating chain (exec `IApp::anyFallback`)
contract AnyCallV7Upgradeable is IAnycallProxy, Initializable {
    // Context of the request on originating chain
    struct RequestContext {
        bytes32 txhash;
        address from;
        uint256 fromChainID;
        uint256 nonce;
        uint256 flags;
    }

    // anycall version
    string public constant ANYCALL_VERSION = "v7.0";

    // Flags constant
    uint256 public constant FLAG_MERGE_CONFIG_FLAGS = 0x1;
    uint256 public constant FLAG_PAY_FEE_ON_DEST = 0x1 << 1;
    uint256 public constant FLAG_ALLOW_FALLBACK = 0x1 << 2;

    address public admin;
    address public mpc;
    address public pendingMPC;

    bool public paused;

    // applications should give permission to this executor
    address public executor;

    // anycall config contract
    address public config;

    mapping(bytes32 => bytes32) public retryExecRecords;
    bool public retryWithPermit;

    mapping(bytes32 => bool) public execCompleted;
    uint256 nonce;

    uint256 private unlocked;
    modifier lock() {
        require(unlocked == 1, "locked");
        unlocked = 0;
        _;
        unlocked = 1;
    }

    event LogAnyCall(
        address indexed from,
        address to,
        bytes data,
        uint256 toChainID,
        uint256 flags,
        string appID,
        uint256 nonce,
        bytes extdata
    );
    event LogAnyCall(
        address indexed from,
        string to,
        bytes data,
        uint256 toChainID,
        uint256 flags,
        string appID,
        uint256 nonce,
        bytes extdata
    );

    event LogAnyExec(
        bytes32 indexed txhash,
        address indexed from,
        address indexed to,
        uint256 fromChainID,
        uint256 nonce,
        bool success,
        bytes result
    );

    event SetAdmin(address admin);
    event SetExecutor(address executor);
    event SetConfig(address config);
    event SetRetryWithPermit(bool flag);
    event SetPaused(bool paused);
    event ChangeMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 timestamp
    );
    event ApplyMPC(
        address indexed oldMPC,
        address indexed newMPC,
        uint256 timestamp
    );
    event StoreRetryExecRecord(
        bytes32 indexed txhash,
        address indexed from,
        address indexed to,
        uint256 fromChainID,
        uint256 nonce,
        bytes data
    );
    event DoneRetryExecRecord(
        bytes32 indexed txhash,
        address indexed from,
        uint256 fromChainID,
        uint256 nonce
    );

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _admin,
        address _mpc,
        address _executor,
        address _config
    ) external initializer {
        require(_mpc != address(0), "zero mpc address");

        unlocked = 1;

        admin = _admin;
        mpc = _mpc;
        executor = _executor;
        config = _config;

        emit ApplyMPC(address(0), _mpc, block.timestamp);
    }

    /// @dev Access control function
    modifier onlyMPC() {
        require(msg.sender == mpc, "only MPC");
        _;
    }

    /// @dev Access control function
    modifier onlyAdmin() {
        require(msg.sender == admin, "only admin");
        _;
    }

    /// @dev pausable control function
    modifier whenNotPaused() {
        require(!paused, "paused");
        _;
    }

    /// @dev Charge an account for execution costs on this chain
    /// @param _from The account to charge for execution costs
    modifier chargeDestFee(address _from, uint256 _flags) {
        if (_isSet(_flags, FLAG_PAY_FEE_ON_DEST)) {
            uint256 _prevGasLeft = gasleft();
            _;
            IAnycallConfig(config).chargeFeeOnDestChain(_from, _prevGasLeft);
        } else {
            _;
        }
    }

    /// @dev pay fee on source chain and return remaining amount
    function _paySrcFees(uint256 fees) internal {
        require(msg.value >= fees, "no enough src fee");
        if (fees > 0) {
            // pay fees
            (bool success, ) = mpc.call{value: fees}("");
            require(success);
        }
        if (msg.value > fees) {
            // return remaining amount
            (bool success, ) = msg.sender.call{value: msg.value - fees}("");
            require(success);
        }
    }

    /**
        @notice Submit a request for a cross chain interaction
        @param _to The target to interact with on `_toChainID`
        @param _data The calldata supplied for the interaction with `_to`
        @param _toChainID The target chain id to interact with
        @param _flags The flags of app on the originating chain
        @dev `_extdata` The extension data for call context
    */
    function anyCall(
        address _to,
        bytes calldata _data,
        uint256 _toChainID,
        uint256 _flags,
        bytes calldata /*_extdata*/
    ) external payable virtual whenNotPaused {
        (string memory _appID, uint256 _srcFees) = IAnycallConfig(config)
            .checkCall(msg.sender, _data, _toChainID, _flags);

        _paySrcFees(_srcFees);

        nonce++;
        emit LogAnyCall(
            msg.sender,
            _to,
            _data,
            _toChainID,
            _flags,
            _appID,
            nonce,
            ""
        );
    }

    /**
        @notice Submit a request for a cross chain interaction
        @param _to The target to interact with on `_toChainID`
        @param _data The calldata supplied for the interaction with `_to`
        @param _toChainID The target chain id to interact with
        @param _flags The flags of app on the originating chain
        @dev `_extdata` The extension data for call context
    */
    function anyCall(
        string calldata _to,
        bytes calldata _data,
        uint256 _toChainID,
        uint256 _flags,
        bytes calldata /*_extdata*/
    ) external payable virtual whenNotPaused {
        (string memory _appID, uint256 _srcFees) = IAnycallConfig(config)
            .checkCall(msg.sender, _data, _toChainID, _flags);

        _paySrcFees(_srcFees);

        nonce++;
        emit LogAnyCall(
            msg.sender,
            _to,
            _data,
            _toChainID,
            _flags,
            _appID,
            nonce,
            ""
        );
    }

    /**
        @notice Execute a cross chain interaction
        @dev Only callable by the MPC
        @param _to The cross chain interaction target
        @param _data The calldata supplied for interacting with target
        @param _appID The app identifier to check whitelist
        @param _ctx The context of the request on originating chain
        @param _extdata The extension data for execute context
    */
    function anyExec(
        address _to,
        bytes calldata _data,
        string calldata _appID,
        RequestContext calldata _ctx,
        bytes calldata _extdata
    )
        external
        virtual
        lock
        whenNotPaused
        chargeDestFee(_to, _ctx.flags)
        onlyMPC
    {
        IAnycallConfig(config).checkExec(_appID, _ctx.from, _to);

        bytes32 uniqID = calcUniqID(
            _ctx.txhash,
            _ctx.from,
            _ctx.fromChainID,
            _ctx.nonce
        );
        require(!execCompleted[uniqID], "exec completed");

        bool success = _execute(_to, _data, _ctx, _extdata);

        // set exec completed (dont care success status)
        execCompleted[uniqID] = true;

        if (!success) {
            if (_isSet(_ctx.flags, FLAG_ALLOW_FALLBACK)) {
                // Call the fallback on the originating chain
                nonce++;
                string memory appID = _appID; // fix Stack too deep
                emit LogAnyCall(
                    _to,
                    _ctx.from,
                    _data,
                    _ctx.fromChainID,
                    FLAG_PAY_FEE_ON_DEST, // pay fee on dest chain
                    appID,
                    nonce,
                    abi.encode(true) // indicate to exec anyFallback
                );
            } else {
                // Store retry record and emit a log
                bytes memory data = _data; // fix Stack too deep
                retryExecRecords[uniqID] = keccak256(abi.encode(_to, data));
                emit StoreRetryExecRecord(
                    _ctx.txhash,
                    _ctx.from,
                    _to,
                    _ctx.fromChainID,
                    _ctx.nonce,
                    data
                );
            }
        }
    }

    /// @notice execute through the executor (sandbox)
    function _execute(
        address _to,
        bytes calldata _data,
        RequestContext calldata _ctx,
        bytes calldata _extdata
    ) internal returns (bool success) {
        bytes memory result;

        try
            IAnycallExecutor(executor).execute(
                _to,
                _data,
                _ctx.from,
                _ctx.fromChainID,
                _ctx.nonce,
                _extdata
            )
        returns (bool succ, bytes memory res) {
            (success, result) = (succ, res);
        } catch Error(string memory reason) {
            result = bytes(reason);
        } catch (bytes memory reason) {
            result = reason;
        }

        emit LogAnyExec(
            _ctx.txhash,
            _ctx.from,
            _to,
            _ctx.fromChainID,
            _ctx.nonce,
            success,
            result
        );
    }

    function _isSet(uint256 _value, uint256 _testBits)
        internal
        pure
        returns (bool)
    {
        return (_value & _testBits) == _testBits;
    }

    /// @notice Calc unique ID
    function calcUniqID(
        bytes32 _txhash,
        address _from,
        uint256 _fromChainID,
        uint256 _nonce
    ) public pure returns (bytes32) {
        return keccak256(abi.encode(_txhash, _from, _fromChainID, _nonce));
    }

    /// @notice Retry stored exec record
    function retryExec(
        bytes32 _txhash,
        address _from,
        uint256 _fromChainID,
        uint256 _nonce,
        address _to,
        bytes calldata _data
    ) external virtual lock {
        require(!retryWithPermit || msg.sender == admin, "no permit");

        bytes32 uniqID = calcUniqID(_txhash, _from, _fromChainID, _nonce);
        require(execCompleted[uniqID], "no exec");
        require(
            retryExecRecords[uniqID] == keccak256(abi.encode(_to, _data)),
            "no retry record"
        );

        // Clear record
        delete retryExecRecords[uniqID];

        (bool success, bytes memory result) = IAnycallExecutor(executor)
            .execute(_to, _data, _from, _fromChainID, _nonce, "");
        require(success, string(result));

        emit DoneRetryExecRecord(_txhash, _from, _fromChainID, _nonce);
    }

    /// @notice Set executor
    function setExecutor(address _executor) external onlyMPC {
        executor = _executor;
        emit SetExecutor(_executor);
    }

    /// @notice Set Config
    function setConfig(address _config) external onlyMPC {
        config = _config;
        emit SetConfig(_config);
    }

    /// @notice Change mpc
    function changeMPC(address _mpc) external onlyMPC {
        pendingMPC = _mpc;
        emit ChangeMPC(mpc, _mpc, block.timestamp);
    }

    /// @notice Apply mpc
    function applyMPC() external {
        require(msg.sender == pendingMPC);
        emit ApplyMPC(mpc, pendingMPC, block.timestamp);
        mpc = pendingMPC;
        pendingMPC = address(0);
    }

    /// @notice Set admin
    function setAdmin(address _admin) external onlyMPC {
        admin = _admin;
        emit SetAdmin(_admin);
    }

    /// @dev set paused flag to pause/unpause functions
    function setPaused(bool _paused) external onlyAdmin {
        paused = _paused;
        emit SetPaused(_paused);
    }

    /// @notice Set retryWithPermit
    function setRetryWithPermit(bool _flag) external onlyAdmin {
        retryWithPermit = _flag;
        emit SetRetryWithPermit(_flag);
    }
}
