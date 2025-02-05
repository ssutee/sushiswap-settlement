// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@sushiswap/core/contracts/uniswapv2/libraries/SafeMath.sol";
import "@sushiswap/core/contracts/uniswapv2/libraries/TransferHelper.sol";
import "@sushiswap/core/contracts/uniswapv2/libraries/UniswapV2Library.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IERC20.sol";
import "./interfaces/ISafeBscSettlement.sol";
import "./interfaces/ISafeBscOrderBook.sol";
import "./interfaces/ISafeBscRouter.sol";
import "./libraries/SafeBscOrders.sol";
import "./libraries/EIP712.sol";

contract SafeBscSettlement is ISafeBscSettlement, ReentrancyGuard, Ownable {
    using SafeMathUniswap for uint256;
    using SafeBscOrders for SafeBscOrders.Order;

    // solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Hash of an order => if canceled
    mapping(address => mapping(bytes32 => bool)) public canceledOfHash;
    // Hash of an order => filledAmountIn
    mapping(bytes32 => uint256) public filledAmountInOfHash;

    address public immutable factory;
    
    address public orderBookAddress;

    address public safeBscRouter;

    constructor(
        uint256 orderBookChainId,
        address _orderBookAddress,
        address _factory,
        address _safeBscRouter
    ) public {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SafeBscOrderBook"),
                keccak256("1"),
                orderBookChainId,
                _orderBookAddress
            )
        );
        factory = _factory;
        orderBookAddress = _orderBookAddress;
        safeBscRouter = _safeBscRouter;
    }

    fallback() external payable {}

    receive() external payable {}

    // Fills an order
    function fillOrder(FillOrderArgs memory args) 
        public override nonReentrant returns (uint256 amountOut) {
        // voids flashloan attack vectors
        // solhint-disable-next-line avoid-tx-origin
        require(msg.sender == tx.origin, "called-by-contract");

        // Check if the order is canceled / already fully filled
        bytes32 hash = args.order.hash();
        _validateStatus(args, hash);

        // Check if the signature is valid
        address signer = EIP712.recover(DOMAIN_SEPARATOR, hash, args.order.v, args.order.r, args.order.s);
        require(signer != address(0) && signer == args.order.maker, "invalid-signature");

        // Calculates amountOutMin
        uint256 amountOutMin = (args.order.amountOutMin.mul(args.amountToFillIn) / args.order.amountIn);

        // Calculates fee amount
        uint256 feeAmount = args.order.fee;
        if (args.amountToFillIn < args.order.amountIn) {
            feeAmount = (args.order.fee.mul(args.amountToFillIn) / args.order.amountIn);
        }

        IERC20Uniswap(args.order.fromToken).transferFrom(
            args.order.maker, 
            address(this), 
            args.amountToFillIn
        );

        IERC20Uniswap(args.order.fromToken).approve(
            safeBscRouter, 
            args.amountToFillIn
        );

        uint256[] memory amounts = ISafeBscRouter(
            safeBscRouter
        ).swapExactTokensForTokens(            
            args.router, 
            args.amountToFillIn, 
            amountOutMin, 
            args.path, 
            args.order.recipient, 
            now.add(60)
        );
        amountOut = amounts[amounts.length - 1];


        // This line is free from reentrancy issues since UniswapV2Pair prevents from them
        filledAmountInOfHash[hash] = filledAmountInOfHash[hash].add(args.amountToFillIn);

        if (feeAmount > 0) {
            msg.sender.transfer(feeAmount);
            emit FeeTransferred(hash, msg.sender, feeAmount);
        }
        

        emit OrderFilled(hash, args.amountToFillIn, amountOut);
    }

    // Checks if an order is canceled / already fully filled
    function _validateStatus(FillOrderArgs memory args, bytes32 hash) internal view {
        require(args.order.deadline >= block.timestamp, "order-expired");
        require(!canceledOfHash[args.order.maker][hash], "order-canceled");
        require(filledAmountInOfHash[hash].add(args.amountToFillIn) <= args.order.amountIn, "already-filled");
    }

    // Swaps an exact amount of tokens for another token through the path passed as an argument
    // Returns the amount of the final token
    function _swapExactTokensForTokens(
        address from,
        uint256 amountIn,
        uint256 amountOutMin,
        address[] memory path,
        address to
    ) internal returns (uint256 amountOut) {
        uint256[] memory amounts = UniswapV2Library.getAmountsOut(factory, amountIn, path);
        amountOut = amounts[amounts.length - 1];
        require(amountOut >= amountOutMin, "insufficient-amount-out");
        TransferHelper.safeTransferFrom(path[0], from, UniswapV2Library.pairFor(factory, path[0], path[1]), amountIn);
        _swap(amounts, path, to);
    }

    // requires the initial amount to have already been sent to the first pair
    function _swap(
        uint256[] memory amounts,
        address[] memory path,
        address _to
    ) internal virtual {
        for (uint256 i; i < path.length - 1; i++) {
            (address input, address output) = (path[i], path[i + 1]);
            (address token0, ) = UniswapV2Library.sortTokens(input, output);
            uint256 amountOut = amounts[i + 1];
            (uint256 amount0Out, uint256 amount1Out) = input == token0
                ? (uint256(0), amountOut)
                : (amountOut, uint256(0));
            address to = i < path.length - 2 ? UniswapV2Library.pairFor(factory, output, path[i + 2]) : _to;
            IUniswapV2Pair(UniswapV2Library.pairFor(factory, input, output)).swap(
                amount0Out,
                amount1Out,
                to,
                new bytes(0)
            );
        }
    }

    // Cancels an order, has to been called by order maker
    function cancelOrder(bytes32 hash) public override {
        require(!canceledOfHash[msg.sender][hash], "already-cancelled");
        
        canceledOfHash[msg.sender][hash] = true;

        SafeBscOrders.Order memory order = ISafeBscOrderBook(orderBookAddress).orderOfHash(hash);
        
        // refund fee
        if (order.fee > 0) {
            uint256 feeAmountDiscount = (order.fee.mul(filledAmountInOfHash[hash]) / order.amountIn);
            uint256 feeAmount = order.fee.sub(feeAmountDiscount);
            msg.sender.transfer(feeAmount);
            emit FeeTransferred(hash, msg.sender, feeAmount);
        }

        emit OrderCanceled(hash);
    }

    function setSafeBscRouter(address _safeBscRouter) external onlyOwner {
        require(_safeBscRouter != address(0),"invalid-address");
        require(_safeBscRouter != safeBscRouter, "same-value");
        _safeBscRouter = safeBscRouter;
    }
}
