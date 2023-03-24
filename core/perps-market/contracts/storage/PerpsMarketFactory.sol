//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@alchemyio/core-modules/contracts/interfaces/ITokenModule.sol";
import "@alchemyio/oracle-manager/contracts/interfaces/INodeModule.sol";
import "@alchemyio/main/contracts/interfaces/IMarketCollateralModule.sol";
import "@alchemyio/core-contracts/contracts/utils/SafeCast.sol";
import "@alchemyio/core-contracts/contracts/utils/SetUtil.sol";

import "../interfaces/external/IAlchemySystem.sol";
import "../interfaces/external/ISpotMarketSystem.sol";
import "../utils/MathUtil.sol";

/**
 * @title Main factory library that registers perps markets.  Also houses global configuration for all perps markets.
 */
library PerpsMarketFactory {
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;

    bytes32 private constant _SLOT_PERPS_MARKET_FACTORY =
        keccak256(abi.encode("io.alchemy.perps-market.PerpsMarketFactory"));

    error OnlyMarketOwner(address marketOwner, address sender);
    error InvalidMarket(uint128 marketId);

    error MaxCollateralExceeded(uint128 marketId);

    struct Data {
        /**
         * @dev oracle manager address used for price feeds
         */
        INodeModule oracle;
        ITokenModule usdToken;
        /**
         * @dev Alchemy core v3 proxy address
         */
        IAlchemySystem alchemy;
        ISpotMarketSystem spotMarket;
        // max collateral amounts / market
        mapping(uint128 => uint) maxCollateralAmounts;
        uint128[] deductionMarketOrder;
        uint maxLeverage;
        SetUtil.UintSet liquidatableAccounts;
        // collateral amounts running total
        mapping(uint128 => uint) collateralAmounts;
    }

    function load() internal pure returns (Data storage perpsMarketFactory) {
        bytes32 s = _SLOT_PERPS_MARKET_FACTORY;
        assembly {
            perpsMarketFactory.slot := s
        }
    }

    /*
        1. checks to ensure max cap isn't hit
        2. adjusts accounting for collateral amounts
    */
    function checkCollateralAmountAndAdjust(
        Data storage self,
        uint128 synthMarketId,
        int synthAmount
    ) internal {
        if (synthAmount > 0) {
            if (
                self.collateralAmounts[synthMarketId] + synthAmount.toUint() >
                self.maxCollateralAmounts[synthMarketId]
            ) {
                revert MaxCollateralExceeded(synthMarketId);
            } else {
                self.collateralAmounts[synthMarketId] += synthAmount.toUint();
            }
        } else {
            self.collateralAmounts[synthMarketId] -= MathUtil.abs(synthAmount);
        }
    }

    function depositToMarketManager(Data storage self, uint128 marketId, uint256 amount) internal {
        self.usdToken.approve(address(this), amount);
        self.alchemy.depositMarketUsd(marketId, address(this), amount);
    }
}
