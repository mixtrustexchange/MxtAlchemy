require('@nomiclabs/hardhat-ethers');
require('hardhat-cannon');
require('@alchemyio/hardhat-storage');
require('@alchemyio/router/utils/cannon');

module.exports = {
  solidity: {
    version: '0.8.17',
    settings: {
      optimizer: {
        enabled: true,
        runs: 200,
      },
    },
  },
  defaultNetwork: 'cannon',
};
