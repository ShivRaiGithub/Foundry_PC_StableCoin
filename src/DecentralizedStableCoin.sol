// Layout of Contract:
// version
// imports
// errors
// interfaces, libraries, contracts
// Type declarations
// State variables
// Events
// Modifiers
// Functions

// Layout of Functions:
// constructor
// receive function (if exists)
// fallback function (if exists)
// external
// public
// internal
// private
// internal & private view & pure functions
// external & public view & pure functions


// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

// Importing necessary contracts from OpenZeppelin library
import {ERC20, ERC20Burnable} from "@openzeppelin/contracts/token/ERC20/extensions/ERC20Burnable.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";

// Defining the DecentralizedStableCoin contract
contract DecentralizedStableCoin is ERC20Burnable, Ownable {
   // Defining custom errors
   error DecentralizedStableCoin__MustBeMoreThanZero();
   error DecentralizedStableCoin__BurnAmountExceedsBalance();
   error DecentralizedStableCoin__NotZeroAddress();

   // Constructor
   constructor() Ownable() ERC20("DecentralizedStableCoin", "DSC") {}

   // Function to burn tokens
   function burn(uint256 _amount) public override onlyOwner {
       // Get the balance of the sender
       uint256 balance = balanceOf(msg.sender);
       
       // Check if the amount to burn is less than or equal to zero
       if (_amount <= 0) {
           revert DecentralizedStableCoin__MustBeMoreThanZero();
       }
       
       // Check if the balance is less than or equal to the amount to burn
       if (balance <= _amount) {
           revert DecentralizedStableCoin__BurnAmountExceedsBalance();
       }
       
       // Burn the tokens
       super.burn(_amount);
   }

   // Function to mint tokens
   function mint(address _to, uint256 _amount) external onlyOwner returns (bool) {
       // Check if the recipient address is the zero address
       if (_to == address(0)) {
           revert DecentralizedStableCoin__NotZeroAddress();
       }
       
       // Check if the amount to mint is less than or equal to zero
       if (_amount <= 0) {
           revert DecentralizedStableCoin__MustBeMoreThanZero();
       }
       
       // Mint the tokens
       _mint(_to, _amount);
       
       // Return true to indicate successful minting
       return (true);
   }
}
