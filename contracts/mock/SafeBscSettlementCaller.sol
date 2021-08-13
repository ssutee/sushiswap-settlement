// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "../interfaces/ISafeBscSettlement.sol";

contract SafeBscSettlementCaller {
    ISafeBscSettlement settlement;

    constructor(ISafeBscSettlement _settlement) public {
        settlement = _settlement;
    }

    function fillOrder(ISafeBscSettlement.FillOrderArgs calldata args) external returns (uint256 amountOut) {
        return settlement.fillOrder(args);
    }
}
