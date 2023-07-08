require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const INFURA_API_KEY = process.env.INFURA_API_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const GOERLI_PRIVATE_KEY = process.env.GOERLI_PRIVATE_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  networks: {
    'optimism-goerli': {
      chainId: 420,
      url: `https://opt-goerli.g.alchemy.com/v2/${process.env.L2_ALCHEMY_KEY}`,
      accounts: { mnemonic: process.env.MNEMONIC }
    },
    'optimism-mainnet': {
      chainId: 10,
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.L2_ALCHEMY_KEY}`,
      accounts: { mnemonic: process.env.MNEMONIC }
    },
    'goerli': {
      url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
      accounts: [GOERLI_PRIVATE_KEY]
    }
  },
  etherscan: {
    apiKey: ETHERSCAN_API_KEY,
  },
  mocha: {
    timeout: 100000000,
  }
  
};
