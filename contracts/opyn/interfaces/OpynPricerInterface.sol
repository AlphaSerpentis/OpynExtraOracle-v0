// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.3;

interface OpynPricerInterface {
    function getPrice() external view returns (uint256);
}