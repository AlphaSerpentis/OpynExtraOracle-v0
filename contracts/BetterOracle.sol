// SPDX-License-Identifier: MIT
pragma solidity 0.8.4;

import {OracleInterface} from "./opyn/interfaces/OracleInterface.sol";
import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";

/// @title Better Oracle
/// @author Amethyst C.
/// @notice Better Oracle pulls data from more than one source and uses a weighted average to calculate the expiration price
/// @dev Pulls data from pricers utilizing the OpynPricerInterface
contract BetterOracle {
    error ZeroAddress();
    error Unauthorized_Bot();
    error Unauthorized_Admin();
    error PricerDoesNotExist();
    error WeightOutOfBounds();

    /// @dev Struct that stores info for the Pricer
    /// Weight can be used to determine the "trust" level
    struct Pricer {
        address source;
        uint16 weight;
        uint8 decimalsOfPrecision;
    }
    /// @dev Struct that stores price of an asset and timestamp of when it was recorded
    /// Adapted from GammaProtocol/contracts/Oracle.sol
    struct Price {
        uint256 price;
        uint256 timestamp;
        Pricer source; // Source of the price data
    }
    /// @dev Permissioned addresses to pull price data from
    /// (key = asset) -> (value = pricers)
    mapping(address => Pricer[]) internal pricers;
    /// @dev Pricer to price data
    mapping(address => Price) internal prices;
    /// @dev Permissioned addresses to allow to call functions
    mapping(address => bool) internal bots;
    /// @dev Tolerable price deviation from the mean in % (measured w/ 2 decimals [100.xx])
    uint16 private tolerablePriceDeviation;
    /// @dev Tolerable weight deviation in % (measured w/ 2 decimals [100.xx])
    uint16 private tolerableWeightDeviation;
    /// @dev Opyn v2's oracle to submit price data to
    OracleInterface private opynOracle;
    /// @dev The admin can represent any multi-sig wallet capable of producing calls to the contract
    address private admin;

    event PricerAdded(address asset, address pricer, uint16 trust);
    event PricerRemoved(address asset, address pricer);
    event BotAdded(address bot);
    event BotRemoved(address bot);
    event PushedData(address asset, uint256 price);
    event AdminChanged(address newAdmin);

    constructor(address _admin, address _opynOracle, uint16 _tolerablePriceDeviation, uint16 _tolerableWeightDeviation) {
        admin = _admin; // Make sure admin is a multi-sig wallet!
        opynOracle = OracleInterface(_opynOracle);
        tolerablePriceDeviation = _tolerablePriceDeviation;
        tolerableWeightDeviation = _tolerableWeightDeviation;
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
    ) external onlyAdmin {
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
    function removePricer(address _asset, address _pricer) external onlyAdmin {
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
        if(_newOracle == address(0))
            revert ZeroAddress();
        opynOracle = OracleInterface(_newOracle);
    }

    /**
     * @notice Change the contract's admin
     * @param _newAdmin new admin's address
     */
    function changeAdmin(address _newAdmin) external onlyAdmin {
        if(_newAdmin == address(0))
            revert ZeroAddress();
        admin = _newAdmin;
    }

    /** (??????)
     * @notice Prepare the pricer data for the asset
     * @param _asset is the asset's address
     */
    function prepareData(address _asset) external onlyBot {
        Pricer[] storage assetPricers = pricers[_asset];

        if(assetPricers.length == 0)
            revert PricerDoesNotExist();
    }

    function pushData(address _asset, uint256 _expiryTimestamp, bool _ignoreOutOfBounds) external onlyBot {
        if(pricers[_asset].length == 0)
            revert PricerDoesNotExist();
        uint256 _weightedPrice = _calculateWeightedAverage(_asset, _ignoreOutOfBounds);

        opynOracle.setExpiryPrice(_asset, _expiryTimestamp, _weightedPrice);

        emit PushedData(_asset, _weightedPrice);
    }

    function _onlyBot() internal view {
        if(!bots[msg.sender])
            revert Unauthorized_Bot();
    }

    function _onlyAdmin() internal view {
        if(msg.sender != admin)
            revert Unauthorized_Admin();
    }

    function _calculateWeightedAverage(address _asset, bool _ignoreOutOfBounds)
        internal
        view
        returns (uint256 weightedPrice)
    {
        uint256 totalPricers = pricers[_asset].length;

        // Check if there is even a pricer available
        if(totalPricers == 0)
            revert PricerDoesNotExist();

        // Continue preparing variables
        uint256 maxDecimalsOfPrecision;
        uint16 totalWeight;
        bool missingPricer;
        Pricer[] memory assetPricers = pricers[_asset];
        Price[] memory assetPrices = new Price[](totalPricers);

        // Check if the pricer was called recently, otherwise remove it from the calculation
        for (uint256 i; i < assetPricers.length; i++) {
            if (
                prices[assetPricers[i].source].timestamp <=
                block.timestamp - 15 minutes &&
                !missingPricer
            ) {
                missingPricer = true;
                continue;
            } else if (prices[assetPricers[i].source].timestamp != 0) {
                assetPrices[i] = prices[assetPricers[i].source];
                totalWeight += assetPricers[i].weight;
                if(assetPricers[i].decimalsOfPrecision > maxDecimalsOfPrecision)
                    maxDecimalsOfPrecision = assetPricers[i].decimalsOfPrecision;
            }
        }

        // Verify weights
        (bool _tolerated, bool _outOfBounds) = _weightDeviationToleranceCheck(totalWeight);

        if(_outOfBounds && !_ignoreOutOfBounds)
            revert WeightOutOfBounds();

        if (_tolerated) {
            if (missingPricer)
                assetPricers = _reweighPricer(assetPricers, 0);
            else
                assetPricers = _reweighPricer(assetPricers, 1);
        }

        // Multiply to get the weighted average
        for (uint256 i; i < assetPrices.length; i++) {
            if (assetPrices[i].price != 0) {
                weightedPrice +=
                    _normalize(assetPrices[i].price, assetPrices[i].source.decimalsOfPrecision, maxDecimalsOfPrecision) *
                    assetPrices[i].source.weight / 10000;
            }
        }
    }

    function _reweighPricer(Pricer[] memory _pricersToReweigh, uint256 _type)
        internal
        pure
        returns (Pricer[] memory)
    {
        if (_type == 0) {
            // Reweigh due to missing pricer
            uint16 currentWeightVal;
            uint256 indexCount;
            uint16[] memory indexOfValidPricers = new uint16[](_pricersToReweigh.length);

            for (uint256 i; i < _pricersToReweigh.length; i++) {
                if (_pricersToReweigh[i].source != address(0)) {
                    indexOfValidPricers[indexCount++] = uint16(i);
                    currentWeightVal += _pricersToReweigh[i].weight;
                }
            }

            for (uint16 i; i < indexOfValidPricers.length; i++) {
                _pricersToReweigh[i].weight /= currentWeightVal;
            }
        } else if (_type == 1) {
            // Reweigh to equalize
            for (uint256 i; i < _pricersToReweigh.length; i++) {
                _pricersToReweigh[i].weight /= uint16(_pricersToReweigh.length);
            }
        }

        return _pricersToReweigh;
    }

    function _priceDeviationToleranceCheck(
        Price[] memory _prices
    ) internal view returns(Price[] memory) {
        uint256 sum;
        uint256 mean;

        for(uint256 i; i < _prices.length; i++) {
            sum += _normalize(_prices[i].price, _prices[i].source.decimalsOfPrecision, 18);
        }

        mean = sum/_prices.length;

        for(uint256 i; i < _prices.length; i++) {
            if(_prices[i].price == mean) // Prevent dividing by zero
                continue;
            int256 diff = int256(_prices[i].price - mean);
            uint256 percent = 10e18 * uint256(_abs(diff)) / ((_prices[i].price + mean) / 2) * 10000 / 10e18;
            if(percent > tolerablePriceDeviation) {
                delete _prices[i];
            }
        }
        return _prices;
    }

    function _normalize(
        uint256 _valueToNormalize,
        uint256 _valueDecimal,
        uint256 _normalDecimals
    ) internal pure returns (uint256) {
        int256 decimalDiff = int256(_valueDecimal) - int256(_normalDecimals);

        if(decimalDiff > 0) {
            return _valueToNormalize / (10**uint256(decimalDiff));
        } else if(decimalDiff < 0) {
            return _valueToNormalize * 10**uint256(-decimalDiff);
        } else {
            return _valueToNormalize;
        }
    }

    /**
     * @notice Verify the weights did not deviate too far or is out of bounds
     * @param _totalWeightValues total value of the weight
     * @return safeDeviation is true if out of bounds is false and did not deviate too far from the tolerable weight deviation
     * @return outOfBounds is true if it is above 10000 (100.00)
     */
    function _weightDeviationToleranceCheck(uint16 _totalWeightValues)
        internal
        view
        returns (bool safeDeviation, bool outOfBounds)
    {
        if(_totalWeightValues <= 10000) {
            outOfBounds = true;
        }

        if(10000 - _totalWeightValues <= tolerableWeightDeviation) {
            safeDeviation = true;
        }
    }

    /**
     * @notice Return an absolute value
     */
    function _abs(int256 _val) internal pure returns(int256) {
        return _val >= 0 ? _val: -_val;
    }
}
