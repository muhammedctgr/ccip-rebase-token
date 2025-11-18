// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IRebaseToken} from "./interfaces/IRebaseToken.sol";

contract Vault {
    // Vault contract code goes here
    // We need to pass the token address to the vault constructor
    // Create a deposit function that mints rebase tokens to the user equal to the amount deposited
    // Create a redeem function that burns rebase tokens from the user and transfers the underlying asset back to the user
    // Create a way to add rewards to the vault that will be distributed to users based on their rebase token holdings

    IRebaseToken private immutable i_rebaseToken;

    event Deposit(address indexed user, uint256 amount);
    event Redeem(address indexed user, uint256 amount);

    error Vault__RedeemFailed();

    constructor(IRebaseToken _rebaseToken) {
        i_rebaseToken = _rebaseToken;
    }

    receive() external payable {}

    /**
     * @notice - Deposit underlying asset into the vault and mint rebase tokens to the user.
     */
    function deposit() external payable {
        // Logic to handle deposits and mint rebase tokens to the user.
        uint256 interestRate = i_rebaseToken.getInterestRate();
        i_rebaseToken.mint(msg.sender, msg.value, interestRate);
        emit Deposit(msg.sender, msg.value);
    }

    /**
     * @notice - Redeem rebase tokens for the underlying asset from the vault.
     * @param _amount - The amount of rebase tokens to redeem.
     */
    function redeem(uint256 _amount) external {
        if (_amount == type(uint256).max){
            _amount = i_rebaseToken.balanceOf(msg.sender);
        }
        // burn the tokens from the user.
        i_rebaseToken.burn(msg.sender, _amount);
        // transfer the underlying asset back to the user(ETH).
        (bool success, ) = payable(msg.sender).call{value: _amount}("");
        if (!success) {
            revert Vault__RedeemFailed();
        }
        emit Redeem(msg.sender, _amount);
    }

    /**
     * @notice - Get the address of the rebase token associated with the vault.
     * @return - The address of the rebase token.
     */ 
    function getRebaseTokenAddress() external view returns (address) {
        return address(i_rebaseToken);
    }
}