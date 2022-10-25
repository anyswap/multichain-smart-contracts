async function main() {
    const transferAmount = '100000000000000000000'; // 100 xcBNB
    const weight = 1000000000; // there may be different values for different parachains
    const parachainId = '0x00000007DB'; // Equilibrium Parachain
    const recipientAddress = "4829b1e41449bd2cc7f04df856052f4d439f2f3e7f346c9702b94928ddf04707"; // Public key format
    const parents = 1; // Up to relay-chain (Polkadot/Kusama chain)
    // Format: 0x01 + AccountId32 + 00 (https://docs.moonbeam.network/builders/xcm/xc20/xtokens/ -> "The X-Tokens Solidity Interface")
    const formattedRecipient = "0x01" + recipientAddress + "00";
    const interior = [parachainId, formattedRecipient];

    const dataPassedToDest = ethers.utils.defaultAbiCoder.encode(["tuple(uint256, tuple(uint8,bytes[]),uint64)"],
        [[transferAmount, [parents, interior], weight]]);
    console.log(`dataPassedToDest: ${dataPassedToDest}`)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
