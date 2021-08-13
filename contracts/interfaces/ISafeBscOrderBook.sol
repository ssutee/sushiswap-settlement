// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;


import "../libraries/SafeBscOrders.sol";
pragma experimental ABIEncoderV2;

interface ISafeBscOrderBook {
    function orderOfHash(bytes32) external returns (SafeBscOrders.Order memory);
}