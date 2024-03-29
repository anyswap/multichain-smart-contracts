# Anycall V7 Document

## related contracts

```text
contracts/anycall/v7/
├── AnycallExecutorProxy.sol
├── AnycallExecutorUpgradeable.sol
├── AnycallV7Config.sol
├── AnycallV7Proxy.sol
├── AnycallV7Upgradeable.sol
├── app-examples
│   ├── AppBase.sol
│   └── AppDemo.sol
├── interfaces
│   ├── AnycallFlags.sol
│   ├── IAnycallConfig.sol
│   ├── IAnycallExecutor.sol
│   ├── IAnycallProxy.sol
│   ├── IApp.sol
│   └── IFeePool.sol
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
    bytes   _data
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
    bytes   _data
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

### 5 deploy an example demo app contract (only for testing)

deploy `AppDemo` in `app-examples/AppDemo.sol`

```solidity
# _callProxy is the `AnycallV7Proxy` contract deployed in step 3

constructor(address _admin, address _callProxy)
```

call `AppDemo::setClientPeers` to set peers on supported chains

>Note: we must call setClientPeers on all the supported chains (connect each other)

```solidity
function setClientPeers(
    uint256[] _chainIds,
    address[] _peers
)
```

call `AppDemo::callout` to trigger a testing transaction

```solidity
function callout(
    string  message,
    address receiver,
    uint256 toChainId,
    uint256 flags
)
```

## app contract implementation attentions

This is dependent according to the concrete app implementation.

1. allow `AnycallExecutorProxy` to call into the app contract

2. call `AnycallV7Proxy::anyCall` to submit a request for a cross chain interaction

   ```solidity
   function anyCall(
        string  _to,
        bytes   _data,
        uint256 _toChainID,
        uint256 _flags,
        bytes   _extdata
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
        /// `_data` is the orignal interaction arguments exec on the destination chain
        function anyFallback(bytes calldata _data)
            external
            returns (bool success, bytes memory result);
    }
    ```

## changes compare with anycall v6

### 1. anycall v7 is split into 3 contract and 2 of them are upgradeable

- AnycallV7Config        (replaceable)
- AnycallExecutorProxy   (upgradeable)
- AnycallV7Proxy         (upgradeable)

### 2. `anyFallback` function prototype is changed

If the `App` want to support `fallback`,
it must support the following `anyFallback` interface.

anycall v6 version:

```solidity
function anyFallback(address _to, bytes calldata _data) external;
```

anycall v7 version:

```solidity
function anyFallback(bytes calldata _data)
    external
    returns (bool success, bytes memory result);
```

### 3. executor can distinguish `anyExectue` and `anyFallback`

in anycall v6 version, the `App` should encode call data with an selector.
and the `anyExecute` should identify which function to call.

in anycall v7 version, only the business related data is needed.
the `_data` in `function anyExecute(bytes calldata _data)`
and `function anyFallback(bytes calldata _data)` is same.

### 4. the default way of paying fee is changed

in anycall v6 version, defaults to `pay fee on destination chain`

in anycall v7 version, defaults to `pay fee on source chain`

### 5. if choose `pay fee on destination chain`, the deposit/withdraw pool is changed

in anycall v6 version, the deposit/withdraw pool is `AnyCallV6Proxy` contract address.
the fee is charged from address of `the app contract address on the source chain`

in anycall v7 version, the deposit/withdraw pool is `AnycallV7Config` contract address.
the fee is charged from address of `the app contract address on the destination chain` (because we may have multiple source chains)

>Note: the app must check the peer and context are right!
>
>ref. `_getAndCheckPeer` and `_getAndCheckContext` in `app-examples/AppBase.sol`
>
> if the app want to support `pay fee on destination chain`,
> the app is suggest to wrapper the interface `IFeePool` functions.
>
>ref. `depositFee` and `withdrawFee` in `app-examples/AppBase.sol`

### 6. AnyCallV6Proxy::anyCall function prototype is changed

anycall v6 version:

if `_fallback` is zero address, then disallow fallback.

`_flags` value are the following:

```solidity
FLAG_MERGE_CONFIG_FLAGS = 1;
FLAG_PAY_FEE_ON_SRC     = 2;
```

```solidity
function anyCall(
    address _to,
    bytes   _data,
    address _fallback,
    uint256 _toChainID,
    uint256 _flags
)
```

anycall v7 version:

`_flags` value are the following:

```solidity
FLAG_MERGE_CONFIG_FLAGS = 1;
FLAG_PAY_FEE_ON_DEST    = 2;
FLAG_ALLOW_FALLBACK     = 4;
```

if `FLAG_ALLOW_FALLBACK` is set, then allow fallback, otherwise disallow fallback.

```solidity
function anyCall(
    address _to,
    bytes   _data,
    uint256 _toChainID,
    uint256 _flags,
    bytes   _extdata /*reserved*/
)
```

### 7. add an overload anycall with a `string to` receiver

reserved for non-evm supports.

### 8. anycall is unlocked, allow call `anyCall` from `anyExecute`

this is usable when the application want to callback
to forward back the execution result, or call `anyCall` to
continue a new cross-chain interaction.
