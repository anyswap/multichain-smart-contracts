# Anycall V7 Document

## related contracts

```text
contracts/anycall/v7
├── AnycallExecutorProxy.sol
├── AnycallExecutorUpgradeable.sol
├── AnycallV7Config.sol
├── AnycallV7Proxy.sol
├── AnycallV7Upgradeable.sol
├── app-examples
│   └── AppDemo.sol
├── interfaces
│   ├── IAnycallConfig.sol
│   ├── IAnycallExecutor.sol
│   └── IApp.sol
└── README.md
```

## deploy steps

Firstly we should know how to deploy *upgradeable* contract, take `AnycallExecutorProxy` for example:

1. deploy `AnycallExecutorUpgradeable`
2. deploy `ProxyAdmin` in `common/ProxyAdmin.sol`
3. deploy `AnycallExecutorProxy`
   >use `step 1` constract as the first argument (the logic impl)
   >
   >use `step 2` contract as the second `admin_` argument
   >
   >use apporate `initialize` data as the third `_data` argument

*Note: we can use a same `ProxyAdmin` contract to admin multiple upgradeable proxy contracts*

OK, now let's continue our deployment steps

### 1. deploy `AnycallExecutorProxy` as *upgradeable*

```solidity
constructor(
    address _executor,
    address admin_,
    bytes memory _data
)

# _data is the input data of calling the following function `AnycallExecutorUpgradeable::initialize`

function initialize(address _admin, address _mpc)
```

### 2. deploy `AnycallV7Config`

```solidity
constructor(
    address _admin,
    address _mpc,
    uint128 _premium,
    uint256 _mode
)
```

`AnycallV7Config` is the config contract which includes almost all the config settings operations. For example, set whitelist, app config, and fees, etc.

### 3. delpoy `AnycallV7Proxy` as *upgradeable*

```solidity
constructor(
    address _anycall,
    address admin_,
    bytes memory _data
)

# _data is the input data of calling the following function `AnyCallV7Upgradeable::initialize`

function initialize(
    address _admin,
    address _mpc,
    address _executor, # deployed in step 1
    address _config    # deployed in step 2
)
```

### 4 setting the other associations

1. call `AnycallV7Config::initAnycallContract`

    ```solidity
    # _anycallContract is AnycallV7Proxy deployed in step 3

    function initAnycallContract(address _anycallContract)
    ```

2. call `AnycallExecutorProxy::addSupportedCaller`

    ```solidity
    # caller is AnycallV7Proxy deployed in step 3

    function addSupportedCaller(address caller)
    ```

### 5 the app contract setting

This is dependent according to the concrete app implementation.

1. allow `AnycallExecutorProxy` to call into the app contract

2. call `AnycallV7Proxy::anyCall` to submit a request for a cross chain interaction

   ```solidity
   function anyCall(
        string calldata _to,
        bytes calldata _data,
        uint256 _toChainID,
        uint256 _flags,
        bytes calldata /*_extdata*/
    )
    ```

    `_extdata` is reserved for future upgradeation usage.

    `_flags` is bitwised value (it can be bitwise `or`ed).

    the meaning of each bit is the following:

    ```solidity
    # merge the app's config flags (`or`ed)
    uint256 FLAG_MERGE_CONFIG_FLAGS = 1;

    # pay fee on the destination chain,
    # otherwise pay fee on the source chain
    uint256 FLAG_PAY_FEE_ON_DEST = 2;

    # allow fallback if cross chain interaction failed on the destination chain
    uint256 FLAG_ALLOW_FALLBACK = 4;
    ```

3. how to prepare `pay fee on destination chain`

    if set pay fee on destination chain, then the caller (ie. the App contract) should
    `deposit/withdraw` fees (the Native gas token) to the config contract (`AnycallV7Config`).

4. the app should implement the interface `IApp.sol`

    ```solidity
    interface IApp {
        /// (required) call on the destination chain to exec the interaction
        function anyExecute(bytes calldata _data)
            external
            returns (bool success, bytes memory result);

        /// (optional,advised) call back on the originating chain if the cross chain interaction fails
        /// `_to` and `_data` are the orignal interaction arguments call on the destination chain
        function anyFallback(address _to, bytes calldata _data)
            external
            returns (bool success, bytes memory result);
    }
    ```
