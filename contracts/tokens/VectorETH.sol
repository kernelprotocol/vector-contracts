// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

contract VectorETH is ERC20, Ownable {

    /// DEPENDENCIES ///

    using SafeERC20 for IERC20;

    /// STATE VARIABLES ///

    /// @notice Array of approved restaked LSTs
    address[] public approvedRestakedLSTs;

    /// @notice Amount of total token deposited
    mapping(address => uint256) public totalRestakedLSTDeposited;
    /// @notice Amount of token managed
    mapping(address => uint256) public restakedLSTManaged;
    /// @notice Amount of vETH for token
    mapping(address => uint256) public vETHPerRestakedLST;
    /// @notice Address to send token to
    mapping(address => address) public routeRestakedLSTTo;
    /// @notice Bool if address is restaked LST
    mapping(address => bool) public restakedLST;
    /// @notice Bool if address is approved manager
    mapping(address => bool) public approvedManager;

    /// @notice Bool if redemtions are active
    bool public redemtionsActive;
    /// @notice Bool if deposits are open
    bool public depositsOpen;

    /// @notice Number of approved tokens
    uint256 public approvedTokens;

    /// EVENTS ///

    event Deposit(address indexed staker, uint256 vETHReceived);
    event Redeemed(address indexed staker, uint256 vETHBurned);
    event TokenBalanceUpdated(address indexed token, uint256 newBalance);
    event RestakedLSTAdded(address tokenAdded, uint256 vETHPerToken);
    event RestakedLSTRemoved(address tokenRemoved);
    event vETHPerTokenUpdated(address restakedLST, uint256 vETHPerToken);
    event TokenRouteUpdated(address restakedLST, address routedTo);
    event RedemtionsActivated();
    event RedemtionUnactivated();
    event ApprovedManagerAdded(address approvedManager);
    event ApprovedManagerRemoved(address removedManaged);
    event TokenManaged(address indexed byAddress, address indexed tokenManaged, uint256 amountManaged);
    event TokenManagedReaded(address indexed fromAddress, address indexed tokenAdded, uint256 amountAdded);
    event DepositsOpened();

    /// CONSTRUCTOR ///

    constructor() ERC20("Vector ETH", "vETH") {}

    /// MUTATIVE FUNCTIONS ///

    /// @notice              Deposit `_restakedLST` to receive vETH
    /// @param _restakedLST  Restaked LST to deposit
    /// @param _to           Address to send minted vETH to
    /// @param _amount       Amount of `_restakedLST` to deposit
    function deposit(
        address _restakedLST,
        address _to,
        uint256 _amount
    ) external {
        if (!depositsOpen) require(msg.sender == owner(), "Deposits not open");
        require(restakedLST[_restakedLST], "Not approved restaked LST");
        require(_amount > 0, "Can not deposit 0");
        uint256 _amountToMint = (vETHPerRestakedLST[_restakedLST] * _amount) /
            (10 ** IERC20Metadata(_restakedLST).decimals());
        _mint(_to, _amountToMint);
        emit Deposit(_to, _amountToMint);

        totalRestakedLSTDeposited[_restakedLST] += _amount;
        if (routeRestakedLSTTo[_restakedLST] == address(0)) {
            IERC20(_restakedLST).safeTransferFrom(
                _msgSender(),
                address(this),
                _amount
            );
        } else {
            IERC20(_restakedLST).safeTransferFrom(
                _msgSender(),
                routeRestakedLSTTo[_restakedLST],
                _amount
            );
            restakedLSTManaged[_restakedLST] += _amount;
        }
    }

    /// @notice                       Redeem vETH to receive `_restakedLSTToReceive`
    /// @param _restakedLSTToReceive  Restaked LST to receive
    /// @param _to                    Address to send receive redeemed `_restakedLSTToReceive`
    /// @param _vETHToRedeem          Amount of vETH to redeem
    function redeem(
        address _restakedLSTToReceive,
        address _to,
        uint256 _vETHToRedeem
    ) external {
        require(redemtionsActive, "Redemtions not active");
        require(restakedLST[_restakedLSTToReceive], "Not restaked LST");

        uint256 _restakedLSTToSend = ((10 **
            IERC20Metadata(_restakedLSTToReceive).decimals()) * _vETHToRedeem) /
            vETHPerRestakedLST[_restakedLSTToReceive];

        require(
            totalRestakedLSTDeposited[_restakedLSTToReceive] >=
                _restakedLSTToSend,
            "Not enough funds to redeem LST"
        );

        totalRestakedLSTDeposited[_restakedLSTToReceive] -= _restakedLSTToSend;
        _burn(_msgSender(), _vETHToRedeem);

        IERC20(_restakedLSTToReceive).safeTransfer(_to, _restakedLSTToSend);
        emit Redeemed(_to, _vETHToRedeem);
    }

    /// @notice              Update balaces of restaked LST
    /// @param _restakedLST  Address of restaked LST to update
    function updateDeposit(address _restakedLST) public {
        uint256 totalDepositsInContract = totalRestakedLSTDeposited[
            _restakedLST
        ] - restakedLSTManaged[_restakedLST];
        uint256 accruedLST = IERC20(_restakedLST).balanceOf(address(this)) -
            totalDepositsInContract;
        totalRestakedLSTDeposited[_restakedLST] += accruedLST;
        emit TokenBalanceUpdated(
            _restakedLST,
            totalRestakedLSTDeposited[_restakedLST]
        );
    }

    /// OWNER FUNCTION ///

    /// @notice              Add restaked LST
    /// @param _restakedLST  Address of restaked LST to add
    /// @param _vETHPerLST   Amount of vETH per `_restakedLST`
    function addRestakedLST(
        address _restakedLST,
        uint256 _vETHPerLST
    ) external onlyOwner {
        require(!restakedLST[_restakedLST], "Already added");
        restakedLST[_restakedLST] = true;
        vETHPerRestakedLST[_restakedLST] = _vETHPerLST;
        approvedRestakedLSTs.push(_restakedLST);
        ++approvedTokens;
        emit RestakedLSTAdded(_restakedLST, _vETHPerLST);
    }

    /// @notice              Remove `_restakedLST`
    /// @param _restakedLST  Address of restaked LST to remove
    function removeRestakedLST(address _restakedLST) external onlyOwner {
        require(restakedLST[_restakedLST], "Not restaked LST");
        restakedLST[_restakedLST] = false;
        vETHPerRestakedLST[_restakedLST] = 0;

        uint256 _arrLength = approvedRestakedLSTs.length;
        for (uint i; i < _arrLength; ++i) {
            if (approvedRestakedLSTs[i] == _restakedLST) {
                approvedRestakedLSTs[i] = approvedRestakedLSTs[_arrLength - 1];
                approvedRestakedLSTs.pop();
                break;
            }
        }
        --approvedTokens;

        emit RestakedLSTRemoved(_restakedLST);
    }

    /// @notice              Update amount of vETH per `_restakedLST`
    /// @param _restakedLST  Address of restaked LST to update `_vETHPerLST` for
    /// @param _vETHPerLST   Amount of vETH per `_restakedLST`
    function updatevETHPerLST(
        address _restakedLST,
        uint256 _vETHPerLST
    ) external onlyOwner {
        require(restakedLST[_restakedLST], "Not restaked LST");
        vETHPerRestakedLST[_restakedLST] = _vETHPerLST;
        emit vETHPerTokenUpdated(_restakedLST, _vETHPerLST);
    }

    /// @notice              Update address to route `_restakedLST` to
    /// @param _restakedLST  Address of restaked LST to add where to route
    /// @param _where        Address of where to route `_restakedLST`
    function updateRouteRestakedLSTTo(
        address _restakedLST,
        address _where
    ) external onlyOwner {
        require(restakedLST[_restakedLST], "Not restaked LST");
        routeRestakedLSTTo[_restakedLST] = _where;
        emit TokenRouteUpdated(_restakedLST, _where);
    }

    /// @notice  Set redemtions active
    function setRedemtionActive() external onlyOwner {
        redemtionsActive = true;
        emit RedemtionsActivated();
    }

    /// @notice  Set redemtions unactive
    function setRedemtionUnactive() external onlyOwner {
        redemtionsActive = false;
        emit RedemtionUnactivated();
    }

    /// @notice  Add approved manager
    function addApprovedManager(address _manager) external onlyOwner {
        approvedManager[_manager] = true;
        emit ApprovedManagerAdded(_manager);
    }

    /// @notice  Remove approved manage
    function removeApprovedManager(address _manager) external onlyOwner {
        approvedManager[_manager] = false;
        emit ApprovedManagerRemoved(_manager);
    }

    /// @notice         Recover tokens
    /// @param _to      Address to send recovered tokens
    /// @param _token   Address of token to recover
    /// @param _amount  Amount of token to recover
    function recoverTokens(
        address _to,
        address _token,
        uint256 _amount
    ) external onlyOwner {
        require(!restakedLST[_token], "Can Not transfer restaked LST");
        IERC20(_token).safeTransfer(_to, _amount);
    }

    /// @notice Open deposits
    function openDeposits() external onlyOwner {
        require(!depositsOpen, "Deposits already opened");
        depositsOpen = true;
        emit DepositsOpened();
    }

    /// MANAGER FUNCTIONS ///

    /// @notice              Manage restaked LST
    /// @param _restakedLST  Address of restaked LST to manage
    /// @param _to           Address of where to send `_amount` of `_restakedLST`
    /// @param _amount       Amount to manage
    function manageRestakedLST(
        address _restakedLST,
        address _to,
        uint256 _amount
    ) external {
        require(approvedManager[msg.sender], "Not approved manager");
        require(restakedLST[_restakedLST], "Not restaked LST");
        updateDeposit(_restakedLST);
        IERC20(_restakedLST).safeTransfer(_to, _amount);
        restakedLSTManaged[_restakedLST] += _amount;

        emit TokenManaged(msg.sender, _restakedLST, _amount);
    }

    /// @notice              Add back managed restaked LST
    /// @param _restakedLST  Address of restaked LST to add back
    /// @param _amount       Amount to add back manage
    function addMangedRestakedLST(
        address _restakedLST,
        uint256 _amount
    ) external {
        require(approvedManager[msg.sender], "Not approved manager");
        require(restakedLST[_restakedLST], "Not restaked LST");
        if (_amount > restakedLSTManaged[_restakedLST])
            restakedLSTManaged[_restakedLST] = 0;
        else restakedLSTManaged[_restakedLST] -= _amount;

        IERC20(_restakedLST).safeTransferFrom(msg.sender, address(this), _amount);
        emit TokenManagedReaded(msg.sender, _restakedLST, _amount);
    }

    /// VIEW FUNCTIONS ///

    /// @notice              Returns amount of `_restakedLST` the contract has, including that being managed
    /// @param _restakedLST  Address of restaked LST to check balance for
    /// @return _balance     Balance of `_restakedLST` for contract
    function currentBalance(
        address _restakedLST
    ) external view returns (uint256 _balance) {
        uint256 totalDepositsInContract = totalRestakedLSTDeposited[
            _restakedLST
        ] - restakedLSTManaged[_restakedLST];
        uint256 accruedLST = IERC20(_restakedLST).balanceOf(address(this)) -
            totalDepositsInContract;
        return totalRestakedLSTDeposited[_restakedLST] + accruedLST;
    }
}
