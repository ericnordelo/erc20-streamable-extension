const SocialTokenMock = artifacts.require('SocialTokenMock');
const StreamingManager = artifacts.require('StreamingManager');

const { settings } = require('../config');

module.exports = async function (_deployer, network, accounts) {
  // this should be the deployed social token contract in production
  await _deployer.deploy(SocialTokenMock, 10 ** 9);

  await _deployer.deploy(StreamingManager, SocialTokenMock.address);

  let social_token = await SocialTokenMock.deployed();
  social_token.setStreamingManagerAddress(StreamingManager.address);
};
