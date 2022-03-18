const { ethers } = require("ethers");
const web3 = require("web3")
const eth = {};

eth.getProvider = function (network) {
    return new ethers.providers.Web3Provider(new web3.providers.HttpProvider(network));
}

eth.loadContract = function (contractAddr, contractAbi, eth_wallet) {
    return new ethers.Contract(contractAddr, contractAbi, eth_wallet);
}

eth.deployContract = function (contractAbi, contractCode, eth_wallet) {
    return new ethers.ContractFactory(contractAbi, contractCode, eth_wallet);
}

eth.loadWallet = async function (privateKey, network) {
    return new ethers.Wallet(privateKey, await eth.getProvider(network));
}

eth.loadInterface = function (abi) {
    return new ethers.utils.Interface(abi);
}

eth.loadAbiCoder = function () {
    return ethers.utils.defaultAbiCoder;
}

eth.constant = ethers.constants;

module.exports = eth;