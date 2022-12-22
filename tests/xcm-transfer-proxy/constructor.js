const TruffleAssert = require('truffle-assertions');
const Ethers = require('ethers');

const XcmTransferProxyContract = artifacts.require("AnycallProxy_XcmTransfer");

contract('XcmTransferProxy - [constructor]', async (accounts) => {
    const mpc = accounts[0];
    const caller = accounts[1];
    const xTokensContractAddress = '0x0000000000000000000000000000000000000804';


    let XcmTransferProxyInstance;

    beforeEach(async () => {
        XcmTransferProxyInstance = await XcmTransferProxyContract.new(mpc, caller, xTokensContractAddress);
    });

    it('[sanity] contract should be deployed successfully', async () => {
        await TruffleAssert.passes(await XcmTransferProxyContract.new(mpc, caller, xTokensContractAddress));
    });

    it('MPC, caller and XTokens should be correctly set', async () => {
        assert.strictEqual(await XcmTransferProxyInstance.mpc(), mpc);
        assert.strictEqual(await XcmTransferProxyInstance.pendingMPC(), Ethers.constants.AddressZero);
        assert.strictEqual(Number(await XcmTransferProxyInstance.delayMPC()), 0);
        assert.strictEqual(await XcmTransferProxyInstance.supportedCaller(caller), true);
        assert.strictEqual(await XcmTransferProxyInstance.xTokens(), xTokensContractAddress);
    });
});
