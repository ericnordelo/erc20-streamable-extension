var HelperLibrary = artifacts.require("HelperLibrary");
var PriviTestToken = artifacts.require("PriviTestToken");

module.exports = function(deployer) {
  // deploy with initialSupply set to 100
  deployer.deploy(HelperLibrary);
  deployer.link(HelperLibrary, PriviTestToken);
  deployer.deploy(PriviTestToken, 100);
};