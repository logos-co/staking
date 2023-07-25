require("@nomicfoundation/hardhat-toolbox");
require("dotenv").config();

const INFURA_API_KEY = process.env.INFURA_API_KEY;
const ETHERSCAN_API_KEY = process.env.ETHERSCAN_API_KEY;
const ETHERSCAN_OPT_API_KEY = process.env.ETHERSCAN_OPT_API_KEY;
const MAINNET_PRIVATE_KEY = process.env.MAINNET_PRIVATE_KEY;
const GOERLI_PRIVATE_KEY = process.env.GOERLI_PRIVATE_KEY;
const OP_GOERLI_ALCHEMY_KEY = process.env.GOERLI_PRIVATE_KEY;

/** @type import('hardhat/config').HardhatUserConfig */
module.exports = {
  solidity: "0.8.18",
  networks: {
    'mainnet': {
      url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
      accounts: { mnemonic: process.env.MAINNET_MNEMONIC },
    },
    'goerli': {
      url: `https://goerli.infura.io/v3/${INFURA_API_KEY}`,
      accounts: { mnemonic: process.env.GOERLI_MNEMONIC },
    },
    'optimism-goerli': {
      chainId: 420,
      url: `https://opt-goerli.g.alchemy.com/v2/${process.env.OP_GOERLI_ALCHEMY_KEY}`,
      accounts: { mnemonic: process.env.GOERLI_MNEMONIC },
      saveDeployments: true
    },
    'optimism-mainnet': {
      chainId: 10,
      url: `https://opt-mainnet.g.alchemy.com/v2/${process.env.MAINNET_ALCHEMY_KEY}`,
      accounts: { mnemonic: process.env.MAINNET_MNEMONIC }
    }
  },
  etherscan: {
    apiKey: {
      mainnet: ETHERSCAN_API_KEY,
      optimisticEthereum: ETHERSCAN_OPT_API_KEY,
      optimisticGoerli: ETHERSCAN_OPT_API_KEY
    }
  },
  mocha: {
    timeout: 100000000,
  }
  
};
