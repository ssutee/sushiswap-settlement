// SPDX-License-Identifier: MIT

pragma solidity =0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@sushiswap/core/contracts/uniswapv2/interfaces/IERC20.sol";
import "./libraries/SafeBscOrders.sol";
import "./libraries/EIP712.sol";
import "./libraries/Bytes32Pagination.sol";

import "hardhat/console.sol";

contract SafeBscOrderBook is Ownable {
    using SafeBscOrders for SafeBscOrders.Order;
    using Bytes32Pagination for bytes32[];

    event OrderCreated(bytes32 indexed hash);

    // solhint-disable-next-line var-name-mixedcase
    bytes32 public immutable DOMAIN_SEPARATOR;

    // Array of hashes of all orders
    bytes32[] internal _allHashes;
    // Address of order maker => hashes (orders)
    mapping(address => bytes32[]) internal _hashesOfMaker;
    // Address of fromToken => hashes (orders)
    mapping(address => bytes32[]) internal _hashesOfFromToken;
    // Address of toToken => hashes (orders)
    mapping(address => bytes32[]) internal _hashesOfToToken;
    // Hash of an order => the order and its data
    mapping(bytes32 => SafeBscOrders.Order) public orderOfHash;

    // fee amount in Native Token for Bot
    uint256 public feeAmount;

    address payable public settlementAddress;

    constructor(uint256 _feeAmount) public {
        uint256 chainId;
        assembly {
            chainId := chainid()
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("SafeBscOrderBook"),
                keccak256("1"),
                chainId,
                address(this)
            )
        );
        feeAmount = _feeAmount;
    }

    // Returns the number of orders of a maker
    function numberOfHashesOfMaker(address maker) public view returns (uint256) {
        return _hashesOfMaker[maker].length;
    }

    // Return the number of orders where fromToken is the origin token
    function numberOfHashesOfFromToken(address fromToken) public view returns (uint256) {
        return _hashesOfFromToken[fromToken].length;
    }

    // Return the number of orders where toToken is the target token
    function numberOfHashesOfToToken(address toToken) public view returns (uint256) {
        return _hashesOfToToken[toToken].length;
    }

    // Returns the number of all orders
    function numberOfAllHashes() public view returns (uint256) {
        return _allHashes.length;
    }

    // Returns an array of hashes of orders of a maker
    function hashesOfMaker(
        address maker,
        uint256 page,
        uint256 limit
    ) public view returns (bytes32[] memory) {
        return _hashesOfMaker[maker].paginate(page, limit);
    }

    // Returns an array of hashes of orders where fromToken is the origin token
    function hashesOfFromToken(
        address fromToken,
        uint256 page,
        uint256 limit
    ) public view returns (bytes32[] memory) {
        return _hashesOfFromToken[fromToken].paginate(page, limit);
    }

    // Returns an array of hashes of orders where toToken is the target token
    function hashesOfToToken(
        address toToken,
        uint256 page,
        uint256 limit
    ) public view returns (bytes32[] memory) {
        return _hashesOfToToken[toToken].paginate(page, limit);
    }

    // Return an array of all hashes
    function allHashes(uint256 page, uint256 limit) public view returns (bytes32[] memory) {
        return _allHashes.paginate(page, limit);
    }

    // Creates an order
    function createOrder(SafeBscOrders.Order memory order) public payable {
        require(order.fee == feeAmount, "invalid-fee-amount");
        require(msg.value >= feeAmount, "not-enough-fee");
        order.fee = feeAmount;
        order.validate();

        bytes32 hash = order.hash();

        address signer = EIP712.recover(DOMAIN_SEPARATOR, hash, order.v, order.r, order.s);

        require(signer != address(0) && signer == order.maker, "invalid-signature");

        require(orderOfHash[hash].maker == address(0), "order-exists");
        orderOfHash[hash] = order;

        _allHashes.push(hash);
        _hashesOfMaker[order.maker].push(hash);
        _hashesOfFromToken[order.fromToken].push(hash);
        _hashesOfToToken[order.toToken].push(hash);

        if (settlementAddress != address(0)) {
            settlementAddress.transfer(msg.value);
        }

        emit OrderCreated(hash);
    }

    function setFeeAmount(uint256 _feeAmount) external onlyOwner {
        require(_feeAmount != feeAmount, "same-value");
        feeAmount = _feeAmount;
    }

    function setSettlementAddress(address payable _settlementAddress) external onlyOwner {
        require(_settlementAddress != address(0), "invalid-address");
        require(_settlementAddress != settlementAddress, "same-value");
        settlementAddress = _settlementAddress;
    }
}
