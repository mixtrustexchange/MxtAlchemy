//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@alchemyio/core-modules/contracts/interfaces/IAssociatedSystemsModule.sol";
import "@alchemyio/main/contracts/interfaces/IMarketManagerModule.sol";
import "@alchemyio/main/contracts/interfaces/IUtilsModule.sol";

interface IAlchemySystem is IAssociatedSystemsModule, IMarketManagerModule, IUtilsModule {}
