const eth = require('./utils/eth');
const ABIS = require('./utils/abis')
const config = require('./config/config')
const abiCoder = eth.loadAbiCoder();

const amount = 100000000;
const BiggerAmount = '100000000000000';

async function start() {

    // mock wallet
    const wallet = await eth.loadWallet(config.privateKey, config.network);
    console.log(`wallet:${wallet.address}`)

    // deploy tokenA and tokenB then return their address
    const { tokenA, tokenB } = await getTokens(wallet);

    const weth = await getWETH(wallet);

    // deploy sushiFactory then return address
    const factory = await getFactory(wallet);

    /**
     * real test 
     * 1) deploy TradeProxyManager contract
     * 2) deploy SushiswapTradeProxy contract
     * 3) call TradeProxyManage.addTradeProxy()
     * 4) deploy MultichainRouter contract on src chain
     * 5) deploy MultichainRouter contract on desc chain
     * 6) call TradeProxyManage.addAuth()
     * 7) call MultichainRouter.anySwapOutAndCall() on src chain then return txHash
     * 8) verify txHash on src chain
     * 9) add mint authority to MultichainRouter
     * 10) call MultichainRouter.anySwapInAndExec() on desc chain
     * 11) check all tx res
     */
    {
        // 1) deploy TradeProxyManager contract
        const tradeProxyManager = await getTradeProxyManager(wallet);
        // 2) deploy SushiswapTradeProxy contract
        const sushiswapTradeProxy = await getSushiswapTradeProxy(wallet, tradeProxyManager, factory, weth);
        // 3) call TradeProxyManage.addTradeProxy()
        const tradeProxyManagerContract = await loadTradeProxyManager(tradeProxyManager, wallet);
        await tradeProxyManagerContract.addTradeProxy(sushiswapTradeProxy)
            .then(res => console.log(`add tradeProxy :${res.hash}`))

        // 4) deploy MultichainRouter contract on src chain
        // do after

        // 5) deploy MultichainRouter contract on desc chain
        const multichainRouter = await getMultichainRouter(wallet, tradeProxyManager);
        // 6) call TradeProxyManage.addAuth()
        await tradeProxyManagerContract.addAuth(multichainRouter).then(
            res => console.log(`add Auth:${res.hash}`)
        )
        // 7) call MultichainRouter.anySwapOutAndCall() on src chain then return txHash
        // do after

        // 8) verify txHash on src chain
        // do after

        // 9) add mint authority to MultichainRouter
        const tokenAContract = await loadToken(tokenA, wallet);
        await tokenAContract.addMinterNow(multichainRouter).then(
            res => console.log(`tokenAContract addMinterNow: ${res.hash}`)
        );
        // 10) call MultichainRouter.anySwapInAndExec() on desc chain
        const multichainRouterContract = await loadMultichainRouter(multichainRouter, wallet);

        // test between token and token
        await testTokenAndToken(wallet, tokenA, tokenB, factory, multichainRouterContract, sushiswapTradeProxy);

        // test between native and token
        // await testTokenAndNative(wallet, tokenA, weth, factory, multichainRouterContract, sushiswapTradeProxy);

        // 11) check all tx res
    }
};

// deploy multichainRouter and return address
async function getMultichainRouter(wallet, tradeProxyManager) {
    // address _tradeProxyManager, address _feeCalc, address _wNATIVE, address _mpc
    const MultichainRouter_factory = eth.deployContract(ABIS.MultichainRouter.abi, ABIS.MultichainRouter.data.bytecode, wallet);
    return await MultichainRouter_factory.deploy(tradeProxyManager, eth.constant.AddressZero, eth.constant.AddressZero, wallet.address).then(res => {
        console.log(`MultichainRouter address:${res.address}`);
        return res.address;
    });
}

// deploy tradeProxyManager and return address
async function getTradeProxyManager(wallet) {
    const TradeProxyManager_factory = eth.deployContract(ABIS.TradeProxyManager.abi, ABIS.TradeProxyManager.data.bytecode, wallet);
    return await TradeProxyManager_factory.deploy(wallet.address).then(res => {
        console.log(`TradeProxyManager address:${res.address}`);
        return res.address;
    });
}

