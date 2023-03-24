//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@alchemyio/core-contracts/contracts/utils/SafeCast.sol";
import "@alchemyio/core-contracts/contracts/utils/DecimalMath.sol";

import "../interfaces/external/IFeeCollector.sol";
import "./SpotMarketFactory.sol";
import "./AsyncOrder.sol";
import "./OrderFees.sol";
import "../utils/SynthUtil.sol";
import "../utils/MathUtil.sol";
import "../utils/TransactionUtil.sol";

/**
 * @title Fee storage that tracks all fees for a given market Id.
 */
library MarketConfiguration {
    using SpotMarketFactory for SpotMarketFactory.Data;
    using OrderFees for OrderFees.Data;
    using SafeCastU256 for uint256;
    using SafeCastI256 for int256;
    using DecimalMath for uint256;
    using DecimalMath for int256;

    error InvalidUtilizationLeverage();
    error InvalidCollateralLeverage(uint);

    struct Data {
        /**
         * @dev The atomic fixed fee rate for a specific transactor.  Useful for direct integrations to set custom fees for specific addresses.
         */
        mapping(address => uint) atomicFixedFeeOverrides;
        /**
         * @dev atomic buy/sell fixed fee that's applied on all trades. Percentage, 18 decimals
         */
        uint atomicFixedFee;
        /**
         * @dev buy/sell fixed fee that's applied on all async trades. Percentage, 18 decimals
         */
        uint asyncFixedFee;
        /**
         * @dev utilization fee rate (in percentage) is the rate of fees applied based on the ratio of delegated collateral to total outstanding synth exposure. 18 decimals
         * applied on buy trades only.
         */
        uint utilizationFeeRate;
        /**
         * @dev a configurable leverage % that is applied to delegated collateral which is used as a ratio for determining utilization, and locked amounts. D18
         */
        uint collateralLeverage;
        /**
         * @dev wrapping fee rate represented as a percent, 18 decimals
         */
        int wrapFixedFee;
        /**
         * @dev unwrapping fee rate represented as a percent, 18 decimals
         */
        int unwrapFixedFee;
        /**
         * @dev skewScale is used to determine % of fees that get applied based on the ratio of outstanding synths to skewScale.
         * if outstanding synths = skew scale, then 100% premium is applied to the trade.
         * A negative skew, derived based on the mentioned ratio, is applied on sell trades
         */
        uint skewScale;
        /**
         * @dev The fee collector gets sent the calculated fees and can keep some of them to distribute in whichever way it wants.
         * The rest of the fees are deposited into the market manager.
         */
        IFeeCollector feeCollector;
        /**
         * @dev Percentage share for each referrer address
         */
        mapping(address => uint) referrerShare;
    }

    function load(uint128 marketId) internal pure returns (Data storage marketConfig) {
        bytes32 s = keccak256(abi.encode("io.alchemy.spot-market.Fee", marketId));
        assembly {
            marketConfig.slot := s
        }
    }

    function isValidLeverage(uint leverage) internal pure {
        // add upper bounds for leverage here
        if (leverage == 0) {
            revert InvalidCollateralLeverage(leverage);
        }
    }

    /**
     * @dev Set custom fee for transactor
     */
    function setAtomicFixedFeeOverride(
        uint128 marketId,
        address transactor,
        uint fixedFee
    ) internal {
        load(marketId).atomicFixedFeeOverrides[transactor] = fixedFee;
    }

    /**
     * @dev Get quote for amount of collateral (`amount`) to receive in synths (`synthAmount`)
     */
    function quoteWrap(
        uint128 marketId,
        uint amount,
        uint synthPrice
    ) internal view returns (uint synthAmount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);
        uint usdAmount = amount.mulDecimal(synthPrice);
        fees.wrapperFees = config.wrapFixedFee.mulDecimal(usdAmount.toInt());
        usdAmount = (usdAmount.toInt() - fees.wrapperFees).toUint();

        synthAmount = usdAmount.divDecimal(synthPrice);
    }

    /**
     * @dev Get quote for amount of synth (`synthAmount`) to receive in collateral (`amount`)
     */
    function quoteUnwrap(
        uint128 marketId,
        uint synthAmount,
        uint synthPrice
    ) internal view returns (uint amount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);
        uint usdAmount = synthAmount.mulDecimal(synthPrice);
        fees.wrapperFees = config.unwrapFixedFee.mulDecimal(usdAmount.toInt());
        usdAmount = (usdAmount.toInt() - fees.wrapperFees).toUint();

        amount = usdAmount.divDecimal(synthPrice);
    }

    /**
     * @dev Get quote for amount of usd (`usdAmount`) to charge trader for the specified synth amount (`synthAmount`)
     */
    function quoteBuyExactOut(
        uint128 marketId,
        uint synthAmount,
        uint synthPrice,
        address transactor,
        Transaction.Type transactionType
    ) internal view returns (uint usdAmount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);
        // this amount gets fees applied below and is the return amount to charge user
        usdAmount = synthAmount.mulDecimal(synthPrice);

        int amountInt = usdAmount.toInt();

        // compute skew fee based on amount out
        int skewFee = calculateSkewFeeExact(
            config,
            marketId,
            amountInt,
            synthPrice,
            transactionType
        );

        fees.skewFees = skewFee.mulDecimal(amountInt);
        // apply fees by adding to the amount
        usdAmount = (amountInt + fees.skewFees).toUint();

        uint utilizationFee = calculateUtilizationRateFee(config, marketId, usdAmount, synthPrice);
        uint fixedFee = _getFixedFee(config, transactor, Transaction.isAsync(transactionType));
        // apply utilization and fixed fees
        // Note: when calculating exact out, we need to apply fees in reverse order.  so instead of
        // multiplying by %, we divide by %
        fees.utilizationFees = usdAmount.divDecimal(DecimalMath.UNIT - utilizationFee) - usdAmount;
        fees.fixedFees = usdAmount.divDecimal(DecimalMath.UNIT - fixedFee) - usdAmount;

        usdAmount += fees.fixedFees + fees.utilizationFees;
    }

    /**
     * @dev Get quote for amount of synths (`synthAmount`) to receive for a given amount of USD (`usdAmount`)
     */
    function quoteBuyExactIn(
        uint128 marketId,
        uint usdAmount,
        uint synthPrice,
        address transactor,
        Transaction.Type transactionType
    ) internal view returns (uint synthAmount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);

        uint utilizationFee = calculateUtilizationRateFee(config, marketId, usdAmount, synthPrice);
        uint fixedFee = _getFixedFee(config, transactor, Transaction.isAsync(transactionType));

        fees.utilizationFees = utilizationFee.mulDecimal(usdAmount);
        fees.fixedFees = fixedFee.mulDecimal(usdAmount);
        // apply utilization and fixed fees by removing from the amount to be returned to trader.
        usdAmount = usdAmount - fees.fixedFees - fees.utilizationFees;

        synthAmount = calculateSkew(config, marketId, usdAmount.toInt(), synthPrice);
        fees.skewFees = usdAmount.toInt() - synthAmount.mulDecimal(synthPrice).toInt();
    }

    /**
     * @dev Get quote for amount of synth (`synthAmount`) to burn from trader for the requested
     *      amount of USD (`usdAmount`)
     */
    function quoteSellExactOut(
        uint128 marketId,
        uint usdAmount,
        uint synthPrice,
        address transactor,
        Transaction.Type transactionType
    ) internal view returns (uint synthAmount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);

        uint synthAmountFromSkew = calculateSkew(
            config,
            marketId,
            usdAmount.toInt() * -1, // when selling, use negative amount
            synthPrice
        );

        fees.skewFees = synthAmountFromSkew.mulDecimal(synthPrice).toInt() - usdAmount.toInt();
        usdAmount = (usdAmount.toInt() + fees.skewFees).toUint();

        uint fixedFee = _getFixedFee(config, transactor, Transaction.isAsync(transactionType));
        // use the usd amount _after_ skew fee is applied to the amount
        // when exact out, fees are applied by dividing by %
        fees.fixedFees = usdAmount.divDecimal(DecimalMath.UNIT - fixedFee) - usdAmount;
        // apply fixed fee
        usdAmount += fees.fixedFees;
        // convert usd amount to synth amount to return to trader
        synthAmount = usdAmount.divDecimal(synthPrice);
    }

    /**
     * @dev Get quote for amount of USD (`usdAmount`) to receive for a given amount of synths (`synthAmount`)
     */
    function quoteSellExactIn(
        uint128 marketId,
        uint synthAmount,
        uint synthPrice,
        address transactor,
        Transaction.Type transactionType
    ) internal view returns (uint usdAmount, OrderFees.Data memory fees, Data storage config) {
        config = load(marketId);

        usdAmount = synthAmount.mulDecimal(synthPrice);

        uint fixedFee = _getFixedFee(config, transactor, Transaction.isAsync(transactionType));
        fees.fixedFees = fixedFee.mulDecimal(usdAmount);

        // apply fixed fee by removing from the amount that gets returned to user in exchange
        usdAmount -= fees.fixedFees;

        // use the amount _after_ fixed fee is applied to the amount
        // skew is calcuated based on amount after all other fees applied, to get accurate skew fee
        int usdAmountInt = usdAmount.toInt();
        int skewFee = calculateSkewFeeExact(
            config,
            marketId,
            usdAmountInt * -1, // removing value so negative
            synthPrice,
            transactionType
        );
        fees.skewFees = skewFee.mulDecimal(usdAmountInt);
        usdAmount = (usdAmountInt - fees.skewFees).toUint();
    }

    /**
     * @dev Returns a skew fee based on the exact amount of synth either being added or removed from the market (`amount`)
     * @dev This function is used when we call `buyExactOut` or `sellExactIn` where we know the exact synth leaving/added to the system.
     * @dev When we only know the USD amount and need to calculate expected synth after fees, we have to use
     *      `calculateSkew` instead.
     *
     * Example:
     *  Skew scale set to 1000 alchemyETH
     *  Before fill outstanding alchemyETH (minus any wrapped collateral): 100 alchemyETH
     *  If buy trade:
     *    - user is buying 10 ETH
     *    - skew fee = (100 / 1000 + 110 / 1000) / 2 = 0.105 = 10.5% = 1005 bips
     *  On a sell, the amount is negative, and so if there's positive skew in the system, the fee is negative to incentize selling
     *  and if the skew is negative, then the fee for a sell would be positive to incentivize neutralizing the skew.
     */
    function calculateSkewFeeExact(
        Data storage self,
        uint128 marketId,
        int amount,
        uint synthPrice,
        Transaction.Type transactionType
    ) internal view returns (int skewFee) {
        if (self.skewScale == 0) {
            return 0;
        }

        int skewScaleValue = self.skewScale.mulDecimal(synthPrice).toInt();

        uint wrappedCollateralAmount = SpotMarketFactory
            .load()
            .alchemy
            .getMarketCollateralAmount(marketId, Wrapper.load(marketId).wrapCollateralType)
            .mulDecimal(synthPrice);

        int initialSkew = SynthUtil
            .getToken(marketId)
            .totalSupply()
            .mulDecimal(synthPrice)
            .toInt() - wrappedCollateralAmount.toInt();

        int skewAfterFill = initialSkew + amount;
        int skewAverage = (skewAfterFill + initialSkew) / 2;

        skewFee = skewAverage.divDecimal(skewScaleValue);
        // fee direction is switched on sell
        if (Transaction.isSell(transactionType)) {
            skewFee = skewFee * -1;
        }
    }

    /**
     * @dev For a given USD amount, based on the skew scale, returns the exact synth amount to return or charge the trader
     * @dev This function is used when we call `buyExactIn` or `sellExactOut` where we know the USD amount and need to calculate the synth amount
     */
    function calculateSkew(
        Data storage self,
        uint128 marketId,
        int usdAmount,
        uint synthPrice
    ) internal view returns (uint synthAmount) {
        if (self.skewScale == 0) {
            return MathUtil.abs(usdAmount).divDecimal(synthPrice);
        }

        uint wrappedCollateralAmount = SpotMarketFactory.load().alchemy.getMarketCollateralAmount(
            marketId,
            Wrapper.load(marketId).wrapCollateralType
        );
        int initialSkew = SynthUtil.getToken(marketId).totalSupply().toInt() -
            wrappedCollateralAmount.toInt();

        synthAmount = MathUtil.abs(
            _calculateSkewAmountOut(self, usdAmount, synthPrice, initialSkew)
        );
    }

    /**
     * @dev Calculates utilization rate fee
     * If no utilizationFeeRate is set, then the fee is 0
     * The utilization rate fee is determined based on the ratio of outstanding synth value to the delegated collateral to the market.
     * The delegated collateral is calculated by multiplying the collateral by a configurable leverage parameter (`utilizationLeveragePercentage`)
     *
     * Example:
     *  Utilization fee rate set to 0.1%
     *  collateralLeverage: 2
     *  Total delegated collateral value: $1000 * 2 = $2000
     *  Total outstanding synth value = $2200
     *  User buys $200 worth of synths
     *  Before fill utilization rate: 2200 / 2000 = 110%
     *  After fill utilization rate: 2400 / 2000 = 120%
     *  Utilization Rate Delta = 120 - 110 = 10% / 2 (average) = 5%
     *  Fee charged = 5 * 0.001 (0.1%)  = 0.5%
     *
     * Note: we do NOT calculate the inverse of this fee on `buyExactIn` vs `buyExactOut`.  We don't
     * believe this edge case adds any risk.  This means it could be beneficial to use `buyExactIn` vs `buyExactOut`
     */
    function calculateUtilizationRateFee(
        Data storage self,
        uint128 marketId,
        uint amount,
        uint256 synthPrice
    ) internal view returns (uint utilFee) {
        if (self.utilizationFeeRate == 0 || self.collateralLeverage == 0) {
            return 0;
        }

        uint leveragedDelegatedCollateralValue = SpotMarketFactory
            .load()
            .alchemy
            .getMarketCollateral(marketId)
            .mulDecimal(self.collateralLeverage);

        uint totalBalance = SynthUtil.getToken(marketId).totalSupply();

        // Note: take into account the async order commitment amount in escrow
        uint totalValueBeforeFill = totalBalance.mulDecimal(synthPrice);
        uint totalValueAfterFill = totalValueBeforeFill + amount;

        // utilization is below 100%
        if (leveragedDelegatedCollateralValue > totalValueAfterFill) {
            return 0;
        } else {
            uint preUtilization = totalValueBeforeFill.divDecimal(
                leveragedDelegatedCollateralValue
            );
            // use 100% utilization if pre-fill utilization was less than 100%
            // no fees charged below 100% utilization
            uint preUtilizationDelta = preUtilization > 1e18 ? preUtilization - 1e18 : 0;
            uint postUtilization = totalValueAfterFill.divDecimal(
                leveragedDelegatedCollateralValue
            );
            uint postUtilizationDelta = postUtilization - 1e18;

            // utilization is represented as the # of percentage points above 100%
            uint utilization = (preUtilizationDelta + postUtilizationDelta).mulDecimal(100e18) / 2;

            utilFee = utilization.mulDecimal(self.utilizationFeeRate);
        }
    }

    /*
     * @dev if special fee is set for a given transactor that takes precedence over the global fixed fees
     * otherwise, if async order, use async fixed fee, otherwise use atomic fixed fee
     */
    function _getFixedFee(
        Data storage self,
        address transactor,
        bool async
    ) private view returns (uint fixedFee) {
        if (self.atomicFixedFeeOverrides[transactor] > 0) {
            fixedFee = self.atomicFixedFeeOverrides[transactor];
        } else {
            fixedFee = async ? self.asyncFixedFee : self.atomicFixedFee;
        }
    }

    /**
     * @dev First sends referrer fees based on fixed fee amount and configured %
     * Then if total fees for transaction are greater than 0, gets quote from
     * fee collector and calls collectFees to send fees to fee collector
     */
    function collectFees(
        Data storage self,
        uint128 marketId,
        OrderFees.Data memory fees,
        address transactor,
        address referrer,
        SpotMarketFactory.Data storage factory,
        Transaction.Type transactionType
    ) internal returns (uint collectedFees) {
        uint referrerFeesCollected = _collectReferrerFees(
            self,
            marketId,
            fees,
            referrer,
            factory,
            transactionType
        );

        int totalFees = fees.total();
        if (totalFees <= 0 || address(self.feeCollector) == address(0)) {
            return referrerFeesCollected;
        }
        // remove fees sent to referrer when calculating fees to collect
        totalFees -= referrerFeesCollected.toInt();

        uint totalFeesUint = totalFees.toUint();
        uint feeCollectorQuote = self.feeCollector.quoteFees(
            marketId,
            totalFeesUint,
            transactor,
            // solhint-disable-next-line numcast/safe-cast
            uint8(transactionType)
        );

        // if transaction is a sell or a wrapper type, we need to withdraw the fees from the market manager
        if (Transaction.isSell(transactionType) || Transaction.isWrapper(transactionType)) {
            factory.alchemy.withdrawMarketUsd(marketId, address(this), feeCollectorQuote);
        }

        // solhint-disable-next-line numcast/safe-cast
        self.feeCollector.collectFees(marketId, totalFeesUint, transactor, uint8(transactionType));

        return referrerFeesCollected + feeCollectorQuote;
    }

    /**
     * @dev Referrer fees are a % of the fixed fee amount.  The % is retrieved from `referrerShare` and can be configured by market owner.
     * @dev If this is a sell transaction, the fee to send to referrer is withdrawn from market, otherwise it's directly transferred from the contract
     *      since funds were transferred here first.
     */
    function _collectReferrerFees(
        Data storage self,
        uint128 marketId,
        OrderFees.Data memory fees,
        address referrer,
        SpotMarketFactory.Data storage factory,
        Transaction.Type transactionType
    ) private returns (uint referrerFeesCollected) {
        if (referrer == address(0)) {
            return 0;
        }

        uint referrerPercentage = self.referrerShare[referrer];
        referrerFeesCollected = fees.fixedFees.mulDecimal(referrerPercentage);

        if (referrerFeesCollected > 0) {
            if (Transaction.isSell(transactionType)) {
                factory.alchemy.withdrawMarketUsd(marketId, referrer, referrerFeesCollected);
            } else {
                factory.usdToken.transfer(referrer, referrerFeesCollected);
            }
        }
    }

    /*
     * @dev This equation allows us to calculate skew fee % from any given point on the skew scale
     * to where we should end up after a fill.  The equation is derived from the following:
     *  K*2P * sqrt((8CP/K)+(2NiP/K + 2P)^2) - K - Ni
     *  K = configured skew scale
     *  C = amount (cost in USD)
     *  Ni = initial skew
     *  P = price
     *
     *  For a given amount in USD, this equation spits out the synth amount to be returned based on skew scale/price/initial skew
     */
    function _calculateSkewAmountOut(
        Data storage self,
        int amount,
        uint price,
        int initialSkew
    ) private view returns (int amountOut) {
        uint skewPriceRatio = self.skewScale.divDecimal(2 * price);
        int costPriceSkewRatio = (8 * amount.mulDecimal(price.toInt())).divDecimal(
            self.skewScale.toInt()
        );
        int initialSkewPriceRatio = (2 * initialSkew.mulDecimal(price.toInt())).divDecimal(
            self.skewScale.toInt()
        );

        int ratioSquared = MathUtil.pow(initialSkewPriceRatio + 2 * price.toInt(), 2);
        int sqrt = MathUtil.sqrt(costPriceSkewRatio + ratioSquared);

        return skewPriceRatio.toInt().mulDecimal(sqrt) - self.skewScale.toInt() - initialSkew;
    }
}
