//SPDX-License-Identifier: MIT
pragma solidity >=0.8.11 <0.9.0;

import {UUPSProxyWithOwner} from "@alchemyio/core-contracts/contracts/proxy/UUPSProxyWithOwner.sol";
import {OwnableStorage} from "@alchemyio/core-contracts/contracts/ownership/OwnableStorage.sol";

/**
 * Alchemy Oracle Manager Proxy Contract
 *
 * Visit https://usecannon.com/packages/oracle-manager to interact with this protocol
 */
contract Proxy is UUPSProxyWithOwner {
    // solhint-disable-next-line no-empty-blocks
    constructor(
        address firstImplementation,
        address initialOwner
    ) UUPSProxyWithOwner(firstImplementation, initialOwner) {}
}
