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

## 1. deploy `MultichainV7Router` in `MultichainV7Router.sol`

```
    constructor(
        address _admin,
        address _mpc,
        address _wNATIVE,
        address[] memory _anycallProxies
    )

    function addAnycallProxies(address[] memory proxies) external onlyMPC
```

here we deploy `MultichainV7Router` at the first step,
we do not know `_anycallProxies`,
so we set it to zero array here,
and we should set them in the 3rd step.


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

with `caller_` be the `MultichainV7Router` contract deployed in the 1st step.

## 3. setting the `MultichainV7Router`

setting the call proxies which are allowed to be called in router

```
    function addAnycallProxies(address[] memory proxies) external onlyMPC
```

where `proxies` includes the `AnycallProxy` contract deployed in step 2
