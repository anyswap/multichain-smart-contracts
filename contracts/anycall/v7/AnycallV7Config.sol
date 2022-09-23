// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity ^0.8.10;

import "./interfaces/IAnycallConfig.sol";

contract AnycallV7Config is IAnycallConfig {
    // Packed fee information (only 1 storage slot)
    struct FeeData {
        uint128 accruedFees;
        uint128 premium;
    }

    // App config
    struct AppConfig {
        address app; // the application contract address
        address appAdmin; // account who admin the application's config
        uint256 appFlags; // flags of the application
    }

    // Src fee is (baseFees + msg.data.length*feesPerByte)
    struct SrcFeeConfig {
        uint256 baseFees;
        uint256 feesPerByte;
    }

    // Flags constant
    uint256 public constant FLAG_MERGE_CONFIG_FLAGS = 0x1;
    uint256 public constant FLAG_PAY_FEE_ON_DEST = 0x1 << 1;

    // App Modes constant
    uint256 public constant APPMODE_USE_CUSTOM_SRC_FEES = 0x1;

    // Modes constant
    uint256 public constant PERMISSIONLESS_MODE = 0x1;
    uint256 public constant FREE_MODE = 0x1 << 1;

    // Extra cost of execution (SSTOREs.SLOADs,ADDs,etc..)
    // TODO: analysis to verify the correct overhead gas usage
    uint256 constant EXECUTION_OVERHEAD = 100000;

    // key is app address
    mapping(address => string) public appIdentifier;

    // key is appID, a unique identifier for each project
    mapping(string => AppConfig) public appConfig;
    mapping(string => mapping(address => bool)) public appExecWhitelist;
    mapping(string => address[]) public appHistoryWhitelist;
    mapping(string => bool) public appBlacklist;
    mapping(uint256 => SrcFeeConfig) public srcDefaultFees; // key is chainID
    mapping(string => mapping(uint256 => SrcFeeConfig)) public srcCustomFees;
    mapping(string => uint256) public appDefaultModes;
    mapping(string => mapping(uint256 => uint256)) public appCustomModes;

    mapping(address => bool) public isAdmin;
    address[] public admins;

    address public mpc;
    address public pendingMPC;

    uint256 public mode;

    uint256 public minReserveBudget;
    mapping(address => uint256) public executionBudget;
    FeeData private _feeData;

    address public anycallContract;

    /// @dev Access control function
    modifier onlyMPC() {
        require(msg.sender == mpc, "only MPC");
        _;
    }

    /// @dev Access control function
    modifier onlyAdmin() {
        require(isAdmin[msg.sender], "only admin");
        _;
    }

    /// @dev Access control function
    modifier onlyAnycallContract() {
        require(msg.sender == anycallContract, "only anycall contract");
        _;
    }

    event InitAnycallContract(address);
    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event SetBlacklist(string appID, bool flag);
    event SetWhitelist(string appID, address indexed whitelist, bool flag);
    event UpdatePremium(uint256 oldPremium, uint256 newPremium);
    event AddAdmin(address admin);
    event RemoveAdmin(address admin);
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
    event SetAppConfig(
        string appID,
        address indexed app,
        address indexed appAdmin,
        uint256 appFlags
    );
    event UpgradeApp(
        string appID,
        address indexed oldApp,
        address indexed newApp
    );

    constructor(
        address _admin,
        address _mpc,
        uint128 _premium,
        uint256 _mode
    ) {
        require(_mpc != address(0), "zero mpc address");
        if (_admin != address(0)) {
            isAdmin[_admin] = true;
            admins.push(_admin);
        }
        if (_mpc != _admin) {
            isAdmin[_mpc] = true;
            admins.push(_mpc);
        }

        mpc = _mpc;
        _feeData.premium = _premium;
        mode = _mode;

        emit ApplyMPC(address(0), _mpc, block.timestamp);
        emit UpdatePremium(0, _premium);
    }

    /// @dev Init the corresponding anycall contract
    function initAnycallContract(address _anycallContract) external onlyAdmin {
        require(anycallContract == address(0), "inited");
        anycallContract = _anycallContract;
        emit InitAnycallContract(anycallContract);
    }

    function checkCall(
        address _sender,
        bytes calldata _data,
        uint256 _toChainID,
        uint256 _flags
    ) external view returns (string memory _appID, uint256 _srcFees) {
        _appID = appIdentifier[_sender];
        require(!appBlacklist[_appID], "blacklist");

        bool _permissionlessMode = _isSet(mode, PERMISSIONLESS_MODE);
        if (!_permissionlessMode) {
            require(appExecWhitelist[_appID][_sender], "no permission");
        }

        if (!_isSet(mode, FREE_MODE)) {
            AppConfig storage config = appConfig[_appID];
            require(
                (_permissionlessMode && config.app == address(0)) ||
                    _sender == config.app,
                "app not exist"
            );

            if (
                _isSet(_flags, FLAG_MERGE_CONFIG_FLAGS) && config.app == _sender
            ) {
                _flags |= config.appFlags;
            }

            if (!_isSet(_flags, FLAG_PAY_FEE_ON_DEST)) {
                _srcFees = _calcSrcFees(_appID, _toChainID, _data.length);
            }
        }
    }

    function checkExec(
        string calldata _appID,
        address _from,
        address _to
    ) external view {
        require(!appBlacklist[_appID], "blacklist");

        if (!_isSet(mode, PERMISSIONLESS_MODE)) {
            require(appExecWhitelist[_appID][_to], "no permission");
        }

        if (!_isSet(mode, FREE_MODE)) {
            require(
                executionBudget[_from] >= minReserveBudget,
                "less than min budget"
            );
        }
    }

    /// @dev Charge an account for execution costs on this chain
    /// @param _from The account to charge for execution costs
    /// @param _prevGasLeft The previous value of `gasleft()`
    function chargeFeeOnDestChain(address _from, uint256 _prevGasLeft)
        external
        onlyAnycallContract
    {
        if (!_isSet(mode, FREE_MODE)) {
            uint256 gasUsed = _prevGasLeft + EXECUTION_OVERHEAD - gasleft();
            uint256 totalCost = gasUsed * (tx.gasprice + _feeData.premium);
            uint256 budget = executionBudget[_from];
            require(budget > totalCost, "no enough budget");
            executionBudget[_from] = budget - totalCost;
            _feeData.accruedFees += uint128(totalCost);
        }
    }

    function _isSet(uint256 _value, uint256 _testBits)
        internal
        pure
        returns (bool)
    {
        return (_value & _testBits) == _testBits;
    }

    /// @notice Deposit native currency crediting `_account` for execution costs on this chain
    /// @param _account The account to deposit and credit for
    function deposit(address _account) external payable {
        executionBudget[_account] += msg.value;
        emit Deposit(_account, msg.value);
    }

    /// @notice Withdraw a previous deposit from your account
    /// @param _amount The amount to withdraw from your account
    function withdraw(uint256 _amount) external {
        executionBudget[msg.sender] -= _amount;
        emit Withdraw(msg.sender, _amount);
        (bool success, ) = msg.sender.call{value: _amount}("");
        require(success);
    }

    /// @notice Withdraw all accrued execution fees
    /// @dev The MPC is credited in the native currency
    function withdrawAccruedFees() external {
        uint256 fees = _feeData.accruedFees;
        _feeData.accruedFees = 0;
        (bool success, ) = mpc.call{value: fees}("");
        require(success);
    }

    /// @notice Set app blacklist
    function setBlacklist(string calldata _appID, bool _flag)
        external
        onlyAdmin
    {
        appBlacklist[_appID] = _flag;
        emit SetBlacklist(_appID, _flag);
    }

    /// @notice Set app blacklist in batch
    function setBlacklists(string[] calldata _appIDs, bool _flag)
        external
        onlyAdmin
    {
        for (uint256 i = 0; i < _appIDs.length; i++) {
            this.setBlacklist(_appIDs[i], _flag);
        }
    }

    /// @notice Set the premimum for cross chain executions
    /// @param _premium The premium per gas
    function setPremium(uint128 _premium) external onlyAdmin {
        emit UpdatePremium(_feeData.premium, _premium);
        _feeData.premium = _premium;
    }

    /// @notice Set minimum exection budget for cross chain executions
    /// @param _minBudget The minimum exection budget
    function setMinReserveBudget(uint128 _minBudget) external onlyAdmin {
        minReserveBudget = _minBudget;
    }

    /// @notice Set mode
    function setMode(uint256 _mode) external onlyAdmin {
        mode = _mode;
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

    /// @notice Get the total accrued fees in native currency
    /// @dev Fees increase when executing cross chain requests
    function accruedFees() external view returns (uint128) {
        return _feeData.accruedFees;
    }

    /// @notice Get the gas premium cost
    /// @dev This is similar to priority fee in eip-1559, except instead of going
    ///     to the miner it is given to the MPC executing cross chain requests
    function premium() external view returns (uint128) {
        return _feeData.premium;
    }

    /// @notice Add admin
    function addAdmin(address _admin) external onlyMPC {
        require(!isAdmin[_admin]);
        isAdmin[_admin] = true;
        admins.push(_admin);
        emit AddAdmin(_admin);
    }

    /// @notice Remove admin
    function removeAdmin(address _admin) external onlyMPC {
        require(isAdmin[_admin]);
        isAdmin[_admin] = false;
        uint256 length = admins.length;
        for (uint256 i = 0; i < length - 1; i++) {
            if (admins[i] == _admin) {
                admins[i] = admins[length - 1];
                break;
            }
        }
        admins.pop();
        emit RemoveAdmin(_admin);
    }

    /// @notice Get all admins
    function getAllAdmins() external view returns (address[] memory) {
        return admins;
    }

    /// @notice Init app config
    function initAppConfig(
        string calldata _appID,
        address _app,
        address _admin,
        uint256 _flags,
        address[] calldata _whitelist
    ) external onlyAdmin {
        require(bytes(_appID).length > 0, "empty appID");
        require(_app != address(0), "zero app address");

        AppConfig storage config = appConfig[_appID];
        require(config.app == address(0), "app exist");

        appIdentifier[_app] = _appID;

        config.app = _app;
        config.appAdmin = _admin;
        config.appFlags = _flags;

        address[] memory whitelist = new address[](1 + _whitelist.length);
        whitelist[0] = _app;
        for (uint256 i = 0; i < _whitelist.length; i++) {
            whitelist[i + 1] = _whitelist[i];
        }
        _setAppWhitelist(_appID, whitelist, true);

        emit SetAppConfig(_appID, _app, _admin, _flags);
    }

    /// @notice Update app config
    /// can be operated only by mpc or app admin
    /// the config.app will always keep unchanged here
    function updateAppConfig(
        address _app,
        address _admin,
        uint256 _flags,
        address[] calldata _whitelist
    ) external {
        string memory _appID = appIdentifier[_app];
        AppConfig storage config = appConfig[_appID];

        require(config.app == _app && _app != address(0), "app not exist");
        require(msg.sender == mpc || msg.sender == config.appAdmin, "forbid");

        if (_admin != address(0)) {
            config.appAdmin = _admin;
        }
        config.appFlags = _flags;
        if (_whitelist.length > 0) {
            _setAppWhitelist(_appID, _whitelist, true);
        }

        emit SetAppConfig(_appID, _app, _admin, _flags);
    }

    /// @notice Upgrade app
    /// can be operated only by mpc or app admin
    /// change config.app to a new address
    /// require the `_newApp` is not inited
    function upgradeApp(address _oldApp, address _newApp) external {
        string memory _appID = appIdentifier[_oldApp];
        AppConfig storage config = appConfig[_appID];

        require(
            config.app == _oldApp && _oldApp != address(0),
            "app not exist"
        );
        require(msg.sender == mpc || msg.sender == config.appAdmin, "forbid");
        require(bytes(appIdentifier[_newApp]).length == 0, "new app is inited");

        config.app = _newApp;

        emit UpgradeApp(_appID, _oldApp, _newApp);
    }

    /// @notice Add whitelist
    function addWhitelist(address _app, address[] memory _whitelist) external {
        string memory _appID = appIdentifier[_app];
        AppConfig storage config = appConfig[_appID];

        require(config.app == _app && _app != address(0), "app not exist");
        require(msg.sender == mpc || msg.sender == config.appAdmin, "forbid");

        _setAppWhitelist(_appID, _whitelist, true);
    }

    /// @notice Remove whitelist
    function removeWhitelist(address _app, address[] memory _whitelist)
        external
    {
        string memory _appID = appIdentifier[_app];
        AppConfig storage config = appConfig[_appID];

        require(config.app == _app && _app != address(0), "app not exist");
        require(msg.sender == mpc || msg.sender == config.appAdmin, "forbid");

        _setAppWhitelist(_appID, _whitelist, false);
    }

    function _setAppWhitelist(
        string memory _appID,
        address[] memory _whitelist,
        bool _flag
    ) internal {
        mapping(address => bool) storage whitelist = appExecWhitelist[_appID];
        address[] storage historyWhitelist = appHistoryWhitelist[_appID];
        address addr;
        for (uint256 i = 0; i < _whitelist.length; i++) {
            addr = _whitelist[i];
            if (whitelist[addr] == _flag) {
                continue;
            }
            if (_flag) {
                historyWhitelist.push(addr);
            }
            whitelist[addr] = _flag;
            emit SetWhitelist(_appID, addr, _flag);
        }
    }

    /// @notice Get history whitelist length
    function getHistoryWhitelistLength(string memory _appID)
        external
        view
        returns (uint256)
    {
        return appHistoryWhitelist[_appID].length;
    }

    /// @notice Get all history whitelist
    function getAllHistoryWhitelist(string memory _appID)
        external
        view
        returns (address[] memory)
    {
        return appHistoryWhitelist[_appID];
    }

    /// @notice Tidy history whitelist to be same with actual whitelist
    function tidyHistoryWhitelist(string memory _appID) external {
        mapping(address => bool) storage actualWhitelist = appExecWhitelist[
            _appID
        ];
        address[] storage historyWhitelist = appHistoryWhitelist[_appID];
        uint256 histLength = historyWhitelist.length;
        uint256 popIndex = histLength;
        address addr;
        for (uint256 i = 0; i < popIndex; ) {
            addr = historyWhitelist[i];
            if (actualWhitelist[addr]) {
                i++;
            } else {
                popIndex--;
                historyWhitelist[i] = historyWhitelist[popIndex];
            }
        }
        for (uint256 i = popIndex; i < histLength; i++) {
            historyWhitelist.pop();
        }
    }

    /// @notice Set default src fees
    function setDefaultSrcFees(
        uint256[] calldata _toChainIDs,
        uint256[] calldata _baseFees,
        uint256[] calldata _feesPerByte
    ) external onlyAdmin {
        uint256 length = _toChainIDs.length;
        require(length == _baseFees.length && length == _feesPerByte.length);

        for (uint256 i = 0; i < length; i++) {
            srcDefaultFees[_toChainIDs[i]] = SrcFeeConfig(
                _baseFees[i],
                _feesPerByte[i]
            );
        }
    }

    /// @notice Set custom src fees
    function setCustomSrcFees(
        address _app,
        uint256[] calldata _toChainIDs,
        uint256[] calldata _baseFees,
        uint256[] calldata _feesPerByte
    ) external onlyAdmin {
        string memory _appID = appIdentifier[_app];
        AppConfig storage config = appConfig[_appID];

        require(config.app == _app && _app != address(0), "app not exist");

        uint256 length = _toChainIDs.length;
        require(length == _baseFees.length && length == _feesPerByte.length);

        mapping(uint256 => SrcFeeConfig) storage _srcFees = srcCustomFees[
            _appID
        ];
        for (uint256 i = 0; i < length; i++) {
            _srcFees[_toChainIDs[i]] = SrcFeeConfig(
                _baseFees[i],
                _feesPerByte[i]
            );
        }
    }

    /// @notice Set app modes
    function setAppModes(
        address _app,
        uint256 _appDefaultMode,
        uint256[] calldata _toChainIDs,
        uint256[] calldata _appCustomModes
    ) external onlyAdmin {
        string memory _appID = appIdentifier[_app];
        AppConfig storage config = appConfig[_appID];
        require(config.app == _app && _app != address(0), "app not exist");

        uint256 length = _toChainIDs.length;
        require(length == _appCustomModes.length);

        appDefaultModes[_appID] = _appDefaultMode;

        for (uint256 i = 0; i < length; i++) {
            appCustomModes[_appID][_toChainIDs[i]] = _appCustomModes[i];
        }
    }

    /// @notice Calc fees
    function calcSrcFees(
        address _app,
        uint256 _toChainID,
        uint256 _dataLength
    ) external view returns (uint256) {
        string memory _appID = appIdentifier[_app];
        return _calcSrcFees(_appID, _toChainID, _dataLength);
    }

    /// @notice Calc fees
    function calcSrcFees(
        string calldata _appID,
        uint256 _toChainID,
        uint256 _dataLength
    ) external view returns (uint256) {
        return _calcSrcFees(_appID, _toChainID, _dataLength);
    }

    /// @notice Is use custom src fees
    function isUseCustomSrcFees(string memory _appID, uint256 _toChainID)
        public
        view
        returns (bool)
    {
        uint256 _appMode = appCustomModes[_appID][_toChainID];
        if (_isSet(_appMode, APPMODE_USE_CUSTOM_SRC_FEES)) {
            return true;
        }
        _appMode = appDefaultModes[_appID];
        return _isSet(_appMode, APPMODE_USE_CUSTOM_SRC_FEES);
    }

    function _calcSrcFees(
        string memory _appID,
        uint256 _toChainID,
        uint256 _dataLength
    ) internal view returns (uint256) {
        SrcFeeConfig memory customFees = srcCustomFees[_appID][_toChainID];
        uint256 customBaseFees = customFees.baseFees;
        uint256 customFeesPerBytes = customFees.feesPerByte;

        if (isUseCustomSrcFees(_appID, _toChainID)) {
            return customBaseFees + _dataLength * customFeesPerBytes;
        }

        SrcFeeConfig memory defaultFees = srcDefaultFees[_toChainID];
        uint256 defaultBaseFees = defaultFees.baseFees;
        uint256 defaultFeesPerBytes = defaultFees.feesPerByte;

        uint256 baseFees = (customBaseFees > defaultBaseFees)
            ? customBaseFees
            : defaultBaseFees;
        uint256 feesPerByte = (customFeesPerBytes > defaultFeesPerBytes)
            ? customFeesPerBytes
            : defaultFeesPerBytes;

        return baseFees + _dataLength * feesPerByte;
    }
}
