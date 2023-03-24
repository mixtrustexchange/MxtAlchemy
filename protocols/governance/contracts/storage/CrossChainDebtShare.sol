//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@alchemyio/core-contracts/contracts/utils/SetUtil.sol";
import "../interfaces/IDebtShare.sol";

library CrossChainDebtShare {
    struct Data {
        // Alchemy v2 cross chain debt share merkle root
        bytes32 merkleRoot;
        // Cross chain debt share merkle root snapshot blocknumber
        uint merkleRootBlockNumber;
        // Cross chain debt shares declared on this chain
        mapping(address => uint) debtShares;
    }
}
