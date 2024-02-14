pragma solidity 0.8.19;

import "../interface/curve/ICurveStableSwapNG.sol";
import "../interface/IvETH.sol";
import "../interface/ITreasury.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CurveRebalancer is Ownable {

    /// EVENTS ///

    event PoolBalanced (uint256 _amountRedeemed, uint256 _vETHReceived, uint256 _amountProfit);

    /// STATE VARIABLES ///

    /// @notice Address of Vector treasury
    address public constant treasury = 0x2dD568028682FF2961cC341a4849F1b32f371064;
    /// @notice Address of Curve vETH/ETH
    address public constant vETHETH = 0x6685fcFCe05e7502bf9f0AA03B36025b09374726;
    /// @notice Address of WETH
    address public constant WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
    /// @notice Address of vETH
    address public constant vETH = 0x38D64ce1Bdf1A9f24E0Ec469C9cAde61236fB4a0;

    /// @notice Total amount of profit treasury has accumuluated from rebalancing
    uint256 public totalProfitForTreasury;

    /// MUTATIVE FUNCTIONS ///

    /// @notice                 Rebalance vETH/ETH with `_amountToRedeem` WETH, receive the minimum `_minvETH` back
    /// @param _amountToRedeem  Amount of vETH to redeem for WETH to rebalance with
    /// @param _minvETH         Min amount of vETH to receive out
    function rebalance(uint256 _amountToRedeem, uint256 _minvETH) external onlyOwner {
        ITreasury(treasury).transferFromTreasury(vETH, address(this), _amountToRedeem);
        IvETH(vETH).redeem(WETH, address(this), _amountToRedeem);
        IERC20(WETH).approve(vETHETH, _amountToRedeem);
        ICurveStableSwapNG(vETHETH).exchange(1, 0, _amountToRedeem, _minvETH);

        uint256 vETHBalance = IERC20(vETH).balanceOf(address(this)) ;
        uint256 profit = vETHBalance - _amountToRedeem;

        totalProfitForTreasury += profit;

        IvETH(vETH).transfer(treasury, IERC20(vETH).balanceOf(address(this)));

        emit PoolBalanced(_amountToRedeem, vETHBalance, profit);
    }

    /// @notice Withdraw token from contract
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }
}