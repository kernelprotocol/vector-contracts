// SPDX-License-Identifier: AGPL-3.0
pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "../interface/IsVEC.sol";
import "../interface/IDistributor.sol";

/// @title   VECStaking
/// @notice  VEC Staking
contract VECStaking is Ownable {
    /// EVENTS ///

    event DistributorSet(address distributor);
    event Stake(address indexed from, address indexed to, uint256 amount);
    event Unstake(address indexed from, address indexed to, uint256 amount);
    event EpochTriggerd(uint256 newEpoch);

    /// DATA STRUCTURES ///

    struct Epoch {
        uint256 length; // in seconds
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    /// STATE VARIABLES ///

    /// @notice VEC address
    IERC20 public immutable VEC;
    /// @notice sVEC address
    IsVEC public immutable sVEC;

    /// @notice Current epoch details
    Epoch public epoch;

    /// @notice Distributor address
    IDistributor public distributor;

    /// CONSTRUCTOR ///

    /// @param _VEC                    Address of VEC
    /// @param _sVEC                   Address of sVEC
    /// @param _epochLength            Epoch length
    /// @param _secondsTillFirstEpoch  Seconds till first epoch starts
    constructor(
        address _VEC,
        address _sVEC,
        uint256 _epochLength,
        uint256 _secondsTillFirstEpoch
    ) {
        VEC = IERC20(_VEC);
        sVEC = IsVEC(_sVEC);

        epoch = Epoch({
            length: _epochLength,
            number: 0,
            end: block.timestamp + _secondsTillFirstEpoch,
            distribute: 0
        });
    }

    /// MUTATIVE FUNCTIONS ///

    /// @notice stake VEC
    /// @param _to address
    /// @param _amount uint
    function stake(address _to, uint256 _amount) external {
        rebase();
        VEC.transferFrom(msg.sender, address(this), _amount);
        sVEC.transfer(_to, _amount);
        emit Stake(msg.sender, _to, _amount);
    }

    /// @notice redeem sVEC for VEC
    /// @param _to address
    /// @param _amount uint
    function unstake(address _to, uint256 _amount, bool _rebase) external {
        if (_rebase) rebase();
        sVEC.transferFrom(msg.sender, address(this), _amount);
        require(
            _amount <= VEC.balanceOf(address(this)),
            "Insufficient VEC balance in contract"
        );
        VEC.transfer(_to, _amount);
        emit Unstake(msg.sender, _to, _amount);
    }

    ///@notice Trigger rebase if epoch over
    function rebase() public {
        if (epoch.end <= block.timestamp) {
            sVEC.rebase(epoch.distribute, epoch.number);

            epoch.end = epoch.end + epoch.length;
            epoch.number++;

            if (address(distributor) != address(0)) {
                distributor.distribute();
            }

            uint256 balance = VEC.balanceOf(address(this));
            uint256 staked = sVEC.circulatingSupply();

            if (balance <= staked) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance - staked;
            }
            emit EpochTriggerd(epoch.number);
        }
    }

    /// VIEW FUNCTIONS ///

    /// @notice         Returns the sVEC index, which tracks rebase growth
    /// @return index_  Index of sVEC
    function index() public view returns (uint256 index_) {
        return sVEC.index();
    }

    /// @notice           Returns econds until the next epoch begins
    /// @return seconds_  Till next epoch
    function secondsToNextEpoch() external view returns (uint256 seconds_) {
        return epoch.end > block.timestamp ? epoch.end - block.timestamp : 0;
    }

    /// MANAGERIAL FUNCTIONS ///

    /// @notice              Sets the contract address for staking
    /// @param _distributor  Distributor Address
    function setDistributor(address _distributor) external onlyOwner {
        distributor = IDistributor(_distributor);
        emit DistributorSet(_distributor);
    }
}
