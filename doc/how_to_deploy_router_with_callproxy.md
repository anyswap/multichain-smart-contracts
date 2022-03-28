# How to deploy router + anycall

the follwing docmuent is explained with example of `router + sushiswap`

related smart contracts

```text
contracts/
├── MultichainRouter.sol
├── proxy
│   └── SushiSwapProxy.sol
├── utils
│   └── RouterFeeCalc.sol
```

Notation: the following steps are not the unique way.
we can change the orders and setting to complete the same job.

## 1. deploy `MultichainRouter` in `MultichainRouter.sol`

```
    constructor(
        address _mpc,
        address _wNATIVE,
        address _feeCalc,
        address[] memory _anycallProxies
    )

    function setFeeCalc(address _feeCalc) external onlyMPC
    function addAnycallProxies(address[] memory proxies) external onlyMPC
```

here we deploy `MultichainRouter` at the first step,
we do not know `_feeCalc` and `_anycallProxies`,
so we set them to zero addresses here,
and we should set them in the 4th step.


## 2. deploy `RouterSwapConfig` and `RouterFeeCalc` in `RouterFeeCalc.sol`

### 2.1 firstly deploy `RouterSwapConfig`

```
    constructor(address[2] memory _owners)

    function setSwapCofig(address token, SwapConfig memory config) external onlyOwner
    function setBigValueWhitelist(address token, address sender, bool flag) external onlyOwner
```

and setting the swap config and whitelist of each `token`.

**when add a new supported token, we should also set its token swap config here.**

### 2.2 then deploy `RouterFeeCalc`

```
    constructor(address _routerSwapConfig, address[2] memory _owners)
```

with the first argment `_routerSwapConfig` be the deployed `RouterSwapConfig` address

we separate `RouterSwapConfig` and `RouterFeeCalc` as two contracts here,
as we may change the second one more frequently.
when the fee calc algorithmn is adjusted,
the swap config can also be referenced and need not reconfig them again.


## 3. deploy `AnycallProxy_SushiSwap` in `SushiSwapProxy.sol`

deploy `AnycallProxy_SushiSwap`

```
    constructor(
        address mpc_,
        address caller_,
        address sushiV2Factory_,
        address wNATIVE_
    )
```

with `caller_` be the `MultichainRouter` contract deployed in the 1st step.

## 4. setting the `MultichainRouter`

### 4.1 setting the fee calculator contract

```
    function setFeeCalc(address _feeCalc) external onlyMPC
```

where `_feeCalc` is the `RouterFeeCalc` contract deployed in step 2.2

### 4.2 setting the call proxies which are allowed to be called in router

```
    function addAnycallProxies(address[] memory proxies) external onlyMPC
```

where `proxies` includes the `AnycallProxy` contract deployed in step 3
