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
    constructor(address _mpc)

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
```

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

and we should add the deployed `MultichainV7Router` contract to auth callers of `AnycallExecutor`, by calling `AnycallExecutor::addAuthCallers`.

and we should add the deployed `MultichainV7Router` contract to supported callers of `MultichainV7RouterSecurity`, by calling `MultichainV7RouterSecurity::addSupportedCaller`.

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

setting the call proxies which are allowed to be called in router

```solidity
    function addAnycallProxies(address[] memory proxies, bool[] memory acceptAnyTokenFlags) external onlyMPC
```

where `proxies` includes the `AnycallProxy` contract deployed in step 2

and `acceptAnyTokenFlags` is flags tell us whether that `AnycallProxy` accept receiving `anyERC20Token`.

If the flag is `false` and when the liquidity pool is not enough, then the router contract will record this swap and finish it. later anyone can retry the record to complete the swap when the liquidity pool is enough.

## 4. the exectuion steps

### 4.1 the user call a corresponding `swapout and call` method

1. token has no underlying

    ```solidity
        function anySwapOutAndCall(
            address token,
            string memory to,
            uint256 amount,
            uint256 toChainID,
            string memory anycallProxy,
            bytes calldata data
        )
    ```

2. token has normal underlying

    ```solidity
        function anySwapOutUnderlyingAndCall(
            address token,
            string memory to,
            uint256 amount,
            uint256 toChainID,
            string memory anycallProxy,
            bytes calldata data
        )
    ```

3. token has special underlying of wNative

    ```solidity
        function anySwapOutNativeAndCall(
            address token,
            string memory to,
            uint256 toChainID,
            string memory anycallProxy,
            bytes calldata data
        )
    ```

where,

> `address token` is the anytoken contract address on the `source` chain
>
> `string to` is the receive address on the `destination` chain
>
> `uint256 amount` is the value transfered on the `source` chain
>
> `uint256 toChainID` is the `destination` blockchain id to router into
>
> `string anycallProxy` is the call proxy contract on the > `destination` chain to call into
>
> `bytes data` is the call data of calling the call proxy contract

Note:
> generally the `string to` is same as `string anycallProxy`.
>
> they can be different either, for example to implement the following user case:
>
> transfer token to `string to` address, and then call `string anycallProxy`, this case `string to` address acts like a separate vault address.

### 4.2 the mpc call a corresponding `swapin and exec` method

1. token has no underlying

    ```solidity
        function anySwapInAndExec(
            string memory swapID,
            address token,
            address receiver,
            uint256 amount,
            uint256 fromChainID,
            address anycallProxy,
            bytes calldata data
        )
    ```

2. token has underlying

    ```solidity
        function anySwapInUnderlyingAndExec(
            string memory swapID,
            address token,
            address receiver,
            uint256 amount,
            uint256 fromChainID,
            address anycallProxy,
            bytes calldata data
        )
    ```
