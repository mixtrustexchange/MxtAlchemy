//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {UUPSProxyWithOwner} from "@alchemyio/core-contracts/contracts/proxy/UUPSProxyWithOwner.sol";

/**
 * Alchemy V3 Perps Factory -- Proxy Contract
 *
 * Visit https://usecannon.com/packages/alchemy-perps-market to interact with this protocol
 */
contract Proxy is UUPSProxyWithOwner {
    // solhint-disable-next-line no-empty-blocks
    constructor(
        address firstImplementation,
        address initialOwner
    ) UUPSProxyWithOwner(firstImplementation, initialOwner) {}
}
