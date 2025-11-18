// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {AccessControl} from "@openzeppelin/contracts/access/AccessControl.sol";

/**
* @title - Rebase Token
* @author - Hammedctgr
* @notice - This is cross-chain rebase token that incentivize users to deposit into a vault and gain interest in rewards.
* @notice - The interest rate in the smart contract can only decrease.
* @notice - Each user will have their own interest that is the global interest rate at the time of deposit.
*/

contract RebaseToken is ERC20, Ownable, AccessControl {
    error RebaseToken__InterestRateCanOnlyDecrease(uint256 oldInterestRate, uint256 newInterestRate);

    bytes32 private constant MINT_AND_BURN_ROLE = keccak256("MINT_AND_BURN_ROLE");
    uint256 private constant PRECISION_FACTOR = 1e18;
    uint256 private s_interestRate = (5 * PRECISION_FACTOR) / 1e18; // Annual interest rate in basis points (e.g., 500 = 5%)

    mapping(address => uint256) private s_userInterestRate;
    mapping(address => uint256) private s_userLastUpdatedTimestamp;
 
    event InterestRateSet(uint256 newInterestRate);

    constructor() ERC20("Rebase Token", "RBT") Ownable(msg.sender) {}

    function grantMintAndBurnRole(address _account) external onlyOwner {
        // Logic to grant mint and burn role to an account.
        _grantRole(MINT_AND_BURN_ROLE, _account);
    }

    /**
    * @notice -Set the interest rate for the rebase token.
    * @param _newInterestRate - The new interest rate to be set (in basis points).
    * @dev - The interest rate can only decrease.
    */
    function setInterestRate(uint256 _newInterestRate) external onlyOwner {
        // Logic to set a new interest rate.abi
        if (_newInterestRate >= s_interestRate) {
            revert RebaseToken__InterestRateCanOnlyDecrease(s_interestRate, _newInterestRate);
        }
        s_interestRate = _newInterestRate;
        emit InterestRateSet(_newInterestRate);
    }

    /** 
    * @notice - Get the principle balance of rebase tokens for a user.
    * @param _user - The address of the user to get the principle balance for.
    * @return - The principle balance of rebase tokens for the user.
    */
    function principleBalanceOf(address _user) external view returns (uint256) {
        return super.balanceOf(_user);
    }

    function mint(address _to, uint256 _amount, uint256 _userInterestRate) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_to);
        s_userInterestRate[_to] = _userInterestRate;
        _mint(_to, _amount);
    }

    /** 
    * @notice - Burn rebase tokens when they withdraw from the vault.
    * @param _from - The address of the user to burn tokens from.
    * @param _amount - The amount of rebase tokens to burn.
    */
    function burn(address _from, uint256 _amount) external onlyRole(MINT_AND_BURN_ROLE) {
        _mintAccruedInterest(_from);
        _burn(_from, _amount);
    }

    function balanceOf(address _user) public view override returns (uint256) {
        // Logic to calculate the current balance including accrued interest.
        return super.balanceOf(_user) * _calculateUserAccumulatedInterestSinceLastUpdate(_user) / PRECISION_FACTOR;
    } 
    /**
    * @notice - Transfer rebase tokens from one user to another user.
    * @param _recipient - The address of the recipient.
    * @param _amount - The amount of rebase tokens to transfer.
    * @return - A boolean value indicating whether the transfer was successful.
    */
    function transfer(address _recipient, uint256 _amount) public override returns (bool){
        _mintAccruedInterest(msg.sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max){
            _amount = balanceOf(msg.sender);
        }
        if (balanceOf(_recipient) == 0){
            s_userInterestRate[_recipient] = s_userInterestRate[msg.sender];
        }
        return super.transfer(_recipient, _amount);
    }

    /**
    * @notice - Transfer rebase tokens from one user to another user.
    * @param _sender - The address of the sender.
    * @param _recipient - The address of the recipient.
    * @param _amount - The amount of rebase tokens to transfer.
    * @return - A boolean value indicating whether the transfer was successful.
    */
    function transferFrom(address _sender, address _recipient, uint256 _amount) public override returns (bool) {
        _mintAccruedInterest(_sender);
        _mintAccruedInterest(_recipient);
        if (_amount == type(uint256).max){
            _amount = balanceOf(_sender);
        }
        if (balanceOf(_recipient) == 0){
            s_userInterestRate[_recipient] = s_userInterestRate[_sender];
        }
        return super.transferFrom(_sender, _recipient, _amount);
    }

    function _calculateUserAccumulatedInterestSinceLastUpdate(address _user) internal view returns (uint256 LinearInterest) {
        // Logic to calculate the accumulated interest since the last update.
        uint256 timeElapsed = block.timestamp - s_userLastUpdatedTimestamp[_user];
        LinearInterest = (PRECISION_FACTOR + (s_userInterestRate[_user] * timeElapsed));
    }

    function _mintAccruedInterest(address _user) internal {
        // find the cuurent balance of rebase tokens that have been minted to the user -> Principle Balance.
        uint256 previousPrincipleBalance = super.balanceOf(_user);
        // calculate their current balance including any interest -> balanceOf.
        uint256 currentBalance = balanceOf(_user);
        // calculate the number of tokens that need to be minted to the user -> balanceOf - tokensNeededToBeMinted
        uint256 balanceIncrease = currentBalance - previousPrincipleBalance;
        // set the user's last updated timestamp.
        s_userLastUpdatedTimestamp[_user] = block.timestamp;
        _mint(_user, balanceIncrease);
    }

    /**
    * @notice - Get the current global interest rate for the contract.
    * @return - The current global interest rate for the contract.
    */
    function getInterestRate() external view returns (uint256) {
        return s_interestRate;
    }

    /**
    * @notice - Get the current interest rate for the user.
    * @param _user - The address of the user(the user to get the interest rate for).
    * @return - The current interest rate for the user.
    */
    function getUserInterestRate(address _user) external view returns (uint256) {
        return s_userInterestRate[_user];
    }
}