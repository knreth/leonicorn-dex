const LeoniLottery = artifacts.require("LeonicornSwapLottery");
const RandNumGen = artifacts.require("RandomNumberGenerator");
const {
    LEON_ADDRESS
} = process.env;

module.exports = async function(deployer) {
	let randNumGen = await RandNumGen.deployed();
	return deployer.deploy(LeoniLottery, LEON_ADDRESS, randNumGen.address); 
};
