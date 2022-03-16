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



