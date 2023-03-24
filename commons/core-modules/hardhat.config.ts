import commonConfig from '@alchemyio/common-config/hardhat.config';

const config = {
  ...commonConfig,
  mocha: {
    timeout: 120000,
  },
};

export default config;
