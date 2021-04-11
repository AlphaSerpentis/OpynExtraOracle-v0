// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;

import {OracleInterface} from "./opyn/interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

/// @title Multi Pricer
/// @author Amethyst C.
/// @notice Multi Pricer pulls data from more than one source and uses a weighted average to calculate the expiration price
/// @dev Pulls data from an oracle utilizing the OpynPricerInterface
contract MultiPricer {
    using SafeMath for uint256;
    using SafeMath for uint16;

    /// @dev Struct that stores price of an asset and timestamp of when it was recorded
    /// Adapted from GammaProtocol/contracts/Oracle.sol
    struct Price {
        uint256 price;
        uint256 timestamp;
        address source; // Source of the price data
    }
    /// @dev Struct that stores info for the Pricer
    /// Weight can be used to determine the "trust" level
    struct Pricer {
        address source;
        uint16 weight;
        uint8 decimalsOfPrecision;
    }

    /// @dev Permissioned addresses to pull price data from
    /// (key = asset) -> (value = pricers)
    mapping(address => Pricer[]) internal pricers;
    /// @dev Permissioned addresses to allow to call functions
    mapping(address => bool) internal bots;
    /// @dev Tolerable weight deviation
    uint16 private tolerableWeightDeviation;
    /// @dev Opyn v2's oracle to submit price data to
    OracleInterface public opynOracle;
    /// @dev The admin can represent any multi-sig wallet capable of producing calls to the contract
    address private admin;

    event PricerAdded(address asset, address pricer, uint16 trust);
    event PricerRemoved(address asset, address pricer);
    event BotAdded(address bot);
    event BotRemoved(address bot);
    event PushedData(address asset, uint256 price);
    event AdminChanged(address newAdmin);

    constructor(
        address _admin,
        address _opynOracle
    ) public {
        admin = _admin; // Make sure admin is a multi-sig wallet!
        opynOracle = OracleInterface(_opynOracle);
    }

    modifier onlyBot {
        _onlyBot();
        _;
    }
    modifier onlyAdmin {
        _onlyAdmin();
        _;
    }

    /** 
    * @notice Add a pricer
    * @param _asset asset's address
    * @param _pricer pricer's address
    */
    function addPricer(
        address _asset,
        address _pricer,
        uint16 _weight
    )
        external
        onlyAdmin 
    {
        Pricer memory newPricer;
        newPricer.source = _pricer;
        newPricer.weight = _weight;

        pricers[_asset].push(newPricer);
        emit PricerAdded(_asset, _pricer, _weight);
    }
    /**
    * @notice Remove a pricer
    * @param _asset asset's address
    * @param _pricer pricer's address
    */
    function removePricer(
        address _asset,
        address _pricer
    )
        external
        onlyAdmin
    {
        delete pricers[_asset];
        emit PricerRemoved(_asset, _pricer);
    }
    /**
    * @notice Adds a bot
    * @param _bot bot's address
    */
    function addBot(address _bot) external onlyAdmin {
        bots[_bot] = true;
        emit BotAdded(_bot);
    }
    /**
    * @notice Removes a bot
    * @param _bot bot's address
    */
    function removeBot(address _bot) external onlyAdmin {
        bots[_bot] = false;
        emit BotRemoved(_bot);
    }
    /**
    * @notice Change the Opyn oracle's address
    * @param _newOracle new oracle's address for Opyn v2
    */
    function changeOpynOracle(address _newOracle) external onlyAdmin {
        require(_newOracle != address(0), "MultiPricer: Zero address");
        opynOracle = OracleInterface(_newOracle);
    }
    /**
    * @notice Change the contract's admin
    * @param _newAdmin new admin's address
    */
    function changeAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "MultiPricer: Zero address");
        admin = _newAdmin;
    }
    function pushData(address _asset) external onlyBot {
        
        

    }
    function _onlyBot() internal view {
        require(bots[msg.sender], "MultiPricer: Unauthorized (bot)");
    }
    function _onlyAdmin() internal view {
        require(msg.sender == admin, "MultiPricer: Unauthorized");
    }
    function _calculateWeightedAverage(
        address _asset
    )
        internal
        returns(uint256 weightedPrice)
    {
        // Check if there is even a pricer available
        

        // Check if the pricer was called recently, otherwise remove it from the calculation
        
        // Multiply the weights appropriately
    }
    function _reweighPricer(
        Pricer[] storage _pricersToReweigh
    )
        internal
        returns(Pricer[] memory pricers)
    {

    }
    /**
    * @notice Verify the weights did not deviate too far or is out of bounds
    * @param _totalWeightValues total value of the weight 
    */
    function _weightDeviationToleranceCheck(
        uint16 _totalWeightValues
    )
        internal
        view
    {
        require(10000 - _totalWeightValues <= tolerableWeightDeviation, "MultiPricer: Intolerable weight deviation");
        require(_totalWeightValues <= 10000, "MultiPricer: Illegal total weight value");
    }
}