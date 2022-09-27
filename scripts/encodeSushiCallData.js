async function main() {
    const amountInMax = "1000000000000000000";
    const tokenA = "0x1111111111111111111111111111111111111111";
    const tokenB = "0x2222222222222222222222222222222222222222";
    const receiver = "0x3333333333333333333333333333333333333333";
    const deadline = ethers.constants.MaxUint256;
    const toNative = false;

    const encodeArgs = [
        0,
        0,
        amountInMax,
        [tokenA, tokenB],
        receiver,
        deadline,
        toNative
    ];

    console.log(`encode arguments:`, encodeArgs);

    // struct AnycallInfo {
    //     uint256 amountOut;
    //     uint256 amountOutMin;
    //     uint256 amountInMax;
    //     address[] path;
    //     address receiver;
    //     uint256 deadline;
    //     bool toNative;
    // }
    const data = ethers.utils.defaultAbiCoder.encode(
        ["tuple(uint256,uint256,uint256,address[],address,uint256,bool)"],
        [encodeArgs]
    );

    console.log(`\nencoded data:\n${data}`);
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