// deploy WETH and return address
async function getWETH(wallet) {
    const WETH9_factory = eth.deployContract(ABIS.WETH9.abi, ABIS.WETH9.data.bytecode, wallet);
    return await WETH9_factory.deploy().then(res => {
        console.log(`WETH9 address:${res.address}`);
        return res.address;
    });
}

// deploy token and return address
async function getTokens(wallet) {
    const AnyswapV6ERC20_factory = eth.deployContract(ABIS.AnyswapV6ERC20.abi, ABIS.AnyswapV6ERC20.data.bytecode, wallet);
    const TokenA_contract = await AnyswapV6ERC20_factory.deploy('TokenA', 'TokenA', 18,
        eth.constant.AddressZero, wallet.address).then(res => {
            console.log(`TokenA address:${res.address}`);
            return res.address;
        });

    const TokenB_contract = await AnyswapV6ERC20_factory.deploy('TokenB', 'TokenB', 18,
        eth.constant.AddressZero, wallet.address).then(res => {
            console.log(`TokenB address:${res.address}`);
            return res.address;
        });

    return { tokenA: TokenA_contract, tokenB: TokenB_contract }
}

// deploy sushiFactory and return address
async function getFactory(wallet) {
    const UniswapV2Factory_factory = eth.deployContract(ABIS.UniswapV2Factory.abi, ABIS.UniswapV2Factory.data.bytecode, wallet);
    return await UniswapV2Factory_factory.deploy(wallet.address).then(res => {
        console.log(`UniswapV2Factory address:${res.address}`);
        return res.address;
    });
}

// deploy sushiRouter and return address
async function getSushiRouter(wallet, factory) {
    const UniswapV2Router02_factory = eth.deployContract(ABIS.UniswapV2Router02.abi, ABIS.UniswapV2Router02.data.bytecode, wallet);
    return await UniswapV2Router02_factory.deploy(factory, eth.constant.AddressZero).then(res => {
        console.log(`UniswapV2Router02 address:${res.address}`);
        return res.address;
    });
}

// deploy sushiswapTradeProxy and return address
async function getSushiswapTradeProxy(wallet, tradeProxyManager, factory, weth) {
    const SushiswapTradeProxy_factory = eth.deployContract(ABIS.SushiSwapTradeProxyV2.abi, ABIS.SushiSwapTradeProxyV2.data.bytecode, wallet)
    return await SushiswapTradeProxy_factory.deploy(tradeProxyManager, factory, weth).then(res => {
        console.log(`SushiswapTradeProxy address:${res.address}`);
        return res.address;
    });
}

// load sushiswapTradeProxy contract instance
async function loadTradProxy(tradeProxy, wallet) {
    return eth.loadContract(tradeProxy, ABIS.MultichainTradeProxy.abi, wallet);
}

// load sushiFactory contract instance
async function loadFactory(factory, wallet) {
    return eth.loadContract(factory, ABIS.UniswapV2Factory.abi, wallet);
}

// load sushiRouter contract instance
async function loadSushiRouter(sushiRouter, wallet) {
    return eth.loadContract(sushiRouter, ABIS.UniswapV2Router02.abi, wallet);
}

// load pair contract instance
async function loadPair(pair, wallet) {
    return eth.loadContract(pair, ABIS.UniswapV2Pair.abi, wallet);
}

// load token contract instance
async function loadToken(token, wallet) {
    return eth.loadContract(token, ABIS.AnyswapV6ERC20.abi, wallet);
}

// load weth contract instance
async function loadWeth(weth, wallet) {
    return eth.loadContract(weth, ABIS.WETH9.abi, wallet);
}

// load tradeProxyManager contract instance
async function loadTradeProxyManager(tradeProxyManager, wallet) {
    return eth.loadContract(tradeProxyManager, ABIS.TradeProxyManager.abi, wallet);
}

// load multichainRouter contract instance
async function loadMultichainRouter(multichainRouter, wallet) {
    return eth.loadContract(multichainRouter, ABIS.MultichainRouter.abi, wallet);
}

