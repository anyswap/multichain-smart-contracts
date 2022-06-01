# How to delpoy anycall with client

the follwing docmuent is explained with example of `anycallv5 + aavev3`

related smart contracts

```text
contracts/
├── anycall
│   ├── AnyswapV5CallProxy.sol
│   ├── AnyswapV6CallProxy.sol
│   ├── client-v5
│   ├── └── AaveV3PoolAnycallClient.sol
│   └── client-v6
│       └── AaveV3PoolAnycallClient.sol
└── common
    └── UpgradableProxy.sol
```

## 1. delpoy `AnyswapCallProxy` same as normal anycall deployment

**AnyswapV5CallProxy**

```text
    constructor(
        address _admin,
        address _mpc,
        uint128 _premium,
        bool _freeTestMode
    )
```

when `_freeTestMode` is true, the whitelist will be disable and no fee will be payed.

**AnyswapV6CallProxy**

```text
    constructor(
        address _admin,
        address _mpc,
        uint128 _premium,
        uint256 _mode
    )
```

when `_mode` is flag bits.

```solidity
    uint256 public constant PERMISSIONLESS_MODE = 0x1;
    uint256 public constant FREE_MODE = 0x1 << 1;
```

Notation:  
the client app should set authorization to allow anyswap callproxy to call into their app.  
for v5, set authorization to `AnyswapV5CallProxy`  
for v6, set authorization to `AnyswapV6CallProxy.executor`

## 2. deploy `AaveV3PoolAnycallClient` as upgradable

### 2.1 deploy `AaveV3PoolAnycallClient` in `AaveV3PoolAnycallClient.sol`

```text
    constructor(
        address _admin,
        address _mpc,
        address _callProxy,
        address _aaveV3Pool
    )
```

where `_callProxy` is the `AnyswapV5CallProxy` contract address,
and `_aaveV3Pool` is the aave v3 pool contract address.

### 2.2 deploy `AnycallClientProxy` in `UpgradableProxy.sol`

```text
    constructor(address _proxyTo)
```

set `_proxyTo` to the contract address deployed in step 2.1

the the aave v3 pool contract should give `Bridge Role`
to this `AnycallClientProxy` contract address.

we can call `updateImplementation` of `AnycallClientProxy` to
update the implementation if we want to upgrage `AaveV3PoolAnycallClient`.

### 2.3 setting `AaveV3PoolAnycallClient`

set client peers, a client have a client perr on each blockchain,
and each peer is an `AaveV3PoolAnycallClient` contract on each blockchain.
the `_chainIds` and `_peers` should have the order, that is the first `_chainIds`'s client peer is the first `_peers`.

```text
    function setClientPeers(
        uint256[] calldata _chainIds,
        address[] calldata _peersanyFallback
    ) external onlyAdmin
```

set token peers, for `each token` on source blockchain, we need to set its corresponding peers on each blockchain.
the `chainIds` and `dstTokens` should have the order, that is the first `chainIds`'s token peer is the first `dstTokens`.

```text
    function setTokenPeers(
        address srcToken,
        uint256[] calldata chainIds,
        address[] calldata dstTokens
    ) external onlyAdmin
```

## 3. the exectuion steps

### 3.1 the user call `callout` of `AnycallClientProxy` on source blockchain

```text
    function callout(
        address token,
        uint256 amount,
        address receiver,
        uint256 toChainId
    ) external
```

### 3.2 `AnyswapV5CallProxy` call `callin` of `AnycallClientProxy` on dest blockchain

the mpc should verify tx of step 3.1 and then do the call

```text
    function callin(
        address srcToken,
        address dstToken,
        uint256 amount,
        address sender,
        address receiver,
        uint256 /*toChainId*/ // used in anyFallback
    ) external onlyCallProxy
```

### 3.3 if `callin` failed on dest chain call back the `anyFallback` on source chain

```text
    function anyFallback(address to, bytes calldata data) external onlyCallProxy
```
