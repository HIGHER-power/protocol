pragma solidity >=0.5.0;

import "../libraries/Arithemtic.sol";
import "../integrations/IUniswapV2Pair.sol";

// library with helper methods for oracles that are concerned with computing average prices
library UniswapV2OracleLibrary {
    using Arithmetic for uint256;

    // helper function that returns the current block timestamp within the range of uint32, i.e. [0, 2**32 - 1]
    function currentBlockTimestamp() internal view returns (uint32) {
        return uint32(block.timestamp % 2 ** 32);
    }

    // produces the cumulative price using counterfactuals to save gas and avoid a call to sync.
    function currentCumulativePrices(
        address pair
    )
        internal
        view
        returns (
            uint price0Cumulative,
            uint price1Cumulative,
            uint32 blockTimestamp
        )
    {
        blockTimestamp = currentBlockTimestamp();
        price0Cumulative = _rescaleUQ112(
            IUniswapV2Pair(pair).price0CumulativeLast()
        );
        price1Cumulative = _rescaleUQ112(
            IUniswapV2Pair(pair).price1CumulativeLast()
        );

        // if time has elapsed since the last update on the pair, mock the accumulated price values
        (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        ) = IUniswapV2Pair(pair).getReserves();
        if (
            blockTimestampLast != blockTimestamp && reserve0 > 0 && reserve1 > 0
        ) {
            uint32 timeElapsed = blockTimestamp - blockTimestampLast;
            price0Cumulative +=
                uint256(reserve1).div(uint256(reserve0)) *
                timeElapsed;
            price1Cumulative +=
                uint256(reserve0).div(uint256(reserve1)) *
                timeElapsed;
        }
    }

    function _rescaleUQ112(uint256 value) internal pure returns (uint256) {
        return (value * 10 ** 18) / 2 ** 112;
    }
}
