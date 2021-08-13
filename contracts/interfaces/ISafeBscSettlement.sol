// SPDX-License-Identifier: MIT

pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "../libraries/SafeBscOrders.sol";

interface ISafeBscSettlement {
    event OrderFilled(bytes32 indexed hash, uint256 amountIn, uint256 amountOut);
    event OrderCanceled(bytes32 indexed hash);
    event FeeTransferred(bytes32 indexed hash, address indexed recipient, uint256 amount);
    event FeeSplitTransferred(bytes32 indexed hash, address indexed recipient, uint256 amount);

    struct FillOrderArgs {
        SafeBscOrders.Order order;
        uint256 amountToFillIn;
        address[] path;
        address router;
    }

    function fillOrder(FillOrderArgs calldata args) external returns (uint256 amountOut);

    function cancelOrder(bytes32 hash) external;
}
