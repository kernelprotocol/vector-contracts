pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
contract StakedVectorETH is ERC20("Staked vETH", "svETH") {

    /// EVENTS ///

    event Stake(address indexed staker, uint256 svETH);
    event Unstake(address indexed unstaker, uint256 vETHReceived);

    /// STATE VARIABLE ///

    IERC20 public immutable vETH;
    address public immutable deployer;

    /// CONSTRUCTOR ///

    constructor(IERC20 _vETH) {
        vETH = _vETH;
        deployer = msg.sender;
    }

    /// STAKE ///

    function stake(uint256 _amount) public {
        uint256 totalvETH = vETH.balanceOf(address(this));
        uint256 totalShares = totalSupply();
        if (totalShares == 0 || totalvETH == 0) {
            require(msg.sender == deployer, "Deployer to be first stake to initialize proper shares");
            _mint(_msgSender(), _amount);
            emit Stake(_msgSender(), _amount);
        } else {
            uint256 _shares = _amount * totalShares / totalvETH;
            _mint(_msgSender(), _shares);
            emit Stake(_msgSender(), _shares);
        }
        vETH.transferFrom(_msgSender(), address(this), _amount);
    }

    /// UNSTAKE ///

    function unstake(uint256 _share) public {
        uint256 totalShares = totalSupply();
        uint256 _amount =
            _share * vETH.balanceOf(address(this)) / totalShares;
        _burn(_msgSender(), _share);
        vETH.transfer(_msgSender(), _amount);
        emit Unstake(_msgSender(), _amount);
    }
}