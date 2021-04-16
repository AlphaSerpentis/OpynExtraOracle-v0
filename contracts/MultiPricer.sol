// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import {OracleInterface} from "./opyn/interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";

/// @title Multi Pricer
/// @author Amethyst C.
/// @notice Multi Pricer pulls data from more than one source and uses a weighted average to calculate the expiration price
/// @dev Pulls data from an oracle utilizing the OpynPricerInterface
contract MultiPricer {

    /// @dev Struct that stores price of an asset and timestamp of when it was recorded
    /// Adapted from GammaProtocol/contracts/Oracle.sol
    struct Price {
        uint256 price;
        uint256 timestamp;
        Pricer source; // Source of the price data
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
    /// @dev Pricer to price data
    mapping(address => Price) internal prices;
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
    function prepareData(address _asset) external onlyBot {

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
        uint256 totalPricers = pricers[_asset].length;

        // Check if there is even a pricer available
        require(totalPricers > 0, "MultiPricer: Pricers do not exist!");

        // Continue preparing variables
        uint16 totalWeight;
        bool missingPricer;
        Pricer[] memory assetPricers = pricers[_asset];
        Price[] memory assetPrices = new Price[](totalPricers);

        // Check if the pricer was called recently, otherwise remove it from the calculation
        for(uint256 i; i < assetPricers.length; i++) {
            if(prices[assetPricers[i].source].timestamp >= block.timestamp - 15 minutes) {
                missingPricer = true;
                continue;
            } else if(prices[assetPricers[i].source].timestamp != 0) {
                assetPrices[assetPrices.length] = (prices[assetPricers[i].source]);
                totalWeight.add(assetPricers[i].weight);
            } 
        }

        // Verify weights 
        if(!_weightDeviationToleranceCheck(totalWeight)) {
            if(missingPricer)
                assetPricers = _reweighPricer(assetPricers, 0);
            else
                assetPricers = _reweighPricer(assetPricers, 1);
        }

        // Multiply to get the weighted average
        for(uint256 i; i < assetPrices.length; i++) {
            if(assetPrices[i].price != 0) {
                weightedPrice.add(assetPrices[i].price.mul(assetPrices[i].source.weight));
            }
        }

    }
    function _reweighPricer(
        Pricer[] memory _pricersToReweigh,
        uint256 _type
    )
        internal
        pure
        returns(Pricer[] memory)
    {
        if(_type == 0) { // Reweigh due to missing pricer
            uint16 currentWeightVal;
            uint256 indexCount;
            uint16[] memory indexOfValidPricers = new uint16[](_pricersToReweigh.length);

            for(uint256 i; i < _pricersToReweigh.length; i++) {
                if(_pricersToReweigh[i].source != address(0)) {
                    indexOfValidPricers[indexCount++] = uint16(i);
                    currentWeightVal.add(_pricersToReweigh[i].weight);
                }
            }

            for(uint16 i; i < indexOfValidPricers.length; i++) {
                _pricersToReweigh[i].weight = uint16(_pricersToReweigh[i].weight.div(currentWeightVal));
            }
        } else if(_type == 1) { // Reweigh to equalize
            for(uint256 i; i < _pricersToReweigh.length; i++) {
                _pricersToReweigh[i].weight = uint16(_pricersToReweigh[i].weight.div(_pricersToReweigh.length));
            }
        }

        return _pricersToReweigh;
    }
    /**
    * @notice Verify the weights did not deviate too far or is out of bounds
    * @param _totalWeightValues total value of the weight
    * @return true if the weight values didn't exceed the tolerance
    */
    function _weightDeviationToleranceCheck(
        uint16 _totalWeightValues
    )
        internal
        view
        returns(bool)
    {
        require(_totalWeightValues <= 10000, "MultiPricer: Out of bounds - manual intervention required!");
        return (10000 - _totalWeightValues <= tolerableWeightDeviation) && (_totalWeightValues <= 10000);
    }
}