// mint to wallet and approve to sushiRouter
async function mintAndApprove(token, wallet, sushiRouter) {
    // approve tokenB to sushiRouter
    const tokenContract = await loadToken(token, wallet);
    await tokenContract.initVault(wallet.address)
        .then(res => console.log(`tokenContract initVault:${res.hash}`));
    await tokenContract.mint(wallet.address, BiggerAmount)
        .then(res => console.log(`tokenContract mint:${res.hash}`));
    await tokenContract.approve(sushiRouter, eth.constant.MaxUint256)
        .then(res => console.log(`tokenContract approve:${res.hash}`));
    await tokenContract.balanceOf(wallet.address)
        .then(res => console.log(`tokenContract balances:${res}`))
    await tokenContract.allowance(wallet.address, sushiRouter)
        .then(res => console.log(`tokenContract allowance:${res}`))
}

// mint to wallet and transfer to pair
async function mintAndTransfer(token, reciept, amount, wallet) {
    const tokenContract = await loadToken(token, wallet);
    await tokenContract.initVault(wallet.address)
        .then(res => console.log(`tokenContract initVault:${res.hash}`));
    await tokenContract.mint(wallet.address, BiggerAmount)
        .then(res => console.log(`tokenContract mint:${res.hash}`));
    await tokenContract.transferFrom(wallet.address, reciept, amount)
        .then(res => console.log(`tokenAContract transfer from :${res.hash}`));
}

// deposit to wallet and transfer to pair
async function depositAndTransfer(weth, reciept, amount, wallet) {
    const wethContract = await loadWeth(weth, wallet);
    await wethContract.deposit({ value: amount })
        .then(res => console.log(`wethContract deposit:${res.hash}`));
    await wethContract.transferFrom(wallet.address, reciept, amount)
        .then(res => console.log(`wethContract transfer from :${res.hash}`));
}

// add init liquidity by sushiRouter
async function addLiquidityByRouter(wallet, factory, tokenA, tokenB) {
    // get sushiRouter
    const sushiRouter = await getSushiRouter(wallet, factory);
    const sushiRouterContract = await loadSushiRouter(sushiRouter, wallet);

    await mintAndApprove(tokenA, wallet, sushiRouter);
    await mintAndApprove(tokenB, wallet, sushiRouter);

    // add tokenA and tokenB pair Liquidity
    await sushiRouterContract.addLiquidity(tokenA, tokenB, amount, amount, '0', '0', wallet.address, eth.constant.MaxUint256)
        .then(res => console.log(`addLiquidity:${res.hash}`));
}

// add init liquidity by transfer
async function addTokenLiquidityByTransfer(wallet, factory, tokenA, tokenB) {
    // create pair for tokenA and tokenB
    const factoryContract = await loadFactory(factory, wallet);
    await factoryContract.createPair(tokenA, tokenB)
        .then(res => console.log(`create pair:${res.hash}`))
    // get pair for tokenA and tokenB
    const pair = await factoryContract.getPair(tokenA, tokenB)
        .then(res => { console.log(`get pair:${res}`); return res })

    // transfer token to pair for tokenA and tokenB
    await mintAndTransfer(tokenA, pair, amount, wallet);
    await mintAndTransfer(tokenB, pair, amount, wallet);

    const pairContract = await loadPair(pair, wallet);
    await pairContract.mint(wallet.address)
        .then(res => console.log(`pairContract mint :${res.hash}`));
}

// add init liquidity by transfer
async function addNativeLiquidityByTransfer(wallet, factory, tokenA, weth) {
    // create pair for tokenA and weth
    const factoryContract = await loadFactory(factory, wallet);
    await factoryContract.createPair(tokenA, weth)
        .then(res => console.log(`create pair:${res.hash}`))
    // get pair for tokenA and weth
    const pair = await factoryContract.getPair(tokenA, weth)
        .then(res => { console.log(`get pair:${res}`); return res })

    // transfer token to pair for tokenA and weth
    await mintAndTransfer(tokenA, pair, amount, wallet);
    await depositAndTransfer(weth, pair, amount, wallet);

    const pairContract = await loadPair(pair, wallet);
    await pairContract.mint(wallet.address)
        .then(res => console.log(`pairContract mint :${res.hash}`));
}

// get tokenA and tokenB balances of pair and get liquidity balances of wallet
async function getBalanceAndLiquidity(wallet, factory, tokenA, tokenB) {
    // create pair for tokenA and tokenB
    const factoryContract = await loadFactory(factory, wallet);
    // get pair for tokenA and tokenB
    const pair = await factoryContract.getPair(tokenA, tokenB)
        .then(res => { console.log(`get pair:${res}`); return res })

    const tokenAContract = await loadToken(tokenA, wallet);
    const balances_tokenA = await tokenAContract.balanceOf(pair);

    const tokenBContract = await loadToken(tokenB, wallet);
    const balances_tokenB = await tokenBContract.balanceOf(pair);

    const pairContract = await loadPair(pair, wallet);
    const balances_liquidity = await pairContract.balanceOf(wallet.address);

    return {
        balances_tokenA, balances_tokenB, balances_liquidity
    }
}

