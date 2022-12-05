const TruffleAssert = require('truffle-assertions');
const Ethers = require('ethers');
const Helpers = require('../helpers');

const XcmTransferProxyContract = artifacts.require("AnycallProxy_XcmTransfer");
const xTokensMockContract = artifacts.require("xTokensMock");
const ERC20MockContract = artifacts.require("ERC20Mock");

contract('XcmTransferProxy - [execXcmTransfer]', async (accounts) => {
    const mpc = accounts[0];
    const caller = accounts[1];
    const receiver = accounts[2];
    const callerInitialBalance = 10000000000;
    const weight = 100;

    let XcmTransferProxyInstance;
    let ERC20MockInstance;
    let xTokensMockInstance;

    beforeEach(async () => {
        xTokensMockInstance = await xTokensMockContract.new();
        XcmTransferProxyInstance = await XcmTransferProxyContract.new(mpc, caller, xTokensMockInstance.address);
        ERC20MockInstance = await ERC20MockContract.new("Test Token", "TTOKEN", caller, callerInitialBalance);
    });

    it(`non-contract itself can't call execXcmTransfer`, async () => {
        await ERC20MockInstance.transferInternal(caller, XcmTransferProxyInstance.address, callerInitialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), callerInitialBalance);
        const data = Helpers.createXcmProxyCallData(weight);
        await TruffleAssert.reverts(XcmTransferProxyInstance.execXcmTransfer(ERC20MockInstance.address, callerInitialBalance, data, {from: caller}));
        await TruffleAssert.reverts(XcmTransferProxyInstance.execXcmTransfer(ERC20MockInstance.address, callerInitialBalance, data, {from: mpc}));
        await TruffleAssert.reverts(XcmTransferProxyInstance.execXcmTransfer(ERC20MockInstance.address, callerInitialBalance, data, {from: receiver}));
    });


});
