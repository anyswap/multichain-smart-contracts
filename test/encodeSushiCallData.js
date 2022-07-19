const eth = require('./utils/eth');
const abiCoder = eth.loadAbiCoder();

function encode(amount, tokenA, tokenB, receiver, toNative) {
    const data = abiCoder.encode(["tuple(uint256,uint256,uint256,address[],address,uint256,bool)"],
        [[0, 0, amount, [tokenA, tokenB], receiver, eth.constant.MaxUint256, toNative]]);
    console.log(`encode data:${data}`)

}

encode(100, "", "", "", false)