async function testTokenAndToken(wallet, tokenA, tokenB, factory, multichainRouterContract, sushiswapTradeProxy) {
    // add init liquidity to pair for tokenA and tokenB by sushiRouter
    // await addLiquidityByRouter(wallet, factory, tokenA, tokenB);

    // add init liquidity to pair for tokenA and tokenB by transfer to pair
    await addTokenLiquidityByTransfer(wallet, factory, tokenA, tokenB);

    // get tokenA and tokenB balances of pair and get liquidity balances of wallet before test
    await getBalanceAndLiquidity(wallet, factory, tokenA, tokenB).then(res => {
        console.log(`after init liquidity======== pair tokenA balances:${res.balances_tokenA},pair tokenB balances:${res.balances_tokenB},wallet liquidity balances:${res.balances_liquidity}`)
    });

    // test swapExactTokensForTokens
    const data = abiCoder.encode(["uint256", "uint256", "uint256", "address[]", "address", "uint256", "bool"],
        [0, amount, amount, [tokenA, tokenB], wallet.address, eth.constant.MaxUint256, false]);

    // test swapTokensForExactTokens
    // const data = abiCoder.encode(["uint256", "uint256", "uint256", "address[]", "address", "uint256", "bool"],
        // [amount / 10, 0, amount, [tokenA, tokenB], wallet.address, eth.constant.MaxUint256, false]);

    await multichainRouterContract.anySwapInAndExec(
        '0x77c98d585b510c5aadf26ef775493ce359f0a8c6df644911f3f84b3df59aab8c', tokenA, amount, 0, sushiswapTradeProxy, data
    ).then(
        res => console.log(`anySwapInAndExec: ${res.hash}`)
    )

    // get tokenA and tokenB balances of pair and get liquidity balances of wallet after test
    await getBalanceAndLiquidity(wallet, factory, tokenA, tokenB).then(res => {
        console.log(`after exec======== pair tokenA balances:${res.balances_tokenA},pair tokenB balances:${res.balances_tokenB},wallet liquidity balances:${res.balances_liquidity}`)
    });
}

async function testTokenAndNative(wallet, tokenA, weth, factory, multichainRouterContract, sushiswapTradeProxy) {
    // add init liquidity to pair for tokenA and weth by transfer to pair
    await addNativeLiquidityByTransfer(wallet, factory, tokenA, weth);
    // get tokenA and weth balances of pair and get liquidity balances of wallet before test
    await getBalanceAndLiquidity(wallet, factory, tokenA, weth).then(res => {
        console.log(`after init liquidity======== pair tokenA balances:${res.balances_tokenA},pair weth balances:${res.balances_tokenB},wallet liquidity balances:${res.balances_liquidity}`)
    });

    // test swapTokensForExactETH 
    const data = interface.encodeFunctionData('swapTokensForExactETH', [
        amount / 4, amount, [tokenA, weth], wallet.address, eth.constant.MaxUint256
    ])

    // test swapExactTokensForETH 
    // const data = interface.encodeFunctionData('swapExactTokensForETH', [
    // amount, 0, [tokenA, weth], wallet.address, eth.constant.MaxUint256
    // ])

    await multichainRouterContract.anySwapInAndExec(
        '0x77c98d585b510c5aadf26ef775493ce359f0a8c6df644911f3f84b3df59aab8c', tokenA, amount, 0, sushiswapTradeProxy, data
    ).then(
        res => console.log(`anySwapInAndExec: ${res.hash}`)
    )

    // get tokenA and weth balances of pair and get liquidity balances of wallet after test
    await getBalanceAndLiquidity(wallet, factory, tokenA, weth).then(res => {
        console.log(`after exec======== pair tokenA balances:${res.balances_tokenA},pair tokenB balances:${res.balances_tokenB},wallet liquidity balances:${res.balances_liquidity}`)
    });
}
// start function
start()