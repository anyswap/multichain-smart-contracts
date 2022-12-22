const TruffleAssert = require('truffle-assertions');
const Ethers = require('ethers');
const Helpers = require('../helpers');

const XcmTransferProxyContract = artifacts.require("AnycallProxy_XcmTransfer");
const XTokensMockContract = artifacts.require("xTokensMock");
const ERC20MockContract = artifacts.require("ERC20Mock");

contract('XcmTransferProxy - [skim]', async (accounts) => {
    const mpc = accounts[0];
    const caller = accounts[1];
    const user = accounts[2];
    const initialBalance = 10000000000;

    let XcmTransferProxyInstance;
    let ERC20MockInstance;
    let xTokensMockInstance;

    beforeEach(async () => {
        xTokensMockInstance = await XTokensMockContract.new();
        XcmTransferProxyInstance = await XcmTransferProxyContract.new(mpc, caller, xTokensMockInstance.address);
        ERC20MockInstance = await ERC20MockContract.new("Test Token", "TTOKEN", XcmTransferProxyInstance.address, initialBalance);
    });

    it('tokens should be send to recipient', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), initialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(mpc)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(user)), 0);

        await XcmTransferProxyInstance.skim(ERC20MockInstance.address, user, {from: mpc});

        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(mpc)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(user)), initialBalance);
    });

    it('only mpc can withdraw tokens', async () => {
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), initialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(mpc)), 0);

        await TruffleAssert.reverts(
            XcmTransferProxyInstance.skim(ERC20MockInstance.address, mpc, {from: caller}),
            "MPC: only mpc"
        );

        await TruffleAssert.reverts(
            XcmTransferProxyInstance.skim(ERC20MockInstance.address, mpc, {from: user}),
            "MPC: only mpc"
        );

        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(XcmTransferProxyInstance.address)), initialBalance);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(caller)), 0);
        assert.strictEqual(Number(await ERC20MockInstance.balanceOf(user)), 0);
    });

});
