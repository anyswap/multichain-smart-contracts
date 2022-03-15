const eth = require('./utils/eth');
const ABIS = require('./utils/abis')
// const privateKey = '30237812841dfc13d8e8674237c6f615967ce01402cb8d93519b6523d6cd9ff2';
// const network = 'https://data-seed-prebsc-1-s1.binance.org:8545';
const network = 'http://localhost:8545';
const privateKey = '0x7b824e86d5daf1bd8fa1882d3152c5ceb2c1487dcaf72dcd3ab10f4acb1e9593';
const amount = 100000;

async function start() {

    // mock wallet
    const deploy_wallet = await eth.loadWallet(privateKey, network);
    console.log(`deploy_wallet:${deploy_wallet.address}`)

    // get tokenA and tokenB
    const { tokenA, tokenB } = await getTokens(deploy_wallet);

    // get sushiFactory
    const factory = await getFactory(deploy_wallet);
    const factoryContract = await loadFactory(factory, deploy_wallet);

    // get sushiRouter
    const sushiRouter = await getSushiRouter(deploy_wallet, factory);
    const sushiRouterContract = await loadSushiRouter(sushiRouter, deploy_wallet);

    await sendAndApprove(tokenA, deploy_wallet, sushiRouter);
    await sendAndApprove(tokenB, deploy_wallet, sushiRouter);

    // add tokenA and tokenB pair Liquidity
    await sushiRouterContract.addLiquidity(tokenA, tokenB, '1000000', '1000000', '0', '0', deploy_wallet.address, eth.constant.MaxUint256)
        .then(res => console.log(`addLiquidity:${res.hash}`));

    // // create pair for tokenA and tokenB
    // await factoryContract.createPair(tokenA, tokenB)
    //     .then(res => console.log(`create pair:${res.hash}`))
    // // get pair for tokenA and tokenB
    // const pair = await factoryContract.getPair(tokenA, tokenB)
    //     .then(res => { console.log(`get pair:${res}`); return res })

    // // transfer token to pair for tokenA and tokenB
    // await addLiquidity(tokenA, pair, amount, deploy_wallet);
    // await addLiquidity(tokenB, pair, amount, deploy_wallet);

    // const pairContract = await loadPair(pair, deploy_wallet);
    // await pairContract.mint(deploy_wallet.address)
    //     .then(res => console.log(`pairContract mint :${res.hash}`));

    // get tradeProxy
    const tradeProxy = await getTradeProxy(deploy_wallet, factory);
    const tradeProxyContract = await loadTradProxy(tradeProxy, deploy_wallet);

    const tokenContract = await loadToken(tokenA, deploy_wallet);
    await tokenContract.approve(tradeProxy, eth.constant.MaxUint256)
        .then(res => console.log(`tokenContract approve:${res.hash}`));

    const interface = eth.loadInterface(ABIS.UniswapV2Router02.abi);
    const data = interface.encodeFunctionData('swapExactTokensForTokens', [
        amount, 0, [tokenA, tokenB], deploy_wallet.address, eth.constant.MaxUint256
    ])
    console.log(`calldata:${data}`)

    const execHash = await tradeProxyContract.exec(tokenA, amount, data)
        .then(res => {
            console.log(`tradeProxyContract exec:${res.hash}`);
            return res.hash
        })

    await eth.getProvider(network).getTransactionReceipt(execHash).then(res => console.log(`reciept:${JSON.stringify(res)}`))

};

async function getTokens(wallet) {
    const AnyswapV6ERC20_factory = eth.deployContract(ABIS.AnyswapV6ERC20.abi, ABIS.AnyswapV6ERC20.data.bytecode, wallet);
    const TokenA_contract = await AnyswapV6ERC20_factory.deploy('TokenA', 'TokenA', 18,
        eth.constant.AddressZero, wallet.address).then(res => {
            console.log(`TokenA_contract address:${res.address}`);
            return res.address;
        });

    const TokenB_contract = await AnyswapV6ERC20_factory.deploy('TokenB', 'TokenB', 18,
        eth.constant.AddressZero, wallet.address).then(res => {
            console.log(`TokenB_contract address:${res.address}`);
            return res.address;
        });

    return { tokenA: TokenA_contract, tokenB: TokenB_contract }
}

async function getFactory(wallet) {
    const UniswapV2Factory_factory = eth.deployContract(ABIS.UniswapV2Factory.abi, ABIS.UniswapV2Factory.data.bytecode, wallet);
    return await UniswapV2Factory_factory.deploy(wallet.address).then(res => {
        console.log(`UniswapV2Factory_contract address:${res.address}`);
        return res.address;
    });
}

async function getSushiRouter(wallet, factory) {
    const UniswapV2Router02_factory = eth.deployContract(ABIS.UniswapV2Router02.abi, ABIS.UniswapV2Router02.data.bytecode, wallet);
    return await UniswapV2Router02_factory.deploy(factory, eth.constant.AddressZero).then(res => {
        console.log(`UniswapV2Router02_contract address:${res.address}`);
        return res.address;
    });
}

async function getTradeProxy(wallet, factory) {
    const MultichainTradeProxy_factory = eth.deployContract(ABIS.MultichainTradeProxy.abi, ABIS.MultichainTradeProxy.data.bytecode, wallet)
    return await MultichainTradeProxy_factory.deploy(wallet.address, factory, eth.constant.AddressZero).then(res => {
        console.log(`MultichainTradeProxy_contract address:${res.address}`);
        return res.address;
    });
}

async function loadTradProxy(tradeProxy, wallet) {
    return eth.loadContract(tradeProxy, ABIS.MultichainTradeProxy.abi, wallet);
}

async function loadFactory(factory, wallet) {
    return eth.loadContract(factory, ABIS.UniswapV2Factory.abi, wallet);
}

async function loadSushiRouter(sushiRouter, wallet) {
    return eth.loadContract(sushiRouter, ABIS.UniswapV2Router02.abi, wallet);
}

async function loadPair(pair, wallet) {
    return eth.loadContract(pair, ABIS.UniswapV2Pair.abi, wallet);
}

async function loadToken(token, wallet) {
    return eth.loadContract(token, ABIS.AnyswapV6ERC20.abi, wallet);
}

async function sendAndApprove(token, wallet, sushiRouter) {
    // approve tokenB to sushiRouter
    const tokenContract = await loadToken(token, wallet);
    await tokenContract.initVault(wallet.address)
        .then(res => console.log(`tokenContract initVault:${res.hash}`));
    await tokenContract.mint(wallet.address, eth.constant.MaxUint256)
        .then(res => console.log(`tokenContract mint:${res.hash}`));
    await tokenContract.approve(sushiRouter, eth.constant.MaxUint256)
        .then(res => console.log(`tokenContract approve:${res.hash}`));
    await tokenContract.balanceOf(wallet.address)
        .then(res => console.log(`tokenContract balances:${res}`))
    await tokenContract.allowance(wallet.address, sushiRouter)
        .then(res => console.log(`tokenContract allowance:${res}`))
}

async function addLiquidity(token, reciept, amount, wallet) {
    const tokenContract = await loadToken(token, wallet);
    await tokenContract.initVault(wallet.address)
        .then(res => console.log(`tokenContract initVault:${res.hash}`));
    await tokenContract.mint(wallet.address, eth.constant.MaxUint256)
        .then(res => console.log(`tokenContract mint:${res.hash}`));
    await tokenContract.transferFrom(wallet.address, reciept, amount)
        .then(res => console.log(`tokenAContract transfer from :${res.hash}`));
}
start()