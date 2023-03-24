//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@alchemyio/spot-market/contracts/interfaces/IAtomicOrderModule.sol";
import "@alchemyio/spot-market/contracts/interfaces/ISpotMarketFactoryModule.sol";

interface ISpotMarketSystem is IAtomicOrderModule, ISpotMarketFactoryModule {}
