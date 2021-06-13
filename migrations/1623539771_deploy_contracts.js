var PriviTestToken = artifacts.require("PriviTestToken");

module.exports = function(deployer) {
  // deployment steps
  deployer.deploy(PriviTestToken);
};