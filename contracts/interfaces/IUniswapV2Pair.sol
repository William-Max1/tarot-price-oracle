pragma solidity =0.5.16;

interface IUniswapV2Pair {
    function reserve0CumulativeLast() external view returns (uint256);
    function reserve1CumulativeLast() external view returns (uint256);
    function currentCumulativePrices() external view returns (uint256, uint256, uint256);
}
