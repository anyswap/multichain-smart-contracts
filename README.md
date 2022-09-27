# multichain smart contract

This repository is used for new smart contracts of `multichain`,
mainly for bridge, router, and anycall functions.

This repository also have upgradation smart contracts of
[anyswap-v1-core](https://github.com/anyswap/anyswap-v1-core.git)
with vesrions start from v7.

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

## scripts

The scripts includs deploying and testing related scripts.

>Note: Adjust arguments before running

```shell
npx hardhat run scripts/encodeSushiCallData.js
```

```shell
npx hardhat run scripts/deploy-anycall-v7.js
```
