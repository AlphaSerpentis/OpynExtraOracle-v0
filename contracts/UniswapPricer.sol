// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

import {OracleInterface} from "./opyn/interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract UniswapPricer is OpynPricerInterface {
    error ZeroAddress();

    OracleInterface public oracle;

    IERC20 public underlying;

    constructor(
        address _underlying,
        address _oracle
    ) {
        if(_underlying == address(0) || _oracle == address(0)) {
            revert ZeroAddress();
        }

        underlying = IERC20(_underlying);
        oracle = OracleInterface(_oracle);
    }

    function getPrice() external override view returns(uint256) {

    }
}