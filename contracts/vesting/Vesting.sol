pragma solidity 0.8.19;

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interface/ITreasury.sol";
import "../interface/IStaking.sol";

contract VectorVest is Ownable {
    /// DEPENDENCIES ///

    using SafeERC20 for IERC20;

    /// STRUCTS ///

    struct Term {
        uint256 percent; // 4 decimals ( 5000 = 0.5% )
        uint256 indexClaimed; // Rebase-tracking number
    }

    /// STATE VARIABLES ///

    /// @notice Claim Token
    IERC20 internal immutable VEC;
    /// @notice Payment Token
    IERC20 internal immutable vETH;
    /// @notice Transfer vETH to treasury, mint VEC
    ITreasury internal immutable treasury;
    /// @notice Stake VEC for sVEC
    IStaking internal immutable staking;

    /// @notice Tracks address term info
    mapping(address => Term) public terms;
    /// @notice Tracks address change
    mapping(address => address) public walletChange;
    /// @notice Total amount allocated (4 decimals: 10000 = 1%)
    uint256 public totalAllocated;
    /// @notice Max percent can allocate. == 20%
    uint256 public maximumAllocated = 200000;
    /// @notice Timestamp percent becomes fully vested
    uint256 public fullVest;
    /// @notice Timestamp vesting started
    uint256 public startVest;

    constructor(
        address _VEC,
        address _vETH,
        address _treasury,
        address _staking
    ) {
        VEC = IERC20(_VEC);
        vETH = IERC20(_vETH);
        treasury = ITreasury(_treasury);
        staking = IStaking(_staking);

        IERC20(_VEC).approve(_staking, type(uint256).max);

        startVest = block.timestamp;
        fullVest = block.timestamp + 365 days;
    }

    /// MUTABLE FUNCTIONS ///

    /// @notice         Allows wallet to claim VEC
    /// @param _to      Address to transfer minted VEC to
    /// @param _amount  Amount of VEC to claim
    function claim(address _to, uint256 _amount) external {
        VEC.safeTransfer(_to, _claim(_amount));
    }

    /// @notice         Allows wallet to claim VEC and stake
    /// @param _to      Address to send sVEC to
    /// @param _amount  Amount to claim and stake
    function stake(address _to, uint256 _amount) external {
        staking.stake(_to, _claim(_amount));
    }

    /// INTERNAL ///

    /// @notice          Logic for claiming VEC
    /// @param _amount   Amount of vETH to send
    /// @return toSend_  Amount to send
    function _claim(uint256 _amount) internal returns (uint256 toSend_) {
        vETH.safeTransferFrom(msg.sender, address(treasury), _amount);
        toSend_ = (_amount * 1e9) / treasury.RESERVE_BACKING();
        treasury.mint(address(this), toSend_);

        require(redeemableFor(msg.sender) >= toSend_, "Claim more than vested");

        terms[msg.sender].indexClaimed += toIndexAdjusted(toSend_);
    }

    /// WALLET CHANGES ///

    /// @notice             Allows address to push terms to new address
    /// @param _newAddress  New wallets address
    function pushWalletChange(address _newAddress) external {
        require(terms[msg.sender].percent != 0, "No wallet to change");
        walletChange[msg.sender] = _newAddress;
    }

    /// @notice             Allows new address to pull terms
    /// @param _oldAddress  Old address to pull terms for
    function pullWalletChange(address _oldAddress) external {
        require(
            walletChange[_oldAddress] == msg.sender,
            "Old wallet did not push"
        );
        require(terms[msg.sender].percent == 0, "Wallet already exists");

        walletChange[_oldAddress] = address(0);
        terms[msg.sender] = terms[_oldAddress];
        delete terms[_oldAddress];
    }

    /// VIEW FUNCTIONS ///

    /// @notice       Returns % of overall vesting completed
    /// @return uint  Percent of overall vesting 1e8 == 10%
    function percentVested() public view returns (uint256) {
        if (block.timestamp > fullVest) return 1e9;

        uint256 timeSinceVestStart = block.timestamp - startVest;

        return ((1e9 * timeSinceVestStart) / 365 days);
    }

    /// @notice       Returns % of vesting an address has
    /// @return uint  Percent of vesting address has currently
    function percentAddressVested(
        address _address
    ) public view returns (uint256) {
        Term memory info = terms[_address];
        return (info.percent * percentVested()) / 1e9;
    }

    /// @notice         Converts index adjusted amount to VEC
    /// @param _amount  Index adjusted amount to get static of
    /// @return uint    Satic amount for index adjusted `_amount`
    function fromIndexAdjusted(uint256 _amount) public view returns (uint256) {
        return (_amount * staking.index()) / 1e9;
    }

    /// @notice         Converts VEC to index adjusted amount
    /// @param _amount  Static amount to get index adjusted of
    /// @return uint    Index adjusted amount for static `_amount`
    function toIndexAdjusted(uint256 _amount) public view returns (uint256) {
        return (_amount * 1e9) / staking.index();
    }

    /// @notice          View VEC redeemable for `_address`
    /// @param _address  Redeemable for address
    /// @return uint256  VEC redeemable for `_address`
    function redeemableFor(address _address) public view returns (uint256) {
        uint256 totalReedemable = (VEC.totalSupply() *
            percentAddressVested(_address)) / 1e6;

        if (totalReedemable < claimed(_address)) return 0;
        return totalReedemable - claimed(_address);
    }

    /// @notice          View VEC claimed for `_address`
    /// @param _address  Claimed for address
    /// @return uint256  VEC claimed for `_address`
    function claimed(address _address) public view returns (uint256) {
        return fromIndexAdjusted(terms[_address].indexClaimed);
    }

    /// OWNER FUNCTIONS ///

    /// @notice          Set terms for new address
    /// @notice          Cannot lower for address or exceed maximum total allocation
    /// @param _address  Address of who to set terms for
    /// @param _percent  Percent of supply can vest i.e. (10_000 = 1%)
    function setTerms(address _address, uint256 _percent) external onlyOwner {
        require(terms[_address].percent == 0, "Address already exists");
        terms[_address] = Term({percent: _percent, indexClaimed: 0});
        require(
            totalAllocated + _percent <= maximumAllocated,
            "Cannot allocate more than 20%"
        );
        totalAllocated += _percent;
    }
}
