# Privi ERC20 Streaming extension

## Overview

​
Abstract smart contract to extend ERC20s, in order to add streamings capability.

#### 1. Streamings

Each streaming contains an amount per second, a starting date, and ending date, a sender an a receiver. Can only exist one streaming between to addresses.

#### 2. Flows

A flow between to addresses is a directed relationship which summarizes the streamings where sender address is the flow sender, and receiver address is the flow receiver. This concept allows to scale consulting over balances, because the contract doesn't need to loop over strreamings.
​

## Addresses of deployed contract on mumbai network

`pDAI`: 0x055DF778d99e147657CeA05254deF1fdBee04A95  
`pUSDT`: 0x6cbC0a9d98a573e0dbF8315eE3038A4454eca031
​

## Addresses of deployed contract on mainnet

​
_TODO: Add mainnet smart contract addresses_
​

## Deployment

​

### Environment Setup

​

1. First clone this repository to your computer.

```
$ git clone ...
$ cd erc20-streamable-extension/
```

2. Then install the node modules.

```
$ npm install
```

3. Create .env in the folder. Fill out all info needed on those files in according to .env.example file.

```
MNEMONIC=[the 12 mnemonic words]
INFURA_API_KEY=[your API key]
ETHER_SCAN_API_KEY=[your API key]
```

​

### Deploy to Local Machine

​

1. Run development server using Truffle.

```
$ truffle develop
```

​ 2. Deploy contracts.

```
$ truffle migrate
```

​

### Deploy to Testnet (Mumbai)

​

```
$ truffle migrate --network mumbai
```

​

### Deploy to Mainnet

​

```
$ truffle migrate --network mainnet
```

​

## References

​

1. Truffle Commands: https://www.trufflesuite.com/docs/truffle/reference/truffle-commands
   ​
2. ERC-721: https://eips.ethereum.org/EIPS/eip-721
   ​
3. IPFS https://ipfs.io/
   ​
4. Bonding Curve https://coinmarketcap.com/alexandria/glossary/bonding-curve#:~:text=A%20bonding%20curve%20is%20a%20mathematical%20concept%20used%20to%20describe,pay%20slightly%20more%20for%20it.
   ​
5. ChainLink Ethereum Price Feeds. https://docs.chain.link/docs/ethereum-addresses/
   ​
6. Flash loan attack https://coinmarketcap.com/alexandria/article/what-are-flash-loan-attacks
