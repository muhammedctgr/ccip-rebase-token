// SPDX-License-Identifier: MIT

pragma solidity ^0.8.24;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IRebaseToken is IERC20{
    function mint(address _to, uint256 _amount, uint256 _interestRate) external;
    function burn(address _from, uint256 _amount) external;
    function balanceOf(address _account) external view returns (uint256);
    function getInterestRate() external view returns (uint256);
    function getUserInterestRate(address _account) external view returns (uint256);
    function grantMintAndBurnRole(address _account) external;
}