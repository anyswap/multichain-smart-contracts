# multichain smart contract

This repository is used for new smart contracts of `multichain`,
mainly for bridge, router, and anycall functions.

This repository also have upgradation smart contracts of
[anyswap-v1-core](https://github.com/anyswap/anyswap-v1-core.git)
with vesrions start from v7.

for example,

```text
contracts/
├── anycall
│   ├── AnyswapV5CallProxy.sol
│   ├── AnyswapV6CallProxy.sol
├── anytoken
│   └── MultichainV7ERC20.sol
└── router
    └── MultichainV7Router.sol
```

## install dependencies

```shell
npm install
```

## flatten contract

```shell
npx hardhat flatten <contract-to-be-flatten> | sed '/SPDX-License-Identifier:/d' | sed 1i'// SPDX-License-Identifier: GPL-3.0-or-later'
```

## compile

1. use hardhat

    ```shell
    npx hardhat compile
    ```

2. use remix

    <https://remix.ethereum.org/#optimize=true&evmVersion=null&version=soljson-v0.8.10+commit.fc410830.js&runs=200>


## test

## install dependencies

```shell
1) npm install --save ethers
2) npm install --save web3
```
## vi config/config.js

```shell
network: '',
privateKey: ''
```

## if run ganache-cli
```shell
1) npm i ganache-cli
2) ganache-cli
```

## start test
```shell
node test/SushiswapTradeProxy.js
```

