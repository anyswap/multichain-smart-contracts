const TruffleAssert = require('truffle-assertions');
const Ethers = require('ethers');
const Helpers = require('../helpers');

const XcmTransferProxyContract = artifacts.require("AnycallProxy_XcmTransfer");
const XTokensMockContract = artifacts.require("XTokensMock");
const ERC20MockContract = artifacts.require("ERC20Mock");

contract('XcmTransferProxy - [exec]', async (accounts) => {
    const mpc = accounts[0];
    const caller = accounts[1];
    const receiver = accounts[2];
    const callerInitialBalance = 10000000000;
    const weight = 100;

    let XcmTransferProxyInstance;
    let ERC20MockInstance;
    let xTokensMockInstance;

    beforeEach(async () => {
        xTokensMockInstance = await XTokensMockContract.new();
        XcmTransferProxyInstance = await XcmTransferProxyContract.new(mpc, caller, xTokensMockInstance.address);
        ERC20MockInstance = await ERC20MockContract.new("Test Token", "TTOKEN", caller, callerInitialBalance);
    });

    it('[sanity] caller should have TTOKEN balance', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), callerInitialBalance);
    });

    it('[sanity] xTokensMock should burn TTOKEN balance', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), callerInitialBalance);
        const destination = Helpers.createDestination();
        await xTokensMockInstance.transfer(ERC20MockInstance.address, callerInitialBalance, destination, weight, {from: caller})
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), 0);
    });

    it('TTOKEN balance should be burned if successful deposit is done', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), callerInitialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(receiver)), 0);

        await ERC20MockInstance.transferInternal(caller, XcmTransferProxyInstance.address, callerInitialBalance);
        const data = Helpers.createXcmProxyCallData(weight);
        const result = await XcmTransferProxyInstance.exec(ERC20MockInstance.address, receiver, callerInitialBalance, data, {from: caller});

        TruffleAssert.eventNotEmitted(result, 'ExecFailed');

        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(receiver)), 0);
    });

    it('TTOKEN should be send to receiver if failed deposit is done', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), callerInitialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(receiver)), 0);

        await ERC20MockInstance.transferInternal(caller, XcmTransferProxyInstance.address, callerInitialBalance);
        const result = await XcmTransferProxyInstance.exec(ERC20MockInstance.address, receiver, callerInitialBalance, "0x00", {from: caller});

        TruffleAssert.eventEmitted(result, 'ExecFailed');

        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(receiver)), callerInitialBalance);
    });

});
