const PriviTestToken = artifacts.require("PriviTestToken");

/*
 * uncomment accounts to access the test accounts made available by the
 * Ethereum client
 * See docs: https://www.trufflesuite.com/docs/truffle/testing/writing-tests-in-javascript
 */
contract("PriviTestToken", function (accounts) {
  var token;
  beforeEach(async function () {
    token = await PriviTestToken.deployed();
  });

  it("should assert true", function () {
    return assert.isTrue(true);
  });
  it("should has correct name", async function () {
    return assert.equal(await token.name(), "PriviTestToken", "Invalid token name");
  });
  it("should has correct symbol", async function () {
    return assert.equal(await token.symbol(), "PTT", "Invalid token symbol");
  });
  it("should get balance from helper library", async function () {
    let balance = await token.balanceOf.call(accounts[0]);
    return assert.equal(balance.toNumber(), 1000000000, "Library function returned unexpected function, linkage may be broken");
  });
  it("should be able to transfer", async function () {
    await token.transfer(accounts[1], 15, {from: accounts[0]});
    let balance = await token.balanceOf(accounts[1]);
    return assert.equal(balance.toNumber(), 15, "Balance was not updated accordingly");
  });
});
