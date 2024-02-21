import "../interface/IStaking.sol";
import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

pragma solidity 0.8.19;

contract gVEC is ERC20 {
    /// EVENTS ///

    event DelegateChanged(
        address indexed delegator,
        address indexed fromDelegate,
        address indexed toDelegate
    );

    event DelegateVotesChanged(
        address indexed delegate,
        uint256 previousBalance,
        uint256 newBalance
    );

    /// DATA STRUCTURES ///

    /// @notice A checkpoint for marking number of votes from a given block
    struct Checkpoint {
        uint256 fromBlock;
        uint256 votes;
    }

    /// STATE VARIABLES ///

    /// @notice sVEC address
    IERC20 public sVEC;
    /// @notice VEC address
    IERC20 public VEC;
    /// @notice Staking address
    IStaking public staking;

    /// @notice Checkpoint for checkpoint id for address
    mapping(address => mapping(uint256 => Checkpoint)) public checkpoints;
    /// @notice Num of checkpoints for address
    mapping(address => uint256) public numCheckpoints;
    /// @notice Delegator address for address
    mapping(address => address) public delegates;

    /// CONSTRUCTOR ///

    constructor(address _VEC, address _sVEC, address _staking) ERC20("Governance VEC", "gVEC") {
        require(_VEC != address(0), "Zero address: VEC");
        VEC = IERC20(_VEC);
        require(_sVEC != address(0), "Zero address: sVEC");
        sVEC = IERC20(_sVEC);
        require(_staking != address(0), "Zero address: Staking");
        staking = IStaking(_staking);
    }

    /// APPROVAL ///

    /// @notice Mass approval
    function massApproval() external {
        VEC.approve(address(staking), type(uint256).max);
        sVEC.approve(address(staking), type(uint256).max);
    }

    /// MUTATIVE FUNCTIONS ///

    /// @notice           Delegate votes from `msg.sender` to `delegatee`
    /// @param delegatee  The address to delegate votes to
    function delegate(address delegatee) external {
        return _delegate(msg.sender, delegatee);
    }

    /// @notice         Wrap sVEC
    /// @param _amount  Amount to wrap
    /// @param _to      Address to send gVEC
    function wrap(uint256 _amount, address _to) external {
        sVEC.transferFrom(msg.sender, address(this), _amount);
        _mint(_to, balanceTo(_amount));
    }

    /// @notice         Unwrap gVEC
    /// @param _amount  Amount of gVEC to unwrap
    /// @param _to      Address to send sVEC
    function unwrap(uint256 _amount, address _to) external {
        _burn(msg.sender, _amount);
        sVEC.transfer(_to, balanceFrom(_amount));
    }

    /// @notice         Stake VEC receive gVEC
    /// @param _amount  Amount of VEC to stake
    /// @param _to      Address to mint gVEC
    function stake(uint256 _amount, address _to) external {
        VEC.transferFrom(msg.sender, address(this), _amount);
        staking.stake(address(this), _amount);
        _mint(_to, balanceTo(_amount));
    }

    /// @notice         Untake gVEC receive VEC
    /// @param _amount  Amount of gVEC to unstake
    /// @param _to      Address to send VEC
    function unstake(uint256 _amount, address _to) external {
        _burn(msg.sender, _amount);
        uint256 _toUnstake = balanceFrom(_amount);
        staking.unstake(_to, _toUnstake, false);
    }

    /// VIEW FUNCTIONS ///

    /// @notice Return index from staking
    function index() public view returns (uint256) {
        return staking.index();
    }

    /// @notice         Converts index adjusted amount to VEC
    /// @param _amount  Index adjusted amount to get static of
    /// @return uint    Satic amount for index adjusted `_amount`
    function balanceFrom(uint256 _amount) public view returns (uint256) {
        return (_amount * index()) / 10 ** decimals();
    }

    /// @notice         Converts VEC to index adjusted amount
    /// @param _amount  Static amount to get index adjusted of
    /// @return uint    Index adjusted amount for static `_amount`
    function balanceTo(uint256 _amount) public view returns (uint256) {
        return (_amount * 10 ** decimals()) / index();
    }

    /// @notice         Gets the current votes balance for `account`
    /// @param account  Address to get current votes for
    /// @return uint    The number of current votes for `account`
    function getCurrentVotes(address account) external view returns (uint256) {
        uint256 nCheckpoints = numCheckpoints[account];
        return
            nCheckpoints > 0 ? checkpoints[account][nCheckpoints - 1].votes : 0;
    }

    /// @notice             Determine the prior number of votes for an account as of a block number
    /// @dev                Block number must be a finalized block or else this function will revert to prevent misinformation.
    /// @param account      The address of the account to check
    /// @param blockNumber  The block number to get the vote balance at
    /// @return uint        The number of votes the account had as of the given block
    function getPriorVotes(
        address account,
        uint256 blockNumber
    ) external view returns (uint256) {
        require(
            blockNumber < block.number,
            "gVEC::getPriorVotes: not yet determined"
        );

        uint256 nCheckpoints = numCheckpoints[account];
        if (nCheckpoints == 0) {
            return 0;
        }

        // First check most recent balance
        if (checkpoints[account][nCheckpoints - 1].fromBlock <= blockNumber) {
            return checkpoints[account][nCheckpoints - 1].votes;
        }

        // Next check implicit zero balance
        if (checkpoints[account][0].fromBlock > blockNumber) {
            return 0;
        }

        uint256 lower = 0;
        uint256 upper = nCheckpoints - 1;
        while (upper > lower) {
            uint256 center = upper - (upper - lower) / 2; // ceil, avoiding overflow
            Checkpoint memory cp = checkpoints[account][center];
            if (cp.fromBlock == blockNumber) {
                return cp.votes;
            } else if (cp.fromBlock < blockNumber) {
                lower = center;
            } else {
                upper = center - 1;
            }
        }
        return checkpoints[account][lower].votes;
    }

    /// INTERNAL FUNCTIONS ///

    function _delegate(address delegator, address delegatee) internal {
        address currentDelegate = delegates[delegator];
        uint256 delegatorBalance = balanceOf(delegator);
        delegates[delegator] = delegatee;

        emit DelegateChanged(delegator, currentDelegate, delegatee);

        _moveDelegates(currentDelegate, delegatee, delegatorBalance);
    }

    function _moveDelegates(
        address srcRep,
        address dstRep,
        uint256 amount
    ) internal {
        if (srcRep != dstRep && amount > 0) {
            if (srcRep != address(0)) {
                uint256 srcRepNum = numCheckpoints[srcRep];
                uint256 srcRepOld = srcRepNum > 0
                    ? checkpoints[srcRep][srcRepNum - 1].votes
                    : 0;
                uint256 srcRepNew = srcRepOld - amount;
                _writeCheckpoint(srcRep, srcRepNum, srcRepOld, srcRepNew);
            }

            if (dstRep != address(0)) {
                uint256 dstRepNum = numCheckpoints[dstRep];
                uint256 dstRepOld = dstRepNum > 0
                    ? checkpoints[dstRep][dstRepNum - 1].votes
                    : 0;
                uint256 dstRepNew = dstRepOld + amount;
                _writeCheckpoint(dstRep, dstRepNum, dstRepOld, dstRepNew);
            }
        }
    }

    function _writeCheckpoint(
        address delegatee,
        uint256 nCheckpoints,
        uint256 oldVotes,
        uint256 newVotes
    ) internal {
        if (
            nCheckpoints > 0 &&
            checkpoints[delegatee][nCheckpoints - 1].fromBlock == block.number
        ) {
            checkpoints[delegatee][nCheckpoints - 1].votes = newVotes;
        } else {
            checkpoints[delegatee][nCheckpoints] = Checkpoint(
                block.number,
                newVotes
            );
            numCheckpoints[delegatee] = nCheckpoints + 1;
        }

        emit DelegateVotesChanged(delegatee, oldVotes, newVotes);
    }

    /// @notice Ensure delegation moves when token is transferred.
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal override {
        _moveDelegates(delegates[from], delegates[to], amount);
    }
}
