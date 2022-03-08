# multichain smart contract

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
