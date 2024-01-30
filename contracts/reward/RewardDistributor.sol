// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interface/IVEC.sol";
import "../interface/IvETH.sol";
import "../interface/IWETH.sol";
import "../interface/ITreasury.sol";

/// @title   Distributor
/// @notice  VEC Staking Distributor
contract Distributor is Ownable {
    /// EVENTS ///

    event VECRateSet(uint256 oldRate, uint256 newRate);
    event vETHRewardSet(uint256 oldReward, uint256 newReward);

    /// VARIABLES ///

    /// @notice VEC address
    IERC20 public immutable VEC;
    /// @notice Treasury address
    ITreasury public immutable treasury;
    /// @notice Staking address
    address public immutable vecStaking;
    /// @notice WETH address
    address public immutable WETH;
    /// @notice vETH address
    address public immutable vETH;
    /// @notice svETH address
    address public immutable svETH;

    /// @notice In ten-thousandths ( 5000 = 0.5% )
    uint256 public vecRate;
    /// @notice Amount of WETH sent to svETH every epoch
    uint256 public svETHRewardPerEpoch;
    /// @notice Total wETH torwards ssvETH
    uint256 public historicalYield;

    uint256 public constant rateDenominator = 1_000_000;

    /// CONSTRUCTOR ///

    /// @param _treasury    Address of treasury contract
    /// @param _VEC         Address of VEC
    /// @param _vETH        Address of vETH
    /// @param _svETH       Address of svETH
    /// @param _vecStaking  Address of staking contract
    constructor(
        address _treasury,
        address _VEC,
        address _vETH,
        address _svETH,
        address _vecStaking
    ) {
        WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2;
        treasury = ITreasury(_treasury);
        VEC = IVEC(_VEC);
        vETH = _vETH;
        svETH = _svETH;
        vecStaking = _vecStaking;
    }

    /// STAKING FUNCTION ///

    /// @notice Send epoch reward to staking contract and svETH reward
    function distribute() external {
        require(msg.sender == vecStaking, "Only staking");
        treasury.mint(vecStaking, nextVECReward()); // mint and send tokens

        if (address(this).balance > 0) IWETH(WETH).deposit{value: address(this).balance}();
        if (svETHRewardPerEpoch == 0 || IERC20(WETH).balanceOf(address(this)) == 0) return;

        if(IERC20(WETH).balanceOf(address(this)) >= svETHRewardPerEpoch) {
            historicalYield += svETHRewardPerEpoch;
            IvETH(vETH).deposit(WETH, svETH, svETHRewardPerEpoch);
        } else {
            historicalYield += IERC20(WETH).balanceOf(address(this));
            IvETH(vETH).deposit(WETH, svETH, IERC20(WETH).balanceOf(address(this)));
        }
    }

    /// VIEW FUNCTIONS ///

    /// @notice          Returns next reward at given rate
    /// @param _rate     Rate
    /// @return _reward  Next reward
    function nextRewardAt(uint256 _rate) public view returns (uint256 _reward) {
        return (VEC.totalSupply() * _rate) / rateDenominator;
    }

    /// @notice          Returns next reward of staking contract
    /// @return _reward  Next reward for staking contract
    function nextVECReward() public view returns (uint256 _reward) {
        uint256 excessReserves = treasury.excessReserves();
        _reward = nextRewardAt(vecRate);
        if (excessReserves < _reward) _reward = excessReserves;
    }

    /// POLICY FUNCTIONS ///

    /// @notice             Set reward rate for rebase
    /// @param _rewardRate  New rate
    function setVECRate(uint256 _rewardRate) external onlyOwner {
        require(
            _rewardRate <= rateDenominator,
            "Rate cannot exceed denominator"
        );
        uint256 _oldRate = vecRate;
        vecRate = _rewardRate;
        emit VECRateSet(_oldRate, _rewardRate);
    }

    /// @notice            Set reward for svETH
    /// @param _newReward  New rate
    function setsvETHReward(uint256 _newReward) external onlyOwner {
        IERC20(WETH).approve(vETH, type(uint256).max);
        uint256 _oldReward = svETHRewardPerEpoch;
        svETHRewardPerEpoch = _newReward;
        emit vETHRewardSet(_oldReward, _newReward);
    }

    /// @notice Withdraw token from contract
    function withdrawToken(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).transfer(_to, _amount);
    }

    /// @notice Withdraw stuck ETH from contract
    function withdrawStuckEth(address toAddr) external onlyOwner {
        (bool success, ) = toAddr.call{value: address(this).balance}("");
        require(success);
    }

    /// RECEIVE ///

    receive() external payable {}
}
