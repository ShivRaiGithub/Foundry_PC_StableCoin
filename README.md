# Foundry DeFi Stablecoin
Project on StableCoin from Cyfrin Foundry Course by Patrick Collins


# About

This project is meant to be a stablecoin where users can deposit WETH and WBTC in exchange for a token that will be pegged to USD. 

# Get started

Clone the repository   
Change to cloned directory   
Remember to set OWNER and PRIVATE_KEY in '.env'   


# Contracts
1) DecentralizedStableCoin : Our Stablecoin is called DecentralizedStableCoin (DSC). We are using ERC20 for the stablecoin with `mint` and `burn` facility.   
2) DSCEngine : The main contract of our project which handles all the working and management of the system. It contains the logic for most of the processes of the system like liquidating, checking for health factor of a user, etc.

# Scripts
1) DeployDSC : The main script which deploys the contracts.
2) HelperConfig : Provides network configuration

# Tests
1) mocks : Mockv3Aggregator to mock priceFeeds
2) unit : unit tests
3) fuzz : fuzz testing

# Features 
Creating a stablecoin using ERC20     
Using Chainlink Aggregators for Price feeds   
Using custom errors and events   
Using weth and wbtc as collateral   
Checking health Factor of a user   
Preventing undercollateralization   
Liquidation   
Burning and Minting DSC   
Redeeming Collateral   
View functions   

A lot of testing in form of unit tests and fuzz tests   
Deploy Scripts   
Etc   


# By
Shiv 
