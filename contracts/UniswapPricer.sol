// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.6.10 < 0.9.0;

import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

contract UniswapPricer is OpynPricerInterface {
    using SafeMath for uint256;

    function getPrice() external override view returns(uint256) {

    }
}