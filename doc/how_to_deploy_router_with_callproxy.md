# How to deploy router + anycall

the follwing docmuent is explained with example of `router + sushiswap`

related smart contracts

```text
contracts/router/
├── AnyCallExecutor.sol
├── MultichainV7RouterSecurity.sol
├── MultichainV7Router.sol
└── proxy
    └── SushiSwapProxy.sol
```

Notation: the following steps are not the unique way.
we can change the orders and setting to complete the same job.

## 0. deploy association contracts

### 0.1. deploy `AnycallExecutor` in `AnyCallExecutor.sol`

`AnycallExecutor` is the delegator to execute contract calling (like a sandbox) to enfore security.

```solidity
constructor(address _admin, address _mpc)

function addAuthCallers(address[] calldata _callers) external
function removeAuthCallers(address[] calldata _callers) external

function isAuthCaller(address _caller) external view returns (bool)
```

### 0.2. deploy `MultichainV7RouterSecurity` in `MultichainV7RouterSecurity.sol`

`MultichainV7RouterSecurity` is a security guard for router v7 contract, and can be updated

```solidity
constructor(address _admin, address _mpc)

function addSupportedCaller(address caller) external
function removeSupportedCaller(address caller) external

function isSupportedCaller(address caller) external view returns (bool)
```

**Note: we can deploy an upgradeable router security contract by the following way:**

1. deploy `MultichainV7RouterSecurityUpgradeable`
2. deploy `MultichainV7RouterSecurityProxy`

    ```solidity
    constructor(
        address _roterSecurity,
        address admin_,
        bytes memory _data
    )
    ```

    the `_roterSecurity` argument is the contract address of `MultichainV7RouterSecurityUpgradeable` deployed in the above step
    the `admin_` is the proxy administrator who can upgrade the proxy implementation.
    the `_data` is the input data of calling `initialize` of `_roterSecurity` (starts with `0x485cc955`)

    ```solidity
    function initialize(address _admin, address _mpc) external
    ```

and now we can use `MultichainV7RouterSecurityProxy` as `MultichainV7RouterSecurity`, for example, call `addSupportedCaller` to add whitelist caller, etc.

## 1. deploy `MultichainV7Router` in `MultichainV7Router.sol`

```solidity
constructor(
    address _admin,
    address _mpc,
    address _wNATIVE,
    address _anycallExecutor,
    address _routerSecurity
)
```

`wNATIVE` and `anycallExecutor` is `immutable`, which means they can not be change after deployed.

set `_anycallExecutor` to the address of the contract `AnycallExecutor` deployed at step 0.1

set `_routerSecurity` to the address of the contract `MultichainV7RouterSecurity` deployed at step 0.2

## 2. deploy `AnycallProxy_SushiSwap` in `SushiSwapProxy.sol`

deploy `AnycallProxy_SushiSwap`

```solidity
constructor(
    address mpc_,
    address caller_,
    address sushiV2Factory_,
    address wNATIVE_
)
```

with `caller_` be the `AnycallExecutor` contract deployed at step 0.

## 3. setting the `MultichainV7Router`

1. we should add the deployed `MultichainV7Router` contract to auth callers of `AnycallExecutor`, by calling `AnycallExecutor::addAuthCallers`.

2. we should add the deployed `MultichainV7Router` contract to supported callers of `MultichainV7RouterSecurity`, by calling `MultichainV7RouterSecurity::addSupportedCaller`.

3. setting the call proxies which are allowed to be called in router

    ```solidity
    function addAnycallProxies(
        address[] proxies,
        bool[] acceptAnyTokenFlags
    )
    ```

    where `proxies` includes the `AnycallProxy` contract deployed in step 2

    and `acceptAnyTokenFlags` is flags tell us whether that `AnycallProxy` accept receiving `anyERC20Token`.

    If the flag is `false` and when the liquidity pool is not enough, then the router contract will record this swap and finish it.

    later anyone can retry the record to complete the swap when the liquidity pool is enough.

## 4. the exectuion steps

### 4.1 the user call a corresponding `swapout and call` method

1. token has no underlying

    ```solidity
    function anySwapOutAndCall(
        address token,
        string  to,
        uint256 amount,
        uint256 toChainID,
        string  anycallProxy,
        bytes   data
    )
    ```

2. token has normal underlying

    ```solidity
    function anySwapOutUnderlyingAndCall(
        address token,
        string  to,
        uint256 amount,
        uint256 toChainID,
        string  anycallProxy,
        bytes   data
    )
    ```

3. token has special underlying of wNative

    ```solidity
    function anySwapOutNativeAndCall(
        address token,
        string  to,
        uint256 toChainID,
        string  anycallProxy,
        bytes   data
    )
    ```

where,

> `address token` is the anytoken contract address on the `source` chain
>
> `string to` is the fallback receive address when exec failed on the `destination` chain
>
> `uint256 amount` is the value transfered on the `source` chain
>
> `uint256 toChainID` is the `destination` blockchain id to router into
>
> `string anycallProxy` is the call proxy contract on the `destination` chain to call into
>
> `bytes data` is the call data of calling the call proxy contract

### 4.2 the mpc call a corresponding `swapin and exec` method

- `SwapInfo` is used in swapin series methods.

    ```solidity
    struct SwapInfo {
        bytes32 swapoutID;
        address token;
        address receiver;
        uint256 amount;
        uint256 fromChainID;
    }
    ```

1. token has no underlying

    ```solidity
    function anySwapInAndExec(
        string   swapID,
        SwapInfo swapInfo,
        address  anycallProxy,
        bytes    data
    )
    ```

2. token has underlying

    ```solidity
    function anySwapInUnderlyingAndExec(
        string calldata swapID,
        SwapInfo calldata swapInfo,
        address anycallProxy,
        bytes calldata data
    )
    ```

### 4.3 retry swapin and exec

- retry swapin and exec when `retryRecords` exist (only happen when the underlying liquidity is not enough and the `anycallProxy` set flag `acceptAnyToken` to false)

    ```solidity
    function retrySwapinAndExec(
        string   swapID,
        SwapInfo swapInfo,
        address  anycallProxy,
        bytes    data,
        bool     dontExec
    )
    ```

Note: `swapInfo.receiver` is the `fallback receive address` when exec failed.

1. it can only be called by `swapInfo.receiver` or `admin`.
2. if `dontExec` is `true`, transfer the `underlying token` to the `swapInfo.receiver`.
3. if `dontExec` is `false`, retry swapin and execute as normal.
