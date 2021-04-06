// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.6.10;

import {OpynPricerInterface} from "./opyn/interfaces/OpynPricerInterface.sol";
import {SafeMath} from "@openzeppelin/contracts/math/SafeMath.sol";

/// @title Multi Pricer
/// @author Amethyst C.
/// @notice Multi Pricer pulls data from more than one source and uses a weighted average to calculate the expiration price
/// @dev Pulls data from an oracle utilizing the OpynPricerInterface
contract MultiPricer {
    using SafeMath for uint256;

    /// @dev Struct that stores price of an asset and timestamp of when it was recorded
    /// Adapted from GammaProtocol/contracts/Oracle.sol
    struct Price {
        uint256 price;
        uint256 timestamp;
        address source; // Source of the price data
    }

    /// @dev Permissioned addresses to pull price data from
    /// (key = asset) -> (value = pricer)
    mapping(address => address) internal pricers;
    /// @dev Permissioned addresses to allow to call functions
    mapping(address => bool) internal bots;
    /// @dev Opyn v2's oracle to submit price data to
    address public opynOracle;
    /// @dev The admin can represent any multi-sig wallet capable of producing calls to the contract
    address private admin;

    event PricerAdded(address asset, address pricer);
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
        opynOracle = _opynOracle;
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
    function addPricer(address _asset, address _pricer) external onlyAdmin {
        pricers[_asset] = _pricer;
        emit PricerAdded(_asset, _pricer);
    }
    /**
    * @notice Remove a pricer
    * @param _asset asset's address
    * @param _pricer pricer's address
    */
    function removePricer(address _asset, address _pricer) external onlyAdmin {
        pricers[_asset] = _pricer;
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
        require(_newOracle != address(0), "ExtraOracle: Zero address");
        opynOracle = _newOracle;
    }
    /**
    * @notice Change the contract's admin
    * @param _newAdmin new admin's address
    */
    function changeAdmin(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "ExtraOracle: Zero address");
        admin = _newAdmin;
    }
    function pushData(address _asset) external onlyBot {
        OpynPricerInterface pricer = OpynPricerInterface(pricers[_asset]);

    }
    function _onlyBot() internal view {
        require(bots[msg.sender], "ExtraOracle: Unauthorized (bot)");
    }
    function _onlyAdmin() internal view {
        require(msg.sender == admin, "ExtraOracle: Unauthorized");
    }

}