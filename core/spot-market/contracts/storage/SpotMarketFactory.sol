//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import "@alchemyio/core-modules/contracts/interfaces/ITokenModule.sol";
import "@alchemyio/oracle-manager/contracts/interfaces/INodeModule.sol";
import "../interfaces/external/IAlchemySystem.sol";
import "./Price.sol";

/**
 * @title Main factory library that registers synths.  Also houses global configuration for all synths.
 */
library SpotMarketFactory {
    bytes32 private constant _SLOT_SPOT_MARKET_FACTORY =
        keccak256(abi.encode("io.alchemy.spot-market.SpotMarketFactory"));

    using Price for Price.Data;

    error OnlyMarketOwner(address marketOwner, address sender);
    error InvalidMarket(uint128 marketId);

    struct Data {
        /**
         * @dev alchemyUSD token address
         */
        ITokenModule usdToken;
        /**
         * @dev oracle manager address used for price feeds
         */
        INodeModule oracle;
        /**
         * @dev Alchemy core v3 proxy
         */
        IAlchemySystem alchemy;
        /**
         * @dev when synth is registered, this is the initial implementation address the proxy services.
         */
        address initialSynthImplementation;
        /**
         * @dev mapping of marketId to marketOwner
         */
        mapping(uint128 => address) marketOwners;
        /**
         * @dev mapping of marketId to marketNominatedOwner
         */
        mapping(uint128 => address) nominatedMarketOwners;
    }

    function load() internal pure returns (Data storage spotMarketFactory) {
        bytes32 s = _SLOT_SPOT_MARKET_FACTORY;
        assembly {
            spotMarketFactory.slot := s
        }
    }

    function onlyMarketOwner(Data storage self, uint128 marketId) internal view {
        address marketOwner = self.marketOwners[marketId];

        if (marketOwner != msg.sender) {
            revert OnlyMarketOwner(marketOwner, msg.sender);
        }
    }

    function isValidMarket(Data storage self, uint128 marketId) internal view {
        if (self.marketOwners[marketId] == address(0)) {
            revert InvalidMarket(marketId);
        }
    }

    /**
     * @dev first creates an allowance entry in usdToken for market manager, then deposits alchemyUSD amount into mm.
     */
    function depositToMarketManager(Data storage self, uint128 marketId, uint256 amount) internal {
        self.usdToken.approve(address(this), amount);
        self.alchemy.depositMarketUsd(marketId, address(this), amount);
    }
}
