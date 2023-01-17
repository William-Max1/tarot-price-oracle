pragma solidity =0.5.16;

import "./libraries/UQ112x112.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/ITarotPriceOracle.sol";

contract TarotPriceOracle is ITarotPriceOracle {
    using UQ112x112 for uint224;

    uint32 public constant MIN_T = 10;

    struct Pair {
        uint256 reserve0CumulativeSlotA;
        uint256 reserve1CumulativeSlotA;
        uint256 reserve0CumulativeSlotB;
        uint256 reserve1CumulativeSlotB;
        uint32 lastUpdateSlotA;
        uint32 lastUpdateSlotB;
        bool latestIsSlotA;
        bool initialized;
    }
    mapping(address => Pair) public getPair;

    event PriceUpdate(
        address indexed pair,
        uint256 reserve0Cumulative,
        uint256 reserve1Cumulative,
        uint32 blockTimestamp,
        bool latestIsSlotA
    );

    function toUint224(uint256 input) internal pure returns (uint224) {
        require(input <= uint224(-1), "TarotPriceOracle: UINT224_OVERFLOW");
        return uint224(input);
    }

    function getReservesCumulativeCurrent(address uniswapV2Pair)
        internal
        view
        returns (uint256 r0, uint256 r1, uint256 t)
    {
        (r0, r1, t) = IUniswapV2Pair(uniswapV2Pair).currentCumulativePrices();
    }

    function initialize(address uniswapV2Pair) external {
        Pair storage pairStorage = getPair[uniswapV2Pair];
        require(
            !pairStorage.initialized,
            "TarotPriceOracle: ALREADY_INITIALIZED"
        );

        (uint256 r0, uint256 r1, uint256 blockTimestamp) =
            getReservesCumulativeCurrent(uniswapV2Pair);
        uint32 _blockTimestamp = uint32(blockTimestamp % 2**32);
        pairStorage.reserve0CumulativeSlotA = r0;
        pairStorage.reserve1CumulativeSlotA = r1;
        pairStorage.lastUpdateSlotA = _blockTimestamp;
        pairStorage.lastUpdateSlotB = _blockTimestamp;
        pairStorage.latestIsSlotA = true;
        pairStorage.initialized = true;
        emit PriceUpdate(
            uniswapV2Pair,
            r0,
            r1,
            _blockTimestamp,
            true
        );
    }

    function getResult(address uniswapV2Pair)
        external
        returns (uint224 price, uint32 T)
    {
        Pair memory pair = getPair[uniswapV2Pair];
        require(pair.initialized, "TarotPriceOracle: NOT_INITIALIZED");
        Pair storage pairStorage = getPair[uniswapV2Pair];

        uint32 blockTimestamp = getBlockTimestamp();
        uint32 lastUpdateTimestamp =
            pair.latestIsSlotA ? pair.lastUpdateSlotA : pair.lastUpdateSlotB;
        (uint256 r0CumulativeCurrent, uint256 r1CumulativeCurrent, ) =
            getReservesCumulativeCurrent(uniswapV2Pair);

        uint256 r0CumulativeLast = pair.reserve0CumulativeSlotA;
        uint256 r1CumulativeLast = pair.reserve1CumulativeSlotA;

        if (blockTimestamp - lastUpdateTimestamp >= MIN_T) {
            // update price
            if (pair.latestIsSlotA) {
                r0CumulativeLast = pair.reserve0CumulativeSlotA;
                r1CumulativeLast = pair.reserve1CumulativeSlotA;
                pairStorage.reserve0CumulativeSlotB = r0CumulativeCurrent;
                pairStorage.reserve1CumulativeSlotB = r1CumulativeCurrent;
                pairStorage.lastUpdateSlotB = blockTimestamp;
            } else {
                r0CumulativeLast = pair.reserve0CumulativeSlotB;
                r1CumulativeLast = pair.reserve1CumulativeSlotB;
                pairStorage.reserve0CumulativeSlotA = r0CumulativeCurrent;
                pairStorage.reserve1CumulativeSlotA = r1CumulativeCurrent;
                pairStorage.lastUpdateSlotA = blockTimestamp;
            }
            pairStorage.latestIsSlotA = !pair.latestIsSlotA;
            emit PriceUpdate(
                uniswapV2Pair,
                r0CumulativeLast,
                r1CumulativeLast,
                blockTimestamp,
                !pair.latestIsSlotA
            );
        } else {
            // don't update; return price using previous priceCumulative
            lastUpdateTimestamp = pair.latestIsSlotA
                ? pair.lastUpdateSlotB
                : pair.lastUpdateSlotA;
            r0CumulativeLast = pair.latestIsSlotA
                ? pair.reserve0CumulativeSlotB
                : pair.reserve0CumulativeSlotA;
            r1CumulativeLast = pair.latestIsSlotA
                ? pair.reserve1CumulativeSlotB
                : pair.reserve1CumulativeSlotA;
        }

        T = blockTimestamp - lastUpdateTimestamp; // overflow is desired
        require(T >= MIN_T, "TarotPriceOracle: NOT_READY"); //reverts only if the pair has just been initialized
        // / is safe, and - overflow is desired
        require(r0CumulativeCurrent > r0CumulativeLast);
        require(r1CumulativeCurrent > r1CumulativeLast);
        uint256 r0Calculate = r0CumulativeCurrent - r0CumulativeLast;
        uint256 r1Calculate = r1CumulativeCurrent - r1CumulativeLast;
        require(r0Calculate < 2**112, "TarotPriceOracle: U112 Overflow");
        require(r1Calculate < 2**112, "TarotPriceOracle: U112 Overflow");
        uint112 _r0 = uint112(r0Calculate);
        uint112 _r1 = uint112(r1Calculate);
        price = UQ112x112.encode(_r1).uqdiv(_r0);
    }

    /*** Utilities ***/
    function getBlockTimestamp() public view returns (uint32) {
        return uint32(block.timestamp % 2**32);
    }
}
