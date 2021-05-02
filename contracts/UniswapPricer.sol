// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {OracleInterface} from "./opyn/interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";
import {IUniswapV2Pair} from "./uniswap/interfaces/IUniswapV2Pair.sol";

contract UniswapPricer is OpynPricerInterface {
    error ZeroAddress();
    error PreparingPrice();
    error TooEarly();
    error Unauthorized();

    /// @notice length of the period
    uint256 public period;
    /// @notice the time of last call
    uint256 public lastCall;
    /// @notice the average price of the last prepared call
    uint256 private averagedPrice;
    /// @notice status if the price is being computed
    bool public preparing;
    /// @notice immutable address of the bot
    address public immutable bot;
    /// @notice immutable OracleInterface for the oracle
    OracleInterface public immutable oracle;
    /// @notice immutable address of the uniswapv2pair
    IUniswapV2Pair public immutable uniswapv2pair;

    constructor(
        address _uniswapv2pair,
        address _oracle,
        address _bot,
        uint256 _period
    ) {
        if(_uniswapv2pair == address(0) ||  _oracle == address(0) || _bot == address(0)) {
            revert ZeroAddress();
        }

        uniswapv2pair = IUniswapV2Pair(_uniswapv2pair);
        oracle = OracleInterface(_oracle);
        bot = _bot;
        period = _period;
    }

    modifier onlyBot {
        _onlyBot();
        _;
    }

    /**
     * @notice get the last computed price for the asset
     * @dev overrides the getPrice function in OpynPricerInterface; reverts if preparing is true
     * @return price of the asset
     */
    function getPrice() external override view returns(uint256) {
        if(preparing)
            revert PreparingPrice(); // Reverts as the averagedPrice is not properly set

        return averagedPrice;
    }
    /**
     * @notice prepare the price for the asset
     * @dev Begin computation of the price (if not already preparing), otherwise finalize the results
     */
    function preparePrice() external onlyBot {
        if(preparing) {
            if(block.timestamp < lastCall + period)
                revert TooEarly();

            lastCall = block.timestamp;

            averagedPrice = (averagedPrice + uniswapv2pair.price0CumulativeLast()) / (block.timestamp - lastCall);

            preparing = false;
        } else {
            preparing = true;

            averagedPrice = uniswapv2pair.price0CumulativeLast();

            lastCall = block.timestamp;
        }
    }

    function _onlyBot() internal view {
        if(msg.sender != bot)
            revert Unauthorized();
    }
}