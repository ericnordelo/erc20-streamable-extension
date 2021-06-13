var PriviTestToken = artifacts.require("PriviTestToken");

module.exports = function(deployer) {
  // deploy with initialSupply set to 100
  deployer.deploy(PriviTestToken, 100);
};