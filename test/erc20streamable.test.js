const SocialTokenMock = artifacts.require('SocialTokenMock');
const StreamingManager = artifacts.require('StreamingManager');
const { expectEvent, expectRevert, constants } = require('@openzeppelin/test-helpers');
const { settings } = require('../config');

const TOKEN_NAME = settings.development.tokenName;
const TOKEN_SYMBOL = settings.development.tokenSymbol;

contract('SocialTokenMock', function (accounts) {
  var social_token;
  var streaming_manager;
  beforeEach(async function () {
    social_token = await SocialTokenMock.new(10 ** 9, TOKEN_NAME, TOKEN_SYMBOL, { from: accounts[0] });
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
    let streaming = {
      stype: 'classic',
      senderAddress: accounts[1],
      receiverAddress: accounts[5],
      amountPerSecond: 10,
      startingDate: Math.floor(Date.now() / 1000),
      endingDate: Math.floor(Date.now() / 1000) + 1000,
    };

    it("can't create streaming with invalid type", async () => {
      let new_streaming = { ...streaming };
      new_streaming.stype = 'not classic';
      await expectRevert(social_token.createStreaming(new_streaming, { from: accounts[1] }), 'Invalid type');
    });

    it("can't create streaming with invalid sender", async () => {
      let new_streaming = { ...streaming };
      await expectRevert(social_token.createStreaming(new_streaming, { from: accounts[2] }), 'Invalid sender');
    });

    it("can't create streaming with invalid receiver", async () => {
      let new_streaming = { ...streaming };
      new_streaming.receiverAddress = constants.ZERO_ADDRESS;
      await expectRevert(social_token.createStreaming(new_streaming, { from: accounts[1] }), 'Invalid receiver');
    });

    it("can't create streaming with invalid amount per second", async () => {
      let new_streaming = { ...streaming };
      new_streaming.amountPerSecond = 0;
      await expectRevert(
        social_token.createStreaming(new_streaming, { from: accounts[1] }),
        'Invalid amount per second'
      );
    });

    it("can't create streaming with invalid ending date", async () => {
      let new_streaming = { ...streaming };
      new_streaming.endingDate = 1624845827;
      await expectRevert(social_token.createStreaming(new_streaming, { from: accounts[1] }), 'Invalid ending date');
    });

    it("can't create two streamings to same address", async () => {
      let new_streaming = { ...streaming };
      new_streaming.senderAddress = accounts[0];
      await social_token.createStreaming(new_streaming, { from: accounts[0] });
      await expectRevert(
        social_token.createStreaming(new_streaming, { from: accounts[0] }),
        "Can't open two streams to same address"
      );
    });

    it("can't create streaming without enough balance", async () => {
      let new_streaming = { ...streaming };
      await expectRevert(social_token.createStreaming(new_streaming, { from: accounts[1] }), 'Not enough balance');
    });

    it('can create streaming (emit event)', async () => {
      let new_streaming = { ...streaming };
      new_streaming.senderAddress = accounts[0];
      expectEvent(await social_token.createStreaming(new_streaming, { from: accounts[0] }), 'StreamingCreated', {
        from: accounts[0],
        to: accounts[5],
        id: '1',
        endingDate: String(new_streaming.endingDate),
      });
    });

    it('can create streaming (correct balance in manager)', async () => {
      let new_streaming = { ...streaming };
      new_streaming.senderAddress = accounts[0];
      await social_token.createStreaming(new_streaming, { from: accounts[0] });

      // 15 seconds windows, so aproximated value
      let balanceExpected = new_streaming.amountPerSecond * (new_streaming.endingDate - new_streaming.startingDate);
      let difference = new_streaming.amountPerSecond * 15;
      let actualBalance = await social_token.balanceOf(streaming_manager.address);

      assert.isAbove(actualBalance.toNumber(), balanceExpected - difference);
      assert.isBelow(actualBalance.toNumber(), balanceExpected + difference);
    });
  });

  describe('update streamings', function () {
    let streaming = {
      stype: 'classic',
      senderAddress: accounts[0],
      receiverAddress: accounts[5],
      amountPerSecond: 10,
      startingDate: Math.floor(Date.now() / 1000),
      endingDate: Math.floor(Date.now() / 1000) + 1000,
    };

    let streamingUpdateRequest = {
      amountPerSecond: 15,
      endingDate: Math.floor(Date.now() / 1000) + 1500,
    };

    it("can't update unexisting streaming", async () => {
      await expectRevert(
        social_token.updateStreaming(1, streamingUpdateRequest, { from: accounts[1] }),
        'Unexisting streaming'
      );
    });

    it("can't update with invalid request", async () => {
      let new_streaming = { ...streaming };
      let invalidStreamingUpdateRequest = { ...streamingUpdateRequest, amountPerSecond: 0 };
      await social_token.createStreaming(new_streaming, { from: accounts[0] });
      await expectRevert(
        social_token.updateStreaming(1, invalidStreamingUpdateRequest, { from: accounts[0] }),
        'Invalid request'
      );
    });

    it('can update streaming', async () => {
      let new_streaming = { ...streaming };

      await social_token.createStreaming(new_streaming, { from: accounts[0] });

      expectEvent(
        await social_token.updateStreaming(1, streamingUpdateRequest, { from: accounts[0] }),
        'StreamingUpdated',
        {
          from: new_streaming.senderAddress,
          to: new_streaming.receiverAddress,
          id: '1',
          endingDate: String(streamingUpdateRequest.endingDate),
        }
      );

      let streamingInstance = await social_token.getStreaming(1, { from: accounts[0] });
      assert.strictEqual(streamingInstance.amountPerSecond, String(streamingUpdateRequest.amountPerSecond));
      assert.strictEqual(streamingInstance.endingDate, String(streamingUpdateRequest.endingDate));
    });
  });

  describe('stop streamings', function () {
    let streaming = {
      stype: 'classic',
      senderAddress: accounts[0],
      receiverAddress: accounts[5],
      amountPerSecond: 10,
      startingDate: Math.floor(Date.now() / 1000),
      endingDate: Math.floor(Date.now() / 1000) + 1000,
    };

    it('can stop streaming', async () => {
      let new_streaming = { ...streaming };

      await social_token.createStreaming(new_streaming, { from: accounts[0] });

      expectEvent(await social_token.stopStreaming(1, { from: accounts[0] }), 'StreamingStopped', {
        from: new_streaming.senderAddress,
        to: new_streaming.receiverAddress,
      });

      await expectRevert(social_token.getStreaming(1, { from: accounts[0] }), 'Unexisting streaming');
    });
  });
});
