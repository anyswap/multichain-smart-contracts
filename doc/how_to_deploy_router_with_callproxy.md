# How to deploy router + anycall

the follwing docmuent is explained with example of `router + sushiswap`

related smart contracts

```text
contracts/router/
├── MultichainV7Router.sol
└── proxy
    └── SushiSwapProxy.sol
```

Notation: the following steps are not the unique way.
we can change the orders and setting to complete the same job.

## 0. deploy `AnycallExecutor` in `AnyCallExecutor.sol`

`AnycallExecutor` is the delegator to execute contract calling (like a sandbox) to enfore security.

```
    constructor(address _mpc)

    function addAuthCallers(address[] calldata _callers) external
    function removeAuthCallers(address[] calldata _callers) external

    function isAuthCaller(address _caller) external view returns (bool)
```

## 1. deploy `MultichainV7Router` in `MultichainV7Router.sol`

```
    constructor(
        address _admin,
        address _mpc,
        address _wNATIVE,
        address _anycallExecutor
    )
```

`wNATIVE` and `anycallExecutor` is `immutable`, which means they can not be change after deployed.

set `_anycallExecutor` to the address of the contract deployed at step 0.

and we should add the deployed `MultichainV7Router` contract to auth callers of `AnycallExecutor`, by calling `AnycallExecutor::addAuthCallers`.


## 2. deploy `AnycallProxy_SushiSwap` in `SushiSwapProxy.sol`

deploy `AnycallProxy_SushiSwap`

```
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

```
    function addAnycallProxies(address[] memory proxies, bool[] memory acceptAnyTokenFlags) external onlyMPC
```

where `proxies` includes the `AnycallProxy` contract deployed in step 2

and `acceptAnyTokenFlags` is flags tell us whether that `AnycallProxy` accept receiving `anyERC20Token`.
If the flag is false and when the liquidity pool is not enough, then the router contract will record this swap and finish it. later anyone can retry the record to complete the swap when the liquidity pool is enough.
