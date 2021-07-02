const StreamingLibrary = artifacts.require('StreamingLibrary');
const SocialTokenMock = artifacts.require('SocialTokenMock');
const StreamingManager = artifacts.require('StreamingManager');

const { settings } = require('../config');
const TOKEN_NAME = settings.development.tokenName;
const TOKEN_SYMBOL = settings.development.tokenSymbol;

module.exports = async function (_deployer, network, accounts) {
  await _deployer.deploy(StreamingLibrary);

  _deployer.link(StreamingLibrary, [SocialTokenMock]);

  // this should be the deployed social token contract in production
  await _deployer.deploy(SocialTokenMock, 10 ** 9, TOKEN_NAME, TOKEN_SYMBOL);

  await _deployer.deploy(StreamingManager, SocialTokenMock.address);

  let social_token = await SocialTokenMock.deployed();
  social_token.setStreamingManagerAddress(StreamingManager.address);
};
