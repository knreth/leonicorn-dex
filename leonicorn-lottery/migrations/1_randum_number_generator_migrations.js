const RandNumGen = artifacts.require("RandomNumberGenerator");

const {
    LINK_CONTRACT,
    VRF_COORDINATOR_ADDRESS	
} = process.env;

module.exports = function (deployer) {
  deployer.deploy(RandNumGen, VRF_COORDINATOR_ADDRESS, LINK_CONTRACT);
};
