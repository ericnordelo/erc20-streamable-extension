const SocialTokenMock = artifacts.require('SocialTokenMock');
const StreamingManager = artifacts.require('StreamingManager');
const { settings } = require('../config');

const TOKEN_NAME = settings.development.tokenName;
const TOKEN_SYMBOL = settings.development.tokenSymbol;

contract('SocialTokenMock', function (accounts) {
  var social_token;
  var streaming_manager;
  beforeEach(async function () {
    social_token = await SocialTokenMock.new(10 ** 9, { from: accounts[0] });
    streaming_manager = await StreamingManager.new(social_token.address, { from: accounts[0] });

    social_token.setStreamingManagerAddress(streaming_manager.address, { from: accounts[0] });
  });

  describe('general behavior', function () {
    it('deploys streaming manager contract', () => {
      assert.ok(streaming_manager.address);
    });

    it('deploys social token contract', () => {
      assert.ok(social_token.address);
    });

    it('should has correct name', async function () {
      return assert.equal(await social_token.name(), TOKEN_NAME, 'Invalid social token name');
    });

    it('should has correct symbol', async function () {
      return assert.equal(await social_token.symbol(), TOKEN_SYMBOL, 'Invalid social token symbol');
    });
  });

  describe('create streamings', function () {
    it('deploys streaming manager contract', () => {
      assert.ok(streaming_manager.address);
    });
  });
});
