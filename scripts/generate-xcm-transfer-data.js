async function main() {
    const parents = 1; // Up to relay-chain (Polkadot/Kusama chain)

    const parachainId = '0x00000007DB'; // Equilibrium Parachain
    const recipientAddress = "4829b1e41449bd2cc7f04df856052f4d439f2f3e7f346c9702b94928ddf04707"; // Public key format
    // Format: 0x01 + AccountId32 + 00 (https://docs.moonbeam.network/builders/xcm/xc20/xtokens/ -> "The X-Tokens Solidity Interface")
    const formattedRecipient = "0x01" + recipientAddress + "00";
    const interior = [parachainId, formattedRecipient];

    const weight = 800_000_000; // there may be different values for different parachains

    const dataPassedToDest = ethers.utils.defaultAbiCoder.encode(["tuple(tuple(uint8,bytes[]),uint64)"],
        [[ [parents, interior], weight]]);
    console.log(`dataPassedToDest: ${dataPassedToDest}`)
}

main()
    .then(() => process.exit(0))
    .catch(error => {
        console.error(error);
        process.exit(1);
    });
