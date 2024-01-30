pragma solidity ^0.8.0;

import "../interface/IERC20.sol";
import "../interface/balancer/IRateProvider.sol";

/**
 * @title vETH Rate Provider
 * @notice Returns the value of svETH in terms of vETH
 */
contract svETHRateProvider is IRateProvider {
    IERC20 public immutable vETH;
    IERC20 public immutable svETH;

    constructor(address _vETH, address _svETH) {
        vETH = IERC20(_vETH);
        svETH = IERC20(_svETH);
    }

    /**
     * @return uint256  the value of svETH in terms of vETH
     */
    function getRate() external view override returns (uint256) {
        return 1e18 * vETH.balanceOf(address(svETH)) / svETH.totalSupply();
    }
}