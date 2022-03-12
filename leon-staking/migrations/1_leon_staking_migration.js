const LeonStaking = artifacts.require("LeonStaking");
const {
  LEON_TOKEN,
  REWARD_ADDRESS
} = process.env;

module.exports = function (deployer) {
  deployer.deploy(LeonStaking, LEON_TOKEN, REWARD_ADDRESS);
};
