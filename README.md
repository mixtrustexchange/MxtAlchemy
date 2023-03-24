# Alchemy


## Documentation

Please refer to the [Official Documentation](https://alchemy-v3-docs.vercel.app/) for high level concepts of the Alchemy v3 protocol, as well as auto generated docs from natspec.

## Package structure

This is a monorepo with the following folder structure and packages:

```
.
├── markets                      // Standalone projects that extend the core Alchemy protocol with markets.
│   ├── legacy-market            // Market that connects Alchemy's v2 and v3 versions.
│   └── spot-market              // Market extension for spot synths.
│
├── protocol                     // Core Alchemy protocol projects.
│   ├── oracle-manager           // Composable oracle and price provider for teh core protocol.
│   └── alchemy                // Core protocol (to be extended by markets).
│
└── utils                        // Utilities, plugins, tooling.
    ├── common-config            // Common npm and hardhat configuration for multiple packages in the monorepo.
    ├── core-contracts           // Standard contract implementations like ERC20, adapted for custom router storage.
    ├── core-modules             // Modules intended to be reused between multiple router based projects.
    ├── core-utils               // Simple Javascript/Typescript utilities that are used in other packages (e.g. test utils, etc).
    ├── router                   // Cannon plugin that merges multiple modules into a router contract.
    ├── hardhat-storage          // Hardhat plugin used to detect storage collisions between proxy implementations.
    └── sample-project           // Sample project based on router proxy and cannon.
```

## Router Proxy

All projects in this monorepo that involve contracts use a proxy architecture developed by Alchemy referred to as the "Router Proxy". It is basically a way to merge several contracts, which we call "modules", into a single implementation contract which is the router itself. This router is used as the implementation of the main proxy of the system.

See the [Router README](utils/router/README.md) for more details.

⚠️ When using the Router as an implementation of a UUPS [Universal Upgradeable Proxy Standard](https://eips.ethereum.org/EIPS/eip-1822) be aware that any of the public functions defined in the Proxy could clash and override any of the Router modules functions. A malicious proxy owner could use this type of obfuscation to have users run code which they do not want to run. You can imagine scenarios where the function names do not look similar but share a function selector. ⚠️

## Information for Developers

If you intend to develop in this repository, please read the following items.

### Installation Requirements

- [Foundry](https://getfoundry.sh/)
- NPM version 8
- Node version 16

### Console logs in contracts

In the contracts, use `import "hardhat/console.sol";`, then run `DEBUG=cannon:cli:rpc yarn test`.

## Deployment Guide

Deployment of the protocol is managed in the [alchemy-deployments repository](https://github.com/alchemyio/alchemy-deployments).

To prepare for system upgrades, this repository is used to release new versions of the [protocol](/protocol) and [markets](/markets).

### Preparing a Release

- Ensure you have the latest version of [Cannon](https://usecannon.com) installed: `@usecannon/cli` and `hardhat-cannon` are upgraded to the latest through the repository (use `yarn upgrade-interactive` command).
- After installing for the first time, run `yarn cannon:setup` to configure IPFS and a reliable RPC endpoint to communicate with the Cannon package registry.
- Confirm the private key that owns the corresponding namespace in the package registry is available as `$DEPLOYER_PRIVATE_KEY`.
- Confirm you are on the `main` branch and there are no git changes `git diff --exit-code .`
- Publish the release with `yarn publish:canary` for the alpha pre-release and `yarn publish:release` for the proper semver release.
- In case cannon publish fails you can run `yarn postpublish` in the root to retry publishing all cannon packages. Or `yarn publish-contracts` in each failed package separately

Then, follow the instructions in the [alchemy-deployments repository](https://github.com/alchemyio/alchemy-deployments).

### Finalizing a Release

After the new version of the [alchemy-omnibus](https://usecannon.com/packages/alchemy-omnibus) package has been published, the previously published packages can be verified on Etherscan.

From the relevant package's directory, run the following command for each network it was deployed on: `yarn hardhat cannon:verify <PACKAGE_NAME>:<VERSION> --network <NETWORK_NAME>